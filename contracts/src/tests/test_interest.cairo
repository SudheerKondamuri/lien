use lien_contracts::interest::{
    compute_accrued_interest,
    apply_interest,
};

// ============================================================
// Constants
// ============================================================

const ONE_USDC: u128 = 1_000_000; // 10^6
const ONE_YEAR: u64 = 31_536_000; // 365 * 24 * 60 * 60
const HALF_YEAR: u64 = 15_768_000;
const ONE_DAY: u64 = 86_400;

// ============================================================
// compute_accrued_interest tests
// ============================================================

#[test]
fn test_interest_zero_debt() {
    let interest = compute_accrued_interest(0, 500, ONE_YEAR);
    assert(interest == 0, 'zero_debt_zero_interest');
}

#[test]
fn test_interest_zero_rate() {
    let interest = compute_accrued_interest(1000 * ONE_USDC, 0, ONE_YEAR);
    assert(interest == 0, 'zero_rate_zero_interest');
}

#[test]
fn test_interest_zero_time() {
    let interest = compute_accrued_interest(1000 * ONE_USDC, 500, 0);
    assert(interest == 0, 'zero_time_zero_interest');
}

#[test]
fn test_interest_1000_usdc_5pct_1_year() {
    // 1000 USDC at 5% (500 bps) for 1 year = 50 USDC = 50_000_000 base units
    let debt = 1000 * ONE_USDC;
    let interest = compute_accrued_interest(debt, 500, ONE_YEAR);
    assert(interest == 50 * ONE_USDC, 'wrong_1000_5pct_1yr');
}

#[test]
fn test_interest_1000_usdc_5pct_half_year() {
    // 1000 USDC at 5% for 6 months = 25 USDC = 25_000_000 base units
    let debt = 1000 * ONE_USDC;
    let interest = compute_accrued_interest(debt, 500, HALF_YEAR);
    assert(interest == 25 * ONE_USDC, 'wrong_1000_5pct_half');
}

#[test]
fn test_interest_1000_usdc_10pct_1_year() {
    // 1000 USDC at 10% (1000 bps) for 1 year = 100 USDC
    let debt = 1000 * ONE_USDC;
    let interest = compute_accrued_interest(debt, 1000, ONE_YEAR);
    assert(interest == 100 * ONE_USDC, 'wrong_1000_10pct');
}

#[test]
fn test_interest_small_debt_short_time() {
    // 1 USDC (1_000_000) at 5% for 1 day
    // = 1_000_000 * 500 * 86400 / (10000 * 31536000)
    // = 43_200_000_000_000 / 315_360_000_000
    // = 136 (truncated from 136.98...)
    let interest = compute_accrued_interest(ONE_USDC, 500, ONE_DAY);
    assert(interest == 136, 'wrong_small_short');
}

#[test]
fn test_interest_truncates_toward_zero() {
    // Very small: 1 base unit at 1 bps for 1 second
    // = 1 * 1 * 1 / (10000 * 31536000) = 1 / 315360000000 = 0
    let interest = compute_accrued_interest(1, 1, 1);
    assert(interest == 0, 'should_truncate_zero');
}

// ============================================================
// apply_interest tests
// ============================================================

#[test]
fn test_apply_interest_adds_correctly() {
    let debt = 1000 * ONE_USDC;
    let new_debt = apply_interest(debt, 500, ONE_YEAR);
    // 1000 + 50 = 1050 USDC = 1_050_000_000
    assert(new_debt == 1050 * ONE_USDC, 'wrong_apply');
}

#[test]
fn test_apply_interest_zero_elapsed() {
    let debt = 1000 * ONE_USDC;
    let new_debt = apply_interest(debt, 500, 0);
    assert(new_debt == debt, 'zero_time_unchanged');
}

#[test]
fn test_apply_interest_idempotent_at_zero_rate() {
    let debt = 1000 * ONE_USDC;
    let new_debt = apply_interest(debt, 0, ONE_YEAR);
    assert(new_debt == debt, 'zero_rate_unchanged');
}

// ============================================================
// Precision and large value tests
// ============================================================

#[test]
fn test_interest_max_reasonable_debt() {
    // 1 billion USDC at 50% for 1 year
    // = 1_000_000_000 * 10^6 * 5000 / (10000 * 31536000)
    // = 500_000_000 * 10^6 = 500M USDC
    let debt: u128 = 1_000_000_000 * ONE_USDC;
    let interest = compute_accrued_interest(debt, 5000, ONE_YEAR);
    let expected: u128 = 500_000_000 * ONE_USDC;
    assert(interest == expected, 'wrong_large_debt');
}
