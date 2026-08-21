use core::poseidon::PoseidonTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_block_timestamp};

use lien_contracts::types::LienOperation;
use lien_contracts::lien_helper::LienHelper;

// ============================================================
// Test constants
// ============================================================

const ONE_STRK: u128 = 1_000_000_000_000_000_000; // 10^18
const ONE_USDC: u128 = 1_000_000; // 10^6

// Price: $1.00 per STRK, 18 decimals
const PRICE_100: u256 = 1_000_000_000_000_000_000;
// Price: $0.50
const PRICE_050: u256 = 500_000_000_000_000_000;

// Market config
const MAX_LTV_BPS: u16 = 7500; // 75%
const LIQ_THRESHOLD_BPS: u16 = 8500; // 85%
const LIQ_BONUS_BPS: u16 = 500; // 5%
const INTEREST_RATE_BPS: u16 = 500; // 5% annual

// Addresses
fn owner_addr() -> ContractAddress {
    let addr: felt252 = 0x1;
    addr.try_into().unwrap()
}
fn pool_addr() -> ContractAddress {
    let addr: felt252 = 0x2;
    addr.try_into().unwrap()
}
fn strk_token() -> ContractAddress {
    let addr: felt252 = 0x3;
    addr.try_into().unwrap()
}
fn usdc_token() -> ContractAddress {
    let addr: felt252 = 0x4;
    addr.try_into().unwrap()
}
fn random_user() -> ContractAddress {
    let addr: felt252 = 0x99;
    addr.try_into().unwrap()
}

// Position ID derivation constants
const POSITION_DOMAIN_TAG: felt252 = 'LIEN_POSITION:V1';

// ============================================================
// Helpers
// ============================================================

/// Deploy LienHelper contract state for testing.
fn setup() -> LienHelper::ContractState {
    let mut state = LienHelper::contract_state_for_testing();

    // Call constructor
    set_caller_address(owner_addr());
    LienHelper::constructor(
        ref state,
        owner_addr(),
        pool_addr(),
        strk_token(),
        usdc_token(),
        MAX_LTV_BPS,
        LIQ_THRESHOLD_BPS,
        LIQ_BONUS_BPS,
        INTEREST_RATE_BPS,
        PRICE_100,
    );

    state
}

/// Compute position_id the same way the contract does.
fn compute_position_id(identity_key: felt252, position_nonce: felt252) -> felt252 {
    PoseidonTrait::new()
        .update_with(POSITION_DOMAIN_TAG)
        .update_with(identity_key)
        .update_with(position_nonce)
        .finalize()
}

// ============================================================
// privacy_compute tests
// ============================================================

#[test]
fn test_privacy_compute_deterministic() {
    let state = setup();
    let id1 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 0);
    let id2 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 0);
    assert(id1 == id2, 'compute_not_deterministic');
}

#[test]
fn test_privacy_compute_different_keys() {
    let state = setup();
    let id1 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 0);
    let id2 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_b', 0);
    assert(id1 != id2, 'different_keys_same_id');
}

#[test]
fn test_privacy_compute_different_nonces() {
    let state = setup();
    let id1 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 0);
    let id2 = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 1);
    assert(id1 != id2, 'different_nonces_same_id');
}

#[test]
fn test_privacy_compute_matches_manual() {
    let state = setup();
    let id = LienHelper::LienComputeImpl::privacy_compute(@state, 'key_a', 0);
    let expected = compute_position_id('key_a', 0);
    assert(id == expected, 'compute_mismatch_manual');
}

// ============================================================
// Authorization tests
// ============================================================

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER',))]
fn test_invoke_rejects_non_pool_caller() {
    let mut state = setup();
    let pos_id = compute_position_id('key_a', 0);
    set_block_timestamp(1000);

    // Call from random user, not the pool
    set_caller_address(random_user());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER',))]
fn test_set_price_rejects_non_owner() {
    let mut state = setup();
    set_caller_address(random_user());
    LienHelper::LienAdminImpl::set_price(ref state, PRICE_050);
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER',))]
fn test_seed_liquidity_rejects_non_owner() {
    let mut state = setup();
    set_caller_address(random_user());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 1000 * ONE_USDC);
}

// ============================================================
// Deposit collateral tests
// ============================================================

#[test]
fn test_deposit_creates_position() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    let (deposits, _tokens) = LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );

    // No output deposits for collateral deposit
    assert(deposits.len() == 0, 'no_deposits_expected');

    // Check position
    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.collateral == 100 * ONE_STRK, 'wrong_collateral');
    assert(pos.debt == 0, 'wrong_debt');
    assert(pos.last_updated == 1000, 'wrong_timestamp');

    // Check global accounting
    assert(LienHelper::LienViewsImpl::get_total_collateral(@state) == 100 * ONE_STRK, 'wrong_total_coll');
}

