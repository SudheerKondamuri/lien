use starknet::ContractAddress;
use lien_contracts::types::OpenNoteDeposit;

#[starknet::interface]
pub trait IMockPrivacyPool<T> {
    fn shield_deposit(ref self: T, token: ContractAddress, amount: u128, depositor: ContractAddress);
    fn execute_deposit_collateral(
        ref self: T,
        helper: ContractAddress,
        identity_key: felt252,
        position_nonce: felt252,
        token: ContractAddress,
        amount: u128,
    );
    fn execute_borrow(
        ref self: T,
        helper: ContractAddress,
        identity_key: felt252,
        position_nonce: felt252,
        borrow_amount: u128,
        note_id: felt252,
        expected_token: ContractAddress,
    );
    fn execute_repay(
        ref self: T,
        helper: ContractAddress,
        identity_key: felt252,
        position_nonce: felt252,
        token: ContractAddress,
        repay_amount: u128,
    );
    fn execute_withdraw_collateral(
        ref self: T,
        helper: ContractAddress,
        identity_key: felt252,
        position_nonce: felt252,
        withdraw_amount: u128,
        note_id: felt252,
        expected_token: ContractAddress,
    );
    fn get_open_note_balance(self: @T, note_id: felt252) -> u128;
    fn get_open_note_token(self: @T, note_id: felt252) -> ContractAddress;
}

#[starknet::contract]
pub mod MockPrivacyPool {
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use lien_contracts::interfaces::{
        IERC20Dispatcher, IERC20DispatcherTrait, ILienComputeDispatcher,
        ILienComputeDispatcherTrait, ILienHelperDispatcher, ILienHelperDispatcherTrait,
    };
    use lien_contracts::types::{LienOperation, OpenNoteDeposit};

    #[storage]
    struct Storage {
        open_note_balances: Map<felt252, u128>,
        open_note_tokens: Map<felt252, ContractAddress>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl MockPrivacyPoolImpl of super::IMockPrivacyPool<ContractState> {
        fn shield_deposit(
            ref self: ContractState,
            token: ContractAddress,
            amount: u128,
            depositor: ContractAddress,
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token };
            let pool = get_contract_address();
            let ok = erc20.transfer_from(depositor, pool, amount.into());
            assert(ok, 'shield_transfer_from_failed');
        }

        fn execute_deposit_collateral(
            ref self: ContractState,
            helper: ContractAddress,
            identity_key: felt252,
            position_nonce: felt252,
            token: ContractAddress,
            amount: u128,
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token };
            // Step 1: Privacy Pool executes TransferTo (transfer to LienHelper)
            let ok = erc20.transfer(helper, amount.into());
            assert(ok, 'transfer_to_lien_failed');

            // Step 2: Privacy Pool derives position_id via privacy_compute
            let compute = ILienComputeDispatcher { contract_address: helper };
            let position_id = compute.privacy_compute(identity_key, position_nonce);

            // Step 3: Privacy Pool calls privacy_invoke_with_computation on LienHelper
            let lien = ILienHelperDispatcher { contract_address: helper };
            let (deposits, _) = lien
                .privacy_invoke_with_computation(
                    position_id, LienOperation::DepositCollateral, amount, 0,
                );

            // Step 4: Validate expected return data
            assert(deposits.len() == 0, 'unexpected_open_notes');
        }

