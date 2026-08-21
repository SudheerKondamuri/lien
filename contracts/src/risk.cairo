/// Pure math functions for collateral risk calculations.
///
/// Unit derivation for STRK/USDC with oracle price:
///   STRK decimals:   18
///   USDC decimals:    6
///   Oracle decimals: 18  (price = USDC_per_STRK * 10^18)
///
///   collateral_value_usdc = (collateral * price) / DECIMAL_SCALING
///   where DECIMAL_SCALING = 10^(collateral_decimals + oracle_decimals - debt_decimals)
///                         = 10^(18 + 18 - 6) = 10^30
///
/// All intermediate arithmetic uses u256 to avoid overflow.

/// 10^30 = 10^(18 + 18 - 6).
/// Converts (STRK_base_units * oracle_price_18_decimals) → USDC_base_units.
pub const DECIMAL_SCALING: u256 = 1_000_000_000_000_000_000_000_000_000_000;

/// Basis points denominator: 10_000 = 100.00%.
pub const BPS_DENOMINATOR: u256 = 10_000;

/// Computes the value of `collateral` (in collateral base units) denominated in
/// debt token base units, given `price` (collateral/debt oracle price, 18 decimals).
///
/// Formula: collateral_value = (collateral * price) / DECIMAL_SCALING
///
/// Returns 0 if price is 0 (caller should validate separately).
pub fn collateral_value_in_debt(collateral: u128, price: u256) -> u256 {
    let collateral_u256: u256 = collateral.into();
    (collateral_u256 * price) / DECIMAL_SCALING
}

/// Computes the maximum debt a position may hold given its collateral
/// value (already in debt units) and the max LTV in basis points.
///
/// Formula: max_debt = (collateral_value_usdc * max_ltv_bps) / 10_000
pub fn max_debt_for_collateral_value(collateral_value_usdc: u256, max_ltv_bps: u16) -> u256 {
    let ltv: u256 = max_ltv_bps.into();
    (collateral_value_usdc * ltv) / BPS_DENOMINATOR
}

/// Returns true if a position is liquidatable: debt exceeds the liquidation
/// threshold applied to the collateral's debt-denominated value.
///
/// liquidatable iff debt > (collateral_value_usdc * liquidation_threshold_bps) / 10_000
pub fn is_liquidatable(
    collateral_value_usdc: u256, debt: u128, liquidation_threshold_bps: u16,
) -> bool {
    let threshold: u256 = liquidation_threshold_bps.into();
    let max_safe_debt = (collateral_value_usdc * threshold) / BPS_DENOMINATOR;
    let debt_u256: u256 = debt.into();
    debt_u256 > max_safe_debt
}

/// Converts a debt amount back into collateral base units using the oracle price.
///
/// Formula: collateral_units = (debt_amount * DECIMAL_SCALING) / price
///
/// Used in liquidation to determine how much collateral to seize.
/// Panics if price is zero.
pub fn debt_to_collateral_units(debt_amount: u256, price: u256) -> u256 {
    assert(price > 0, 'ZERO_PRICE');
    (debt_amount * DECIMAL_SCALING) / price
}
