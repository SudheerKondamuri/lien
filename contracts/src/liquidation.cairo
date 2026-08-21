/// Pure math for liquidation: cross-asset seizure calculation with bad-debt recognition.
///
/// Full-close liquidation model for V1:
///   When a position is liquidatable, the liquidator covers the entire remaining debt.
///   The collateral seized includes a liquidation bonus as incentive.
///   If collateral is insufficient to cover the full debt + bonus, all collateral is seized,
///   the position is closed, and the unrecoverable debt is recognized as protocol bad debt.

use crate::types::LiquidationResult;
use crate::risk::{DECIMAL_SCALING, BPS_DENOMINATOR};

/// Computes the full-close liquidation outcome for a position.
///
/// Parameters:
///   - collateral: position collateral in collateral base units (e.g. STRK 10^18)
///   - debt: position debt in debt base units (e.g. USDC 10^6), AFTER interest accrual
///   - price: oracle price (collateral per debt unit, 18 decimals)
///   - liquidation_bonus_bps: bonus reward for liquidators in basis points
///
/// Returns LiquidationResult:
///   - collateral_seized: collateral transferred to liquidator
///   - debt_repaid: debt removed from position and returned to available_liquidity
///   - bad_debt_incurred: debt written off (collateral insufficient)
///
/// Full-close model: always attempts to cover the entire debt.
/// If collateral is insufficient, seizes all collateral and records bad debt.
pub fn compute_liquidation(
    collateral: u128,
    debt: u128,
    price: u256,
    liquidation_bonus_bps: u16,
) -> LiquidationResult {
    if debt == 0 || collateral == 0 {
        return LiquidationResult {
            collateral_seized: 0, debt_repaid: 0, bad_debt_incurred: 0,
        };
    }

    let debt_u256: u256 = debt.into();
    let collateral_u256: u256 = collateral.into();
    let bonus: u256 = liquidation_bonus_bps.into();

    // Collateral required to cover debt + bonus, in collateral base units:
    //   required_collateral = (debt * (10000 + bonus) * DECIMAL_SCALING) / (10000 * price)
    //
    // Unit derivation:
    //   debt is in USDC base units (10^6)
    //   price is USDC_per_STRK * 10^18
    //   DECIMAL_SCALING = 10^30
    //   result: (USDC * 10^30) / (USDC_per_STRK * 10^18) = STRK * 10^12 ... wait
    //
    // Correct unit derivation:
    //   collateral_value_usdc = (collateral_strk * price) / 10^30
    //   Therefore: collateral_strk = (value_usdc * 10^30) / price
    //   With bonus: collateral_strk = (debt_usdc * (10000 + bonus_bps) / 10000 * 10^30) / price
    let numerator = debt_u256 * (BPS_DENOMINATOR + bonus) * DECIMAL_SCALING;
    let denominator = BPS_DENOMINATOR * price;
    let required_collateral = numerator / denominator;

    if required_collateral <= collateral_u256 {
        // Sufficient collateral: seize exactly what's needed, cover full debt.
        let seized: u128 = required_collateral.try_into().expect('SEIZE_OVERFLOW');
        LiquidationResult {
            collateral_seized: seized,
            debt_repaid: debt,
            bad_debt_incurred: 0,
        }
    } else {
        // Insufficient collateral: seize everything, compute how much debt is actually covered.
        // debt_covered = (collateral * price * 10000) / ((10000 + bonus) * DECIMAL_SCALING)
        let covered_numerator = collateral_u256 * price * BPS_DENOMINATOR;
        let covered_denominator = (BPS_DENOMINATOR + bonus) * DECIMAL_SCALING;
        let debt_actually_covered_u256 = covered_numerator / covered_denominator;

        let debt_actually_covered: u128 = debt_actually_covered_u256
            .try_into()
            .expect('COVER_OVERFLOW');

        // Clamp: debt_actually_covered should never exceed total debt
        let clamped_covered = if debt_actually_covered > debt {
            debt
        } else {
            debt_actually_covered
        };

        let bad_debt = debt - clamped_covered;

        LiquidationResult {
            collateral_seized: collateral,
            debt_repaid: clamped_covered,
            bad_debt_incurred: bad_debt,
        }
    }
}