        fn execute_borrow(
            ref self: ContractState,
            helper: ContractAddress,
            identity_key: felt252,
            position_nonce: felt252,
            borrow_amount: u128,
            note_id: felt252,
            expected_token: ContractAddress,
        ) {
            // Step 1: Derive position_id
            let compute = ILienComputeDispatcher { contract_address: helper };
            let position_id = compute.privacy_compute(identity_key, position_nonce);

            // Step 2: Call privacy_invoke_with_computation
            let lien = ILienHelperDispatcher { contract_address: helper };
            let (deposits, _) = lien
                .privacy_invoke_with_computation(
                    position_id, LienOperation::Borrow, borrow_amount, note_id,
                );

            // Step 3: Inspect OpenNoteDeposit instruction
            assert(deposits.len() == 1, 'expected_1_deposit');
            let dep = *deposits.at(0);
            assert(dep.note_id == note_id, 'wrong_note_id');
            assert(dep.token == expected_token, 'wrong_token');
            assert(dep.amount == borrow_amount, 'wrong_amount');

            // Step 4: Privacy Pool pulls tokens from LienHelper (consumes allowance)
            let erc20 = IERC20Dispatcher { contract_address: dep.token };
            let pool = get_contract_address();
            let ok = erc20.transfer_from(helper, pool, dep.amount.into());
            assert(ok, 'pool_pull_borrow_failed');

            // Step 5: Credit the open note inside the pool
            let curr = self.open_note_balances.read(note_id);
            self.open_note_balances.write(note_id, curr + dep.amount);
            self.open_note_tokens.write(note_id, dep.token);
        }

        fn execute_repay(
            ref self: ContractState,
            helper: ContractAddress,
            identity_key: felt252,
            position_nonce: felt252,
            token: ContractAddress,
            repay_amount: u128,
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token };
            // Step 1: Privacy Pool transfers repayment tokens to LienHelper
            let ok = erc20.transfer(helper, repay_amount.into());
            assert(ok, 'transfer_to_lien_failed');

            // Step 2: Derive position_id
            let compute = ILienComputeDispatcher { contract_address: helper };
            let position_id = compute.privacy_compute(identity_key, position_nonce);

            // Step 3: Invoke LienHelper Repay
            let lien = ILienHelperDispatcher { contract_address: helper };
            let (deposits, _) = lien
                .privacy_invoke_with_computation(
                    position_id, LienOperation::Repay, repay_amount, 0,
                );

            assert(deposits.len() == 0, 'unexpected_open_notes');
        }

        fn execute_withdraw_collateral(
            ref self: ContractState,
            helper: ContractAddress,
            identity_key: felt252,
            position_nonce: felt252,
            withdraw_amount: u128,
            note_id: felt252,
            expected_token: ContractAddress,
        ) {
            // Step 1: Derive position_id
            let compute = ILienComputeDispatcher { contract_address: helper };
            let position_id = compute.privacy_compute(identity_key, position_nonce);

            // Step 2: Call privacy_invoke_with_computation
            let lien = ILienHelperDispatcher { contract_address: helper };
            let (deposits, _) = lien
                .privacy_invoke_with_computation(
                    position_id, LienOperation::WithdrawCollateral, withdraw_amount, note_id,
                );

            // Step 3: Inspect OpenNoteDeposit instruction
            assert(deposits.len() == 1, 'expected_1_deposit');
            let dep = *deposits.at(0);
            assert(dep.note_id == note_id, 'wrong_note_id');
            assert(dep.token == expected_token, 'wrong_token');
            assert(dep.amount == withdraw_amount, 'wrong_amount');

            // Step 4: Privacy Pool pulls tokens from LienHelper (consumes allowance)
            let erc20 = IERC20Dispatcher { contract_address: dep.token };
            let pool = get_contract_address();
            let ok = erc20.transfer_from(helper, pool, dep.amount.into());
            assert(ok, 'pool_pull_withdraw_failed');

            // Step 5: Credit the open note inside the pool
            let curr = self.open_note_balances.read(note_id);
            self.open_note_balances.write(note_id, curr + dep.amount);
            self.open_note_tokens.write(note_id, dep.token);
        }

        fn get_open_note_balance(self: @ContractState, note_id: felt252) -> u128 {
            self.open_note_balances.read(note_id)
        }

        fn get_open_note_token(self: @ContractState, note_id: felt252) -> ContractAddress {
            self.open_note_tokens.read(note_id)
        }
    }
}
