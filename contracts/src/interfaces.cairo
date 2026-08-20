use starknet::ContractAddress;
use lien_contracts::types::{Position, LoanTerms};

#[starknet::interface]
pub trait ISTRK20Pool<TContractState> {
    // Shield tokens into the pool on behalf of a shielded recipient
    fn shield_deposit(ref self: TContractState, amount: u256, shielded_recipient: felt252);

    // Private transfer within the shielded pool
    fn shielded_transfer(
        ref self: TContractState,
        proof: Span<felt252>,
        root: felt252,
        nullifier: felt252,
        output_commitments: Span<felt252>,
    );

    // Transfer shielded tokens from pool reserve to shielded recipient
    fn transfer_shielded_from(
        ref self: TContractState,
        from_shielded: felt252,
        to_shielded: felt252,
        amount: u256,
    );

    // Unshield tokens to a public Starknet recipient address
    fn unshield_withdraw(
        ref self: TContractState,
        amount: u256,
        recipient: ContractAddress,
        proof: Span<felt252>,
        nullifier: felt252,
    );

    // Retrieve pool token asset address
    fn get_underlying_asset(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
pub trait ILendingPool<TContractState> {
    // Deposit collateral into position via STRK20 shielded pool
    fn deposit_collateral(ref self: TContractState, position_id: felt252, amount: u256);

    // Borrow debt assets against shielded collateral
    fn borrow(ref self: TContractState, position_id: felt252, amount: u256);

    // Repay borrowed debt assets via STRK20 shielded pool
    fn repay(ref self: TContractState, position_id: felt252, amount: u256);

    // Liquidate undercollateralized position
    fn liquidate(
        ref self: TContractState,
        position_id: felt252,
        debt_to_cover: u256,
        liquidator_shielded_recipient: felt252,
    );

    // Read position details by shielded position identifier
    fn get_position(self: @TContractState, position_id: felt252) -> Position;

    // Read active loan terms
    fn get_loan_terms(self: @TContractState) -> LoanTerms;
}
