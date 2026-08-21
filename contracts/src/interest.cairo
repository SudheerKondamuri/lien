/// Pure math for linear interest accrual.
///
/// Formula:
///   accrued_interest = (debt * interest_rate_bps * elapsed_seconds) / (BPS_DENOM * SECONDS_PER_YEAR)
///
/// All intermediate arithmetic uses u256 to avoid overflow.
/// The result is truncated back to u128 (checked conversion).

/// Seconds in a standard year (365 days).
pub const SECONDS_PER_YEAR: u256 = 31_536_000;

/// Basis points denominator.
pub const BPS_DENOMINATOR: u256 = 10_000;

/// Computes accrued interest on `debt` over `elapsed_seconds` at `interest_rate_bps`.
///
/// Returns the interest amount in debt token base units.
/// Truncates toward zero (no rounding up against the borrower).
///
/// Returns 0 if debt, rate, or elapsed time is 0.
pub fn compute_accrued_interest(
    debt: u128, interest_rate_bps: u16, elapsed_seconds: u64,
) -> u128 {
    if debt == 0 || interest_rate_bps == 0 || elapsed_seconds == 0 {
        return 0;
    }

    let debt_u256: u256 = debt.into();
    let rate_u256: u256 = interest_rate_bps.into();
    let elapsed_u256: u256 = elapsed_seconds.into();

    let numerator = debt_u256 * rate_u256 * elapsed_u256;
    let denominator = BPS_DENOMINATOR * SECONDS_PER_YEAR;
    let interest_u256 = numerator / denominator;

    // Checked conversion: u256 -> u128
    // In practice, interest on a u128 debt over reasonable time periods
    // will never exceed u128. But we verify defensively.
    let result: u128 = interest_u256.try_into().expect('INTEREST_OVERFLOW');
    result
}

/// Applies accrued interest to a debt principal, returning the new total debt.
///
/// new_debt = debt + accrued_interest
///
/// Panics on overflow (u128 debt space exhausted — would indicate protocol insolvency).
pub fn apply_interest(debt: u128, interest_rate_bps: u16, elapsed_seconds: u64) -> u128 {
    let interest = compute_accrued_interest(debt, interest_rate_bps, elapsed_seconds);
    let new_debt: u256 = debt.into() + interest.into();
    let result: u128 = new_debt.try_into().expect('DEBT_OVERFLOW');
    result
}
