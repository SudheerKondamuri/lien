use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Position {
    // Shielded reference / commitment identifying the position owner privately
    pub owner: felt252,
    // Amount of collateral shielded into the lending pool
    pub collateral_amount: u256,
    // Outstanding borrowed debt amount
    pub borrowed_amount: u256,
    // Timestamp of the last position state modification
    pub last_update_timestamp: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct LoanTerms {
    // Contract address of the STRK20 Shielded Collateral Pool
    pub collateral_pool: ContractAddress,
    // Contract address of the STRK20 Shielded Borrow Pool
    pub borrow_pool: ContractAddress,
    // Maximum Loan-To-Value ratio in basis points (e.g. 7500 = 75%)
    pub max_ltv_bps: u16,
    // Liquidation threshold in basis points (e.g. 8500 = 85%)
    pub liquidation_threshold_bps: u16,
    // Annualized borrow interest rate in basis points (e.g. 500 = 5%)
    pub interest_rate_bps: u16,
}
