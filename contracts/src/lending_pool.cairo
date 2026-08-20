#[starknet::contract]
pub mod LendingPool {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use lien_contracts::types::{Position, LoanTerms};
    use lien_contracts::interfaces::{
        ILendingPool, ISTRK20PoolDispatcher, ISTRK20PoolDispatcherTrait
    };

    #[storage]
    struct Storage {
        admin: ContractAddress,
        loan_terms: LoanTerms,
        positions: legacy_map::LegacyMap<felt252, Position>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollateralDeposited: CollateralDeposited,
        Borrowed: Borrowed,
        Repaid: Repaid,
        Liquidated: Liquidated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralDeposited {
        pub position_id: felt252,
        pub amount: u256,
        pub new_collateral: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Borrowed {
        pub position_id: felt252,
        pub amount: u256,
        pub new_debt: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Repaid {
        pub position_id: felt252,
        pub amount: u256,
        pub remaining_debt: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Liquidated {
        pub position_id: felt252,
        pub debt_covered: u256,
        pub collateral_seized: u256,
        pub liquidator_shielded: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        collateral_pool: ContractAddress,
        borrow_pool: ContractAddress,
        max_ltv_bps: u16,
        liquidation_threshold_bps: u16,
        interest_rate_bps: u16,
    ) {
        self.admin.write(admin);
        self.loan_terms.write(
            LoanTerms {
                collateral_pool,
                borrow_pool,
                max_ltv_bps,
                liquidation_threshold_bps,
                interest_rate_bps,
            }
        );
    }

    #[abi(embed_v0)]
    impl LendingPoolImpl of ILendingPool<ContractState> {
        fn deposit_collateral(ref self: ContractState, position_id: felt252, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            assert(position_id != 0, 'Invalid position_id');

            let terms = self.loan_terms.read();
            let mut pos = self.positions.read(position_id);
            let timestamp = get_block_timestamp();

            // Route deposit verification through STRK20 collateral pool primitive
            let collateral_pool = ISTRK20PoolDispatcher { contract_address: terms.collateral_pool };
            collateral_pool.transfer_shielded_from(position_id, position_id, amount);

            if pos.owner == 0 {
                pos.owner = position_id;
            }

            pos.collateral_amount += amount;
            pos.last_update_timestamp = timestamp;
            self.positions.write(position_id, pos);

            self.emit(
                CollateralDeposited {
                    position_id,
                    amount,
                    new_collateral: pos.collateral_amount,
                }
            );
        }

        fn borrow(ref self: ContractState, position_id: felt252, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let terms = self.loan_terms.read();
            let mut pos = self.positions.read(position_id);
            assert(pos.owner != 0, 'Position does not exist');

            let timestamp = get_block_timestamp();
            let new_debt = pos.borrowed_amount + amount;

            // Maximum allowed borrow capacity based on shielded collateral & LTV
            // max_borrow = (collateral * max_ltv_bps) / 10000
            let max_borrow = (pos.collateral_amount * terms.max_ltv_bps.into()) / 10000;
            assert(new_debt <= max_borrow, 'Exceeds max LTV capacity');

            // Route debt disbursement as a private shielded transfer to borrower's shielded reference
            let borrow_pool = ISTRK20PoolDispatcher { contract_address: terms.borrow_pool };
            borrow_pool.transfer_shielded_from(0, position_id, amount);

            pos.borrowed_amount = new_debt;
            pos.last_update_timestamp = timestamp;
            self.positions.write(position_id, pos);

            self.emit(
                Borrowed {
                    position_id,
                    amount,
                    new_debt: pos.borrowed_amount,
                }
            );
        }

        fn repay(ref self: ContractState, position_id: felt252, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let terms = self.loan_terms.read();
            let mut pos = self.positions.read(position_id);
            assert(pos.owner != 0, 'Position does not exist');
            assert(pos.borrowed_amount >= amount, 'Repayment exceeds debt');

            let timestamp = get_block_timestamp();

            // Route debt recovery through STRK20 borrow pool primitive
            let borrow_pool = ISTRK20PoolDispatcher { contract_address: terms.borrow_pool };
            borrow_pool.transfer_shielded_from(position_id, 0, amount);

            pos.borrowed_amount -= amount;
            pos.last_update_timestamp = timestamp;
            self.positions.write(position_id, pos);

            self.emit(
                Repaid {
                    position_id,
                    amount,
                    remaining_debt: pos.borrowed_amount,
                }
            );
        }

        fn liquidate(
            ref self: ContractState,
            position_id: felt252,
            debt_to_cover: u256,
            liquidator_shielded_recipient: felt252,
        ) {
            assert(debt_to_cover > 0, 'Debt to cover must be > 0');
            assert(liquidator_shielded_recipient != 0, 'Invalid liquidator reference');

            let terms = self.loan_terms.read();
            let mut pos = self.positions.read(position_id);
            assert(pos.owner != 0, 'Position does not exist');

            // Liquidation threshold validation
            // liquidation_limit = (collateral * liquidation_threshold_bps) / 10000
            let liquidation_limit = (pos.collateral_amount * terms.liquidation_threshold_bps.into()) / 10000;
            assert(pos.borrowed_amount > liquidation_limit, 'Position is healthy');
            assert(debt_to_cover <= pos.borrowed_amount, 'Coverage exceeds total debt');

            // Calculate collateral to seize (with 5% liquidation bonus)
            let collateral_to_seize = (debt_to_cover * 105) / 100;
            assert(collateral_to_seize <= pos.collateral_amount, 'Seizure exceeds collateral');

            let timestamp = get_block_timestamp();

            // Repay debt via STRK20 borrow pool
            let borrow_pool = ISTRK20PoolDispatcher { contract_address: terms.borrow_pool };
            borrow_pool.transfer_shielded_from(liquidator_shielded_recipient, 0, debt_to_cover);

            // Transfer seized collateral to liquidator's shielded note in collateral pool
            let collateral_pool = ISTRK20PoolDispatcher { contract_address: terms.collateral_pool };
            collateral_pool.transfer_shielded_from(position_id, liquidator_shielded_recipient, collateral_to_seize);

            pos.borrowed_amount -= debt_to_cover;
            pos.collateral_amount -= collateral_to_seize;
            pos.last_update_timestamp = timestamp;
            self.positions.write(position_id, pos);

            self.emit(
                Liquidated {
                    position_id,
                    debt_covered: debt_to_cover,
                    collateral_seized: collateral_to_seize,
                    liquidator_shielded: liquidator_shielded_recipient,
                }
            );
        }

        fn get_position(self: @ContractState, position_id: felt252) -> Position {
            self.positions.read(position_id)
        }

        fn get_loan_terms(self: @ContractState) -> LoanTerms {
            self.loan_terms.read()
        }
    }
}
