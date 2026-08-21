use lien_contracts::risk::{
    collateral_value_in_debt,
    max_debt_for_collateral_value,
    is_liquidatable,
    debt_to_collateral_units,
};

// ============================================================
// Constants for readability
// ============================================================

// 1 STRK = 10^18 base units
const ONE_STRK: u128 = 1_000_000_000_000_000_000;
// 1 USDC = 10^6 base units
const ONE_USDC: u128 = 1_000_000;

// Oracle price: $0.50 USDC per STRK, scaled to 18 decimals
// 0.50 * 10^18 = 500_000_000_000_000_000
const PRICE_050: u256 = 500_000_000_000_000_000;
// Oracle price: $1.00
const PRICE_100: u256 = 1_000_000_000_000_000_000;
// Oracle price: $2.00
const PRICE_200: u256 = 2_000_000_000_000_000_000;

// ============================================================
// collateral_value_in_debt tests
// ============================================================

#[test]
fn test_collateral_value_1_strk_at_1_dollar() {
    // 1 STRK at $1.00 = 1 USDC = 1_000_000 base units
    let value = collateral_value_in_debt(ONE_STRK, PRICE_100);
    assert(value == ONE_USDC.into(), 'wrong_value_1_at_1');
}

#[test]
fn test_collateral_value_1_strk_at_050() {
    // 1 STRK at $0.50 = 0.5 USDC = 500_000 base units
    let value = collateral_value_in_debt(ONE_STRK, PRICE_050);
    assert(value == 500_000_u256, 'wrong_value_1_at_050');
}

#[test]
fn test_collateral_value_1000_strk_at_2_dollars() {
    // 1000 STRK at $2.00 = 2000 USDC = 2_000_000_000 base units
    let collateral = 1000 * ONE_STRK;
    let value = collateral_value_in_debt(collateral, PRICE_200);
    assert(value == 2_000_000_000_u256, 'wrong_value_1000_at_2');
}

#[test]
fn test_collateral_value_zero_collateral() {
    let value = collateral_value_in_debt(0, PRICE_100);
    assert(value == 0, 'zero_coll_not_zero');
}

#[test]
fn test_collateral_value_zero_price() {
    let value = collateral_value_in_debt(ONE_STRK, 0);
    assert(value == 0, 'zero_price_not_zero');
}

// ============================================================
// max_debt_for_collateral_value tests
// ============================================================

#[test]
fn test_max_debt_75_ltv() {
    // Collateral value = 1000 USDC, max LTV = 75%
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let max = max_debt_for_collateral_value(coll_value, 7500);
    // 1000 * 7500 / 10000 = 750 USDC = 750_000_000
    assert(max == 750_000_000_u256, 'wrong_max_75');
}

#[test]
fn test_max_debt_50_ltv() {
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let max = max_debt_for_collateral_value(coll_value, 5000);
    // 500 USDC = 500_000_000
    assert(max == 500_000_000_u256, 'wrong_max_50');
}

#[test]
fn test_max_debt_zero_collateral() {
    let max = max_debt_for_collateral_value(0, 7500);
    assert(max == 0, 'zero_coll_max_not_zero');
}

#[test]
fn test_max_debt_zero_ltv() {
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let max = max_debt_for_collateral_value(coll_value, 0);
    assert(max == 0, 'zero_ltv_max_not_zero');
}

// ============================================================
// is_liquidatable tests
// ============================================================

#[test]
fn test_not_liquidatable_healthy() {
    // Collateral value = 1000 USDC, debt = 500 USDC, threshold = 85%
    // max_safe = 1000 * 8500 / 10000 = 850 USDC
    // 500 < 850 → not liquidatable
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let liquidatable = is_liquidatable(coll_value, 500 * ONE_USDC, 8500);
    assert(!liquidatable, 'should_not_be_liq');
}

#[test]
fn test_liquidatable_at_threshold() {
    // debt exactly at threshold: 850 USDC = 850_000_000
    // 850 > 850 is false → NOT liquidatable (boundary: equal is safe)
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let liquidatable = is_liquidatable(coll_value, 850 * ONE_USDC, 8500);
    assert(!liquidatable, 'at_threshold_not_liq');
}

#[test]
fn test_liquidatable_above_threshold() {
    // debt = 851 USDC > 850 threshold → liquidatable
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let liquidatable = is_liquidatable(coll_value, 851 * ONE_USDC, 8500);
    assert(liquidatable, 'above_threshold_is_liq');
}

#[test]
fn test_not_liquidatable_zero_debt() {
    let coll_value: u256 = (1000 * ONE_USDC).into();
    let liquidatable = is_liquidatable(coll_value, 0, 8500);
    assert(!liquidatable, 'zero_debt_not_liq');
}

// ============================================================
// debt_to_collateral_units tests
// ============================================================

#[test]
fn test_debt_to_coll_1_usdc_at_1_dollar() {
    // 1 USDC ($1 debt) at STRK=$1 → 1 STRK = 10^18 base units
    let coll = debt_to_collateral_units(ONE_USDC.into(), PRICE_100);
    assert(coll == ONE_STRK.into(), 'wrong_d2c_1_at_1');
}

#[test]
fn test_debt_to_coll_1_usdc_at_050() {
    // 1 USDC ($1 debt) at STRK=$0.50 → 2 STRK = 2 * 10^18
    let coll = debt_to_collateral_units(ONE_USDC.into(), PRICE_050);
    let expected: u256 = (2 * ONE_STRK).into();
    assert(coll == expected, 'wrong_d2c_1_at_050');
}

#[test]
fn test_debt_to_coll_500_usdc_at_2_dollars() {
    // 500 USDC at STRK=$2 → 250 STRK = 250 * 10^18
    let debt: u256 = (500 * ONE_USDC).into();
    let coll = debt_to_collateral_units(debt, PRICE_200);
    let expected: u256 = (250 * ONE_STRK).into();
    assert(coll == expected, 'wrong_d2c_500_at_2');
}

#[test]
#[should_panic(expected: ('ZERO_PRICE',))]
fn test_debt_to_coll_zero_price_panics() {
    debt_to_collateral_units(ONE_USDC.into(), 0);
}

// ============================================================
// Round-trip consistency: value → debt → collateral
// ============================================================

#[test]
fn test_roundtrip_value_and_back() {
    // 100 STRK at $2 = 200 USDC value
    let collateral = 100 * ONE_STRK;
    let value = collateral_value_in_debt(collateral, PRICE_200);
    assert(value == (200 * ONE_USDC).into(), 'roundtrip_value');

    // Convert 200 USDC back to STRK at $2 → 100 STRK
    let back = debt_to_collateral_units(value, PRICE_200);
    assert(back == collateral.into(), 'roundtrip_back');
}