#[test]
fn test_deposit_adds_to_existing_position() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // First deposit
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 50 * ONE_STRK, 0,
    );

    // Second deposit
    set_block_timestamp(2000);
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 50 * ONE_STRK, 0,
    );

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.collateral == 100 * ONE_STRK, 'wrong_total_deposit');
    assert(LienHelper::LienViewsImpl::get_total_collateral(@state) == 100 * ONE_STRK, 'wrong_global');
}

// ============================================================
// Borrow tests
// ============================================================

#[test]
fn test_borrow_at_max_ltv() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Deposit 1000 STRK at $1 = $1000 value
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    // Seed liquidity
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);

    // Borrow at max LTV: $1000 * 75% = 750 USDC
    set_caller_address(pool_addr());
    let (deposits, tokens) = LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 750 * ONE_USDC, 'note_1',
    );

    // Should return 1 open note deposit
    assert(deposits.len() == 1, 'expected_1_deposit');
    let dep = *deposits.at(0);
    assert(dep.note_id == 'note_1', 'wrong_note_id');
    assert(dep.token == usdc_token(), 'wrong_token');
    assert(dep.amount == 750 * ONE_USDC, 'wrong_amount');

    // Should return 1 token address
    assert(tokens.len() == 1, 'expected_1_token');
    assert(*tokens.at(0) == usdc_token(), 'wrong_token_addr');

    // Check position state
    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.debt == 750 * ONE_USDC, 'wrong_debt');

    // Check accounting
    assert(LienHelper::LienViewsImpl::get_total_debt(@state) == 750 * ONE_USDC, 'wrong_total_debt');
    assert(
        LienHelper::LienViewsImpl::get_available_liquidity(@state) == 10000 * ONE_USDC
            - 750 * ONE_USDC,
        'wrong_liquidity',
    );
}

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV',))]
fn test_borrow_exceeds_max_ltv() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Deposit 1000 STRK at $1
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);

    // Try borrow 751 USDC (exceeds 75% of $1000)
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 751 * ONE_USDC, 'note_1',
    );
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_LIQUIDITY',))]
fn test_borrow_insufficient_liquidity() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    // Seed only 100 USDC
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 100 * ONE_USDC);

    // Try borrow 500 USDC
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_1',
    );
}

#[test]
#[should_panic(expected: ('POSITION_NOT_FOUND',))]
fn test_borrow_without_collateral() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Try to borrow without depositing first
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 100 * ONE_USDC, 'note_1',
    );
}

// ============================================================
// Repay tests
// ============================================================

#[test]
fn test_repay_partial() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Deposit and borrow
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_1',
    );

    // Repay 200 USDC (same block, no interest)
    let (deposits, _tokens) = LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Repay, 200 * ONE_USDC, 0,
    );
    assert(deposits.len() == 0, 'repay_no_deposits');

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.debt == 300 * ONE_USDC, 'wrong_remaining_debt');
    assert(
        LienHelper::LienViewsImpl::get_available_liquidity(@state) == 10000 * ONE_USDC
            - 500 * ONE_USDC + 200 * ONE_USDC,
        'wrong_liq_after_repay',
    );
}

#[test]
fn test_repay_clamped_to_debt() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 100 * ONE_USDC, 'note_1',
    );

    // Overpay: send 500 but only 100 is owed
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Repay, 500 * ONE_USDC, 0,
    );

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.debt == 0, 'debt_should_be_zero');
}

// ============================================================
// Withdraw collateral tests
// ============================================================

