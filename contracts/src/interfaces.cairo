use starknet::ContractAddress;
use crate::types::{Position, MarketConfig, LienOperation, OpenNoteDeposit};

/// Standard ERC-20 interface on Starknet.
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

/// Lien privacy_compute interface.
/// Called by the STRK20 Virtual OS during proof generation (not on-chain).
/// Derives the pseudonymous position identifier from the user's identity_key.
#[starknet::interface]
pub trait ILienCompute<TContractState> {
    /// Computes the deterministic position identifier for a given identity.
    ///
    /// Called by STRK20 during ComputeAndInvoke client action processing.
    /// identity_key: injected by the STRK20 Virtual OS from:
    ///   h('IDENTITY_KEY_TAG:V1', user_addr, user_private_key, LienHelper_address)
    /// position_nonce: user-selected index (0, 1, 2...) for multiple positions.
    ///
    /// Returns: position_id = Poseidon('LIEN_POSITION:V1', identity_key, position_nonce)
    fn privacy_compute(
        self: @TContractState,
        identity_key: felt252,
        position_nonce: felt252,
    ) -> felt252;
}

/// Lien privacy_invoke_with_computation interface.
/// Called on-chain by the STRK20 Privacy Pool during ServerAction::InvokeWithComputation.
#[starknet::interface]
pub trait ILienHelper<TContractState> {
    /// Executes a position state transition.
    ///
    /// ONLY callable by the configured STRK20 Privacy Pool contract.
    /// The position_id is the verified output of privacy_compute, injected
    /// by the pool as the first element of calldata (from the compute result).
    ///
    /// Returns Span<OpenNoteDeposit> for operations that produce output tokens
    /// (Borrow, WithdrawCollateral). Returns empty span for input-only operations
    /// (DepositCollateral, Repay).
    fn privacy_invoke_with_computation(
        ref self: TContractState,
        position_id: felt252,
        operation: LienOperation,
        amount: u128,
        note_id: felt252,
    ) -> (Span<OpenNoteDeposit>, Span<ContractAddress>);

    /// Public, permissionless liquidation entrypoint.
    /// NOT routed through the privacy pool — anyone can liquidate undercollateralized positions.
    fn liquidate(ref self: TContractState, position_id: felt252);
}

/// Admin interface for protocol configuration.
#[starknet::interface]
pub trait ILienAdmin<TContractState> {
    /// Sets the oracle price. Manual feed for hackathon V1.
    /// WARNING: Non-production oracle. Documented as a hackathon limitation.
    fn set_price(ref self: TContractState, price: u256);

    /// Seeds USDC liquidity into the protocol for borrowing (transfers USDC from caller).
    fn seed_liquidity(ref self: TContractState, amount: u128);

    /// Withdraws excess USDC liquidity (admin only, transfers USDC to admin).
    fn withdraw_liquidity(ref self: TContractState, amount: u128);
}

/// Read-only views for protocol state inspection.
#[starknet::interface]
pub trait ILienViews<TContractState> {
    fn get_position(self: @TContractState, position_id: felt252) -> Position;
    fn get_market_config(self: @TContractState) -> MarketConfig;
    fn get_price(self: @TContractState) -> u256;
    fn get_total_collateral(self: @TContractState) -> u128;
    fn get_total_debt(self: @TContractState) -> u128;
    fn get_available_liquidity(self: @TContractState) -> u128;
    fn get_bad_debt(self: @TContractState) -> u128;
    fn get_privacy_pool(self: @TContractState) -> ContractAddress;
}
