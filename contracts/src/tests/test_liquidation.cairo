use lien_contracts::liquidation::compute_liquidation;

// ============================================================
// Constants
// ============================================================

const ONE_STRK: u128 = 1_000_000_000_000_000_000; // 10^18
const ONE_USDC: u128 = 1_000_000; // 10^6

// Oracle prices (18 decimals)
const PRICE_100: u256 = 1_000_000_000_000_000_000; // $1.00
const PRICE_050: u256 = 500_000_000_000_000_000;   // $0.50
const PRICE_200: u256 = 2_000_000_000_000_000_000; // $2.00

// Liquidation bonus: 5% = 500 bps
const BONUS_500: u16 = 500;
// Liquidation bonus: 10% = 1000 bps
const BONUS_1000: u16 = 1000;

// ============================================================
// Sufficient collateral cases (no bad debt)
// ============================================================

#[test]
fn test_liquidation_sufficient_collateral_1dollar() {
    // 1000 STRK collateral at $1.00
    // Debt: 500 USDC
    // Bonus: 5%
    //
    // required_collateral = (500 * 10^6 * 10500 * 10^30) / (10000 * 10^18)
    //                     = (500 * 10500 * 10^36) / (10^22)
    //                     = 525 * 10^18 = 525 STRK
    let result = compute_liquidation(
        1000 * ONE_STRK,   // collateral
        500 * ONE_USDC,    // debt
        PRICE_100,         // price
        BONUS_500,         // bonus
    );
    assert(result.collateral_seized == 525 * ONE_STRK, 'wrong_seized_suf');
    assert(result.debt_repaid == 500 * ONE_USDC, 'wrong_repaid_suf');
    assert(result.bad_debt_incurred == 0, 'no_bad_debt_suf');
}

#[test]
fn test_liquidation_sufficient_at_2_dollars() {
    // 100 STRK at $2.00
    // Debt: 100 USDC
    // Bonus: 5%
    //
    // required = (100 * 10^6 * 10500 * 10^30) / (10000 * 2 * 10^18)
    //          = (100 * 10500 * 10^36) / (2 * 10^22)
    //          = 52.5 * 10^18 = 52.5 STRK
    let result = compute_liquidation(
        100 * ONE_STRK,
        100 * ONE_USDC,
        PRICE_200,
        BONUS_500,
    );
    // 52.5 STRK = 52_500_000_000_000_000_000
    assert(result.collateral_seized == 52_500_000_000_000_000_000, 'wrong_seized_2d');
    assert(result.debt_repaid == 100 * ONE_USDC, 'wrong_repaid_2d');
    assert(result.bad_debt_incurred == 0, 'no_bad_debt_2d');
}

// ============================================================
// Insufficient collateral (bad debt) cases
// ============================================================

#[test]
fn test_liquidation_insufficient_collateral() {
    // 10 STRK at $1.00 (= $10 collateral value)
    // Debt: 20 USDC (way underwater)
    // Bonus: 5%
    //
    // required = (20 * 10^6 * 10500 * 10^30) / (10000 * 10^18)
    //          = 21 * 10^18 = 21 STRK (need 21, have 10)
    //
    // All 10 STRK seized.
    // debt_covered = (10 * 10^18 * 10^18 * 10000) / (10500 * 10^30)
    //              = (10^37 * 10000) / (10500 * 10^30)
    //              = 10^41 / (10500 * 10^30)
    //              = 10^11 / 10500
    //              = 9_523_809 (truncated) → ~9.52 USDC
    // bad_debt = 20_000_000 - 9_523_809 = 10_476_191
    let result = compute_liquidation(
        10 * ONE_STRK,
        20 * ONE_USDC,
        PRICE_100,
        BONUS_500,
    );
    assert(result.collateral_seized == 10 * ONE_STRK, 'wrong_seized_insuf');
    assert(result.debt_repaid == 9_523_809, 'wrong_repaid_insuf');
    assert(result.bad_debt_incurred == 20 * ONE_USDC - 9_523_809, 'wrong_bad_debt');
}