#[test]
fn test_withdraw_collateral_no_debt() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );

    // Withdraw all — no debt, so no LTV constraint
    let (deposits, tokens) = LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::WithdrawCollateral, 100 * ONE_STRK, 'note_w',
    );

    assert(deposits.len() == 1, 'expected_1_deposit');
    let dep = *deposits.at(0);
    assert(dep.note_id == 'note_w', 'wrong_note_id');
    assert(dep.token == strk_token(), 'wrong_token');
    assert(dep.amount == 100 * ONE_STRK, 'wrong_withdraw_amount');

    assert(tokens.len() == 1, 'expected_1_token');

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.collateral == 0, 'should_be_zero');
    assert(LienHelper::LienViewsImpl::get_total_collateral(@state) == 0, 'global_coll_zero');
}

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV',))]
fn test_withdraw_collateral_breaks_ltv() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 700 * ONE_USDC, 'note_1',
    );

    // Try to withdraw 100 STRK — remaining 900 STRK at $1 = $900
    // 700 USDC debt > 900 * 75% = 675 → should fail
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::WithdrawCollateral, 100 * ONE_STRK, 'note_w',
    );
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_COLLATERAL',))]
fn test_withdraw_more_than_collateral() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );

    // Withdraw 200 STRK (only have 100)
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::WithdrawCollateral, 200 * ONE_STRK, 'note_w',
    );
}

// ============================================================
// Full lifecycle test
// ============================================================

#[test]
fn test_full_lifecycle_deposit_borrow_repay_withdraw() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // 1. Deposit 1000 STRK
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    // 2. Seed liquidity
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);

    // 3. Borrow 500 USDC
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_b',
    );

    // 4. Repay all 500 USDC
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Repay, 500 * ONE_USDC, 0,
    );

    // 5. Withdraw all collateral
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::WithdrawCollateral, 1000 * ONE_STRK, 'note_w',
    );

    // Position should be empty
    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    assert(pos.collateral == 0, 'lifecycle_coll');
    assert(pos.debt == 0, 'lifecycle_debt');

    // Global accounting should be clean
    assert(LienHelper::LienViewsImpl::get_total_collateral(@state) == 0, 'lifecycle_gcoll');
    assert(LienHelper::LienViewsImpl::get_total_debt(@state) == 0, 'lifecycle_gdebt');
    assert(
        LienHelper::LienViewsImpl::get_available_liquidity(@state) == 10000 * ONE_USDC,
        'lifecycle_gliq',
    );
}

// ============================================================
// Interest accrual tests
// ============================================================

#[test]
fn test_interest_accrues_on_borrow() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(0);
    set_caller_address(pool_addr());

    // Deposit
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 10000 * ONE_STRK, 0,
    );

    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 100000 * ONE_USDC);

    // Borrow 1000 USDC at t=0
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 1000 * ONE_USDC, 'note_b',
    );

    // Advance 1 year, then borrow more (triggers interest accrual)
    set_block_timestamp(31_536_000); // 1 year

    // Borrow 1 more USDC just to trigger interest
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, ONE_USDC, 'note_b2',
    );

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    // Debt = 1000 + 50 (interest) + 1 = 1051 USDC = 1_051_000_000
    assert(pos.debt == 1_051_000_000, 'wrong_debt_with_interest');
}

// ============================================================
// Liquidation tests (contract-level)
// ============================================================

#[test]
fn test_liquidation_underwater_position() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Deposit 100 STRK at $1
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );

    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);

    // Borrow 75 USDC (at max 75% LTV)
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 75 * ONE_USDC, 'note_b',
    );

    // Price drops to $0.50 → collateral value = $50, debt = $75
    // Threshold: $50 * 85% = $42.5 USDC
    // $75 > $42.5 → liquidatable
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::set_price(ref state, PRICE_050);

    // Anyone can liquidate
    set_caller_address(random_user());
    LienHelper::LienHelperImpl::liquidate(ref state, pos_id);

    let pos = LienHelper::LienViewsImpl::get_position(@state, pos_id);
    // Position should be fully or mostly liquidated
    // At $0.50, 100 STRK = $50 value
    // Debt = $75, required collateral = (75 * 10500 * 10^30) / (10000 * 0.5 * 10^18)
    //       = 157.5 STRK — way more than available 100 STRK
    // So: seize all 100 STRK, bad debt recognized
    assert(pos.collateral == 0, 'coll_should_be_zero');

    // Bad debt should be recorded
    let bad_debt = LienHelper::LienViewsImpl::get_bad_debt(@state);
    assert(bad_debt > 0, 'should_have_bad_debt');
}

#[test]
#[should_panic(expected: ('POSITION_NOT_LIQUIDATABLE',))]
fn test_healthy_position_not_liquidatable() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 10000 * ONE_USDC);

    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_b',
    );

    // Price stays at $1, debt=$500, threshold=$850
    // Not liquidatable
    set_caller_address(random_user());
    LienHelper::LienHelperImpl::liquidate(ref state, pos_id);
}

// ============================================================
// Admin tests
// ============================================================

