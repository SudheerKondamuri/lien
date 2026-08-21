use starknet::ContractAddress;

/// Lifecycle status for a lending position.
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug, Default)]
pub enum PositionStatus {
    #[default]
    Inactive,
    Active,
    Closed,
}

/// Position state stored on-chain keyed by position_id.
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug, Default)]
pub struct Position {
    /// Collateral token amount in token's base units (e.g. 10^18 for STRK).
    pub collateral: u128,
    /// Outstanding debt in debt token's base units (e.g. 10^6 for USDC).
    pub debt: u128,
    /// Block timestamp (in seconds) of the last state update / interest accrual.
    pub last_updated: u64,
    /// Lifecycle status of the position.
    pub status: PositionStatus,
}

/// Market parameters for Lien V1 single market (STRK collateral / USDC debt).
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct MarketConfig {
    /// ERC-20 contract address for collateral (STRK).
    pub collateral_token: ContractAddress,
    /// ERC-20 contract address for debt (USDC).
    pub debt_token: ContractAddress,
    /// Max Loan-To-Value in basis points (e.g. 7500 = 75.00%).
    pub max_ltv_bps: u16,
    /// Liquidation threshold in basis points (e.g. 8500 = 85.00%).
    pub liquidation_threshold_bps: u16,
    /// Liquidation bonus reward in basis points (e.g. 500 = 5.00%).
    pub liquidation_bonus_bps: u16,
    /// Annual interest rate in basis points (e.g. 500 = 5.00%).
    pub interest_rate_bps: u16,
}

/// Operation discriminant for privacy_invoke_with_computation.
#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub enum LienOperation {
    DepositCollateral,
    Borrow,
    Repay,
    WithdrawCollateral,
}

/// Deposit instructions returned to the STRK20 Privacy Pool.
/// Matches exact layout of privacy::objects::OpenNoteDeposit in starknet-privacy.
#[derive(Drop, Serde, starknet::Store, PartialEq, Debug, Copy)]
pub struct OpenNoteDeposit {
    pub note_id: felt252,
    pub token: ContractAddress,
    pub amount: u128,
}

/// Output breakdown from liquidation calculation.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct LiquidationResult {
    /// Amount of collateral tokens seized and transferred to the liquidator.
    pub collateral_seized: u128,
    /// Amount of debt covered and repaid into the available liquidity.
    pub debt_repaid: u128,
    /// Amount of debt unrecovered (if collateral was insufficient) recognized as bad debt.
    pub bad_debt_incurred: u128,
}