#[test]
fn test_liquidation_all_bad_debt_zero_collateral() {
    // 0 collateral, 100 USDC debt
    let result = compute_liquidation(0, 100 * ONE_USDC, PRICE_100, BONUS_500);
    assert(result.collateral_seized == 0, 'zero_coll_seized');
    assert(result.debt_repaid == 0, 'zero_coll_repaid');
    assert(result.bad_debt_incurred == 0, 'zero_coll_bad');
}

#[test]
fn test_liquidation_zero_debt() {
    let result = compute_liquidation(100 * ONE_STRK, 0, PRICE_100, BONUS_500);
    assert(result.collateral_seized == 0, 'zero_debt_seized');
    assert(result.debt_repaid == 0, 'zero_debt_repaid');
    assert(result.bad_debt_incurred == 0, 'zero_debt_bad');
}

// ============================================================
// Edge cases
// ============================================================

#[test]
fn test_liquidation_exact_collateral_match() {
    // Debt and collateral perfectly balanced with bonus.
    // 105 STRK at $1.00, debt = 100 USDC, bonus = 5%
    // required = (100 * 10^6 * 10500 * 10^30) / (10000 * 10^18)
    //          = 105 * 10^18 = exactly 105 STRK
    let result = compute_liquidation(
        105 * ONE_STRK,
        100 * ONE_USDC,
        PRICE_100,
        BONUS_500,
    );
    assert(result.collateral_seized == 105 * ONE_STRK, 'exact_match_seized');
    assert(result.debt_repaid == 100 * ONE_USDC, 'exact_match_repaid');
    assert(result.bad_debt_incurred == 0, 'exact_match_no_bad');
}

#[test]
fn test_liquidation_low_price_creates_bad_debt() {
    // 100 STRK at $0.50 = $50 collateral value
    // Debt: 80 USDC
    // Bonus: 10%
    //
    // required = (80 * 10^6 * 11000 * 10^30) / (10000 * 0.5 * 10^18)
    //          = (80 * 11000 * 10^36) / (5000 * 10^18)
    //          = (880_000 * 10^36) / (5 * 10^21)
    //          = 176 * 10^18 = 176 STRK (need 176, have 100)
    //
    // Seize all 100 STRK.
    // debt_covered = (100 * 10^18 * 0.5 * 10^18 * 10000) / (11000 * 10^30)
    //              = (5 * 10^37 * 10000) / (11000 * 10^30)
    //              = (5 * 10^41) / (11 * 10^33)
    //              = 5 * 10^8 / 11 = 45_454_545 → ~45.45 USDC
    // bad_debt = 80_000_000 - 45_454_545 = 34_545_455
    let result = compute_liquidation(
        100 * ONE_STRK,
        80 * ONE_USDC,
        PRICE_050,
        BONUS_1000,
    );
    assert(result.collateral_seized == 100 * ONE_STRK, 'low_price_seized');
    assert(result.debt_repaid == 45_454_545, 'low_price_repaid');
    assert(result.bad_debt_incurred == 80 * ONE_USDC - 45_454_545, 'low_price_bad');
}

// ============================================================
// Accounting invariant: seized_value >= debt_repaid (liquidator profit >= 0)
// ============================================================

#[test]
fn test_liquidator_always_profits_sufficient() {
    let result = compute_liquidation(
        1000 * ONE_STRK, 200 * ONE_USDC, PRICE_100, BONUS_500,
    );
    // Seized value = 210 STRK * $1 = $210 USDC
    // Debt repaid = $200 USDC
    // Profit = $10
    // In base units: 210 * 10^18 at $1 = 210_000_000 USDC
    // 210_000_000 > 200_000_000 ✓
    let seized_value_usdc: u256 = (result.collateral_seized.into() * PRICE_100)
        / 1_000_000_000_000_000_000_000_000_000_000_u256;
    assert(seized_value_usdc >= result.debt_repaid.into(), 'liquidator_loss');
}