#[test]
fn test_set_price() {
    let mut state = setup();
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::set_price(ref state, PRICE_050);
    assert(LienHelper::LienViewsImpl::get_price(@state) == PRICE_050, 'price_not_updated');
}

#[test]
#[should_panic(expected: ('ZERO_PRICE',))]
fn test_set_price_zero_rejected() {
    let mut state = setup();
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::set_price(ref state, 0);
}

#[test]
fn test_seed_and_withdraw_liquidity() {
    let mut state = setup();
    set_caller_address(owner_addr());

    LienHelper::LienAdminImpl::seed_liquidity(ref state, 1000 * ONE_USDC);
    assert(
        LienHelper::LienViewsImpl::get_available_liquidity(@state) == 1000 * ONE_USDC,
        'wrong_seeded',
    );

    LienHelper::LienAdminImpl::withdraw_liquidity(ref state, 400 * ONE_USDC);
    assert(
        LienHelper::LienViewsImpl::get_available_liquidity(@state) == 600 * ONE_USDC,
        'wrong_after_withdraw',
    );
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_LIQUIDITY',))]
fn test_withdraw_too_much_liquidity() {
    let mut state = setup();
    set_caller_address(owner_addr());
    LienHelper::LienAdminImpl::seed_liquidity(ref state, 100 * ONE_USDC);
    LienHelper::LienAdminImpl::withdraw_liquidity(ref state, 200 * ONE_USDC);
}

// ============================================================
// View tests
// ============================================================

#[test]
fn test_views_after_constructor() {
    let state = setup();
    let config = LienHelper::LienViewsImpl::get_market_config(@state);
    assert(config.collateral_token == strk_token(), 'wrong_coll_token');
    assert(config.debt_token == usdc_token(), 'wrong_debt_token');
    assert(config.max_ltv_bps == MAX_LTV_BPS, 'wrong_max_ltv');
    assert(config.liquidation_threshold_bps == LIQ_THRESHOLD_BPS, 'wrong_liq_threshold');
    assert(config.liquidation_bonus_bps == LIQ_BONUS_BPS, 'wrong_liq_bonus');
    assert(config.interest_rate_bps == INTEREST_RATE_BPS, 'wrong_interest');

    assert(LienHelper::LienViewsImpl::get_price(@state) == PRICE_100, 'wrong_price');
    assert(LienHelper::LienViewsImpl::get_privacy_pool(@state) == pool_addr(), 'wrong_pool');
    assert(LienHelper::LienViewsImpl::get_total_collateral(@state) == 0, 'init_coll');
    assert(LienHelper::LienViewsImpl::get_total_debt(@state) == 0, 'init_debt');
    assert(LienHelper::LienViewsImpl::get_available_liquidity(@state) == 0, 'init_liq');
    assert(LienHelper::LienViewsImpl::get_bad_debt(@state) == 0, 'init_bad');
}

// ============================================================
// Multi-position isolation test
// ============================================================

#[test]
fn test_two_positions_isolated() {
    let mut state = setup();
    let pos_alice = compute_position_id('alice', 0);
    let pos_bob = compute_position_id('bob', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());

    // Alice deposits 1000 STRK
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_alice, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
    );

    // Bob deposits 500 STRK
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_bob, LienOperation::DepositCollateral, 500 * ONE_STRK, 0,
    );

    let alice = LienHelper::LienViewsImpl::get_position(@state, pos_alice);
    let bob = LienHelper::LienViewsImpl::get_position(@state, pos_bob);
    assert(alice.collateral == 1000 * ONE_STRK, 'alice_coll');
    assert(bob.collateral == 500 * ONE_STRK, 'bob_coll');

    // Global: 1500 STRK total
    assert(
        LienHelper::LienViewsImpl::get_total_collateral(@state) == 1500 * ONE_STRK,
        'total_coll_both',
    );
}

// ============================================================
// Zero amount rejection
// ============================================================

#[test]
#[should_panic(expected: ('ZERO_AMOUNT',))]
fn test_deposit_zero_rejected() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 0, 0,
    );
}

#[test]
#[should_panic(expected: ('ZERO_AMOUNT',))]
fn test_borrow_zero_rejected() {
    let mut state = setup();
    let pos_id = compute_position_id('alice', 0);
    set_block_timestamp(1000);
    set_caller_address(pool_addr());
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
    );
    LienHelper::LienHelperImpl::privacy_invoke_with_computation(
        ref state, pos_id, LienOperation::Borrow, 0, 'note_b',
    );
}
