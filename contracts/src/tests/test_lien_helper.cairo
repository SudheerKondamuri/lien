use core::poseidon::PoseidonTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use starknet::testing::{set_contract_address, set_block_timestamp};

use lien_contracts::types::{Position, PositionStatus, LienOperation, OpenNoteDeposit};
use lien_contracts::lien_helper::LienHelper;
use lien_contracts::interfaces::{
    ILienComputeDispatcher, ILienComputeDispatcherTrait, ILienHelperDispatcher,
    ILienHelperDispatcherTrait, ILienAdminDispatcher, ILienAdminDispatcherTrait,
    ILienViewsDispatcher, ILienViewsDispatcherTrait,
};
use lien_contracts::tests::mock_erc20::{
    MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
};

// ============================================================
// Test constants
// ============================================================

const ONE_STRK: u128 = 1_000_000_000_000_000_000; // 10^18
const ONE_USDC: u128 = 1_000_000; // 10^6

// Price: $1.00 per STRK, 18 decimals
const PRICE_100: u256 = 1_000_000_000_000_000_000;
// Price: $0.50 per STRK
const PRICE_050: u256 = 500_000_000_000_000_000;
// Price: $2.00 per STRK
const PRICE_200: u256 = 2_000_000_000_000_000_000;

// Market config
const MAX_LTV_BPS: u16 = 7500; // 75%
const LIQ_THRESHOLD_BPS: u16 = 8500; // 85%
const LIQ_BONUS_BPS: u16 = 500; // 5%
const INTEREST_RATE_BPS: u16 = 500; // 5% annual

// Domain tag
const POSITION_DOMAIN_TAG: felt252 = 'LIEN_POSITION:V1';

// Addresses
fn owner_addr() -> ContractAddress {
    let addr: felt252 = 0x100;
    addr.try_into().unwrap()
}
fn pool_addr() -> ContractAddress {
    let addr: felt252 = 0x200;
    addr.try_into().unwrap()
}
fn liquidator_addr() -> ContractAddress {
    let addr: felt252 = 0x300;
    addr.try_into().unwrap()
}
fn random_user() -> ContractAddress {
    let addr: felt252 = 0x999;
    addr.try_into().unwrap()
}

// ============================================================
// Deployment & Setup Helpers
// ============================================================

fn deploy_mock_token(salt: felt252) -> ContractAddress {
    let (addr, _) = deploy_syscall(
        MockERC20::TEST_CLASS_HASH.try_into().unwrap(),
        salt,
        array![].span(),
        false,
    )
        .unwrap();
    addr
}

fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    let strk_addr = deploy_mock_token('STRK_SALT');
    let usdc_addr = deploy_mock_token('USDC_SALT');

    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    pool_addr().serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    usdc_addr.serialize(ref calldata);
    MAX_LTV_BPS.serialize(ref calldata);
    LIQ_THRESHOLD_BPS.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let (lien_addr, _) = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'LIEN_SALT',
        calldata.span(),
        false,
    )
        .unwrap();

    (lien_addr, strk_addr, usdc_addr)
}

fn compute_position_id(identity_key: felt252, position_nonce: felt252) -> felt252 {
    PoseidonTrait::new()
        .update_with(POSITION_DOMAIN_TAG)
        .update_with(identity_key)
        .update_with(position_nonce)
        .finalize()
}

// ============================================================
// Privacy Compute Tests
// ============================================================

#[test]
fn test_privacy_compute_deterministic() {
    let (lien_addr, _, _) = setup();
    let compute = ILienComputeDispatcher { contract_address: lien_addr };
    let id1 = compute.privacy_compute('alice_key', 0);
    let id2 = compute.privacy_compute('alice_key', 0);
    assert(id1 == id2, 'compute_not_deterministic');
}

#[test]
fn test_privacy_compute_different_keys() {
    let (lien_addr, _, _) = setup();
    let compute = ILienComputeDispatcher { contract_address: lien_addr };
    let id1 = compute.privacy_compute('alice_key', 0);
    let id2 = compute.privacy_compute('bob_key', 0);
    assert(id1 != id2, 'different_keys_same_id');
}

#[test]
fn test_privacy_compute_different_nonces() {
    let (lien_addr, _, _) = setup();
    let compute = ILienComputeDispatcher { contract_address: lien_addr };
    let id1 = compute.privacy_compute('alice_key', 0);
    let id2 = compute.privacy_compute('alice_key', 1);
    assert(id1 != id2, 'different_nonces_same_id');
}

#[test]
fn test_privacy_compute_matches_manual() {
    let (lien_addr, _, _) = setup();
    let compute = ILienComputeDispatcher { contract_address: lien_addr };
    let id = compute.privacy_compute('alice_key', 0);
    let expected = compute_position_id('alice_key', 0);
    assert(id == expected, 'compute_mismatch_manual');
}

// ============================================================
// Authorization Tests
// ============================================================

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER', 'ENTRYPOINT_FAILED'))]
fn test_invoke_rejects_non_pool_caller() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_contract_address(random_user());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER', 'ENTRYPOINT_FAILED'))]
fn test_set_price_rejects_non_owner() {
    let (lien_addr, _, _) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };

    set_contract_address(random_user());
    admin.set_price(PRICE_050);
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER', 'ENTRYPOINT_FAILED'))]
fn test_seed_liquidity_rejects_non_owner() {
    let (lien_addr, _, _) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };

    set_contract_address(random_user());
    admin.seed_liquidity(1000 * ONE_USDC);
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED_CALLER', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_liquidity_rejects_non_owner() {
    let (lien_addr, _, _) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };

    set_contract_address(random_user());
    admin.withdraw_liquidity(500 * ONE_USDC);
}

// ============================================================
// Real Token Settlement: Seed & Withdraw Liquidity
// ============================================================

#[test]
fn test_seed_and_withdraw_liquidity_with_real_tokens() {
    let (lien_addr, _, usdc_addr) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };

    // Mint USDC to owner and approve LienHelper
    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());

    // Seed 5000 USDC
    admin.seed_liquidity(5000 * ONE_USDC);

    // Verify token balance moved
    assert(usdc.balance_of(owner_addr()) == 5000 * ONE_USDC.into(), 'wrong_owner_balance');
    assert(usdc.balance_of(lien_addr) == 5000 * ONE_USDC.into(), 'wrong_contract_balance');
    assert(views.get_available_liquidity() == 5000 * ONE_USDC, 'wrong_avail_liq');

    // Withdraw 2000 USDC
    admin.withdraw_liquidity(2000 * ONE_USDC);

    // Verify token balance moved back
    assert(usdc.balance_of(owner_addr()) == 7000 * ONE_USDC.into(), 'wrong_owner_bal_after');
    assert(usdc.balance_of(lien_addr) == 3000 * ONE_USDC.into(), 'wrong_contract_bal_after');
    assert(views.get_available_liquidity() == 3000 * ONE_USDC, 'wrong_avail_liq_after');
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_BALANCE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_seed_liquidity_without_tokens_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };

    // Approve without minting tokens
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 1000 * ONE_USDC.into());

    admin.seed_liquidity(1000 * ONE_USDC);
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_ALLOWANCE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_seed_liquidity_without_approval_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };

    usdc.mint(owner_addr(), 1000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    // Do not approve

    admin.seed_liquidity(1000 * ONE_USDC);
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_LIQUIDITY', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_too_much_liquidity_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };

    usdc.mint(owner_addr(), 1000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 1000 * ONE_USDC.into());
    admin.seed_liquidity(1000 * ONE_USDC);

    // Try to withdraw 1001 USDC
    admin.withdraw_liquidity(1001 * ONE_USDC);
}

// ============================================================
// Deposit Collateral Tests
// ============================================================

#[test]
fn test_deposit_creates_active_position() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());

    let (deposits, tokens) = helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    assert(deposits.len() == 0, 'no_deposits_expected');
    assert(tokens.len() == 0, 'no_tokens_expected');

    let pos = views.get_position(pos_id);
    assert(pos.collateral == 100 * ONE_STRK, 'wrong_collateral');
    assert(pos.debt == 0, 'wrong_debt');
    assert(pos.last_updated == 1000, 'wrong_timestamp');
    assert(pos.status == PositionStatus::Active, 'should_be_active');

    assert(views.get_total_collateral() == 100 * ONE_STRK, 'wrong_total_coll');
}

#[test]
fn test_deposit_adds_to_existing_position() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());

    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 50 * ONE_STRK, 0,
        );

    set_block_timestamp(2000);
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 50 * ONE_STRK, 0,
        );

    let pos = views.get_position(pos_id);
    assert(pos.collateral == 100 * ONE_STRK, 'wrong_total_collateral');
    assert(pos.last_updated == 2000, 'wrong_timestamp');
    assert(views.get_total_collateral() == 100 * ONE_STRK, 'wrong_global_coll');
}

#[test]
#[should_panic(expected: ('ZERO_AMOUNT', 'ENTRYPOINT_FAILED'))]
fn test_deposit_zero_rejected() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 0, 0,
        );
}

// ============================================================
// Borrow Tests & Pool Approval
// ============================================================

#[test]
fn test_borrow_at_max_ltv_approves_pool() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    // Deposit 1000 STRK (worth $1000 at $1.00)
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    // Seed 10,000 USDC
    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    // Borrow max 75% LTV: 750 USDC
    set_contract_address(pool_addr());
    let (deposits, tokens) = helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 750 * ONE_USDC, 'note_borrow_1',
        );

    assert(deposits.len() == 1, 'expected_1_deposit');
    let dep = *deposits.at(0);
    assert(dep.note_id == 'note_borrow_1', 'wrong_note_id');
    assert(dep.token == usdc_addr, 'wrong_token');
    assert(dep.amount == 750 * ONE_USDC, 'wrong_amount');

    assert(tokens.len() == 1, 'expected_1_token');
    assert(*tokens.at(0) == usdc_addr, 'wrong_token_addr');

    // Verify LienHelper approved Privacy Pool to pull the 750 USDC
    assert(usdc.allowance(lien_addr, pool_addr()) == 750 * ONE_USDC.into(), 'wrong_pool_allowance');

    // Verify position state & accounting
    let pos = views.get_position(pos_id);
    assert(pos.debt == 750 * ONE_USDC, 'wrong_debt');
    assert(views.get_total_debt() == 750 * ONE_USDC, 'wrong_total_debt');
    assert(views.get_available_liquidity() == 9250 * ONE_USDC, 'wrong_available_liq');
}

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV', 'ENTRYPOINT_FAILED'))]
fn test_borrow_exceeds_max_ltv_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    // Try to borrow 751 USDC (> 75% of $1000)
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 751 * ONE_USDC, 'note_1',
        );
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_LIQUIDITY', 'ENTRYPOINT_FAILED'))]
fn test_borrow_insufficient_liquidity_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    // Seed only 100 USDC
    usdc.mint(owner_addr(), 100 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 100 * ONE_USDC.into());
    admin.seed_liquidity(100 * ONE_USDC);

    // Try to borrow 500 USDC
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_1',
        );
}

#[test]
#[should_panic(expected: ('POSITION_NOT_FOUND', 'ENTRYPOINT_FAILED'))]
fn test_borrow_without_collateral_reverts() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 100 * ONE_USDC, 'note_1',
        );
}

// ============================================================
// Repay Tests & Strict Overpayment Rejection
// ============================================================

#[test]
fn test_repay_partial_success() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_b',
        );

    // Repay 200 USDC
    let (deposits, tokens) = helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 200 * ONE_USDC, 0,
        );
    assert(deposits.len() == 0, 'no_deposits');
    assert(tokens.len() == 0, 'no_tokens');

    let pos = views.get_position(pos_id);
    assert(pos.debt == 300 * ONE_USDC, 'wrong_remaining_debt');
    assert(views.get_total_debt() == 300 * ONE_USDC, 'wrong_total_debt');
    assert(views.get_available_liquidity() == 9700 * ONE_USDC, 'wrong_avail_liq');
}

#[test]
#[should_panic(expected: ('REPAY_EXCEEDS_DEBT', 'ENTRYPOINT_FAILED'))]
fn test_repay_overpayment_strictly_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 100 * ONE_USDC, 'note_b',
        );

    // Attempt to repay 150 USDC when only 100 is owed -> must revert!
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 150 * ONE_USDC, 0,
        );
}

// ============================================================
// Withdraw Collateral Tests & Pool Approval
// ============================================================

#[test]
fn test_withdraw_collateral_no_debt_approves_pool() {
    let (lien_addr, strk_addr, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    // Withdraw all 100 STRK
    let (deposits, tokens) = helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::WithdrawCollateral, 100 * ONE_STRK, 'note_w',
        );

    assert(deposits.len() == 1, 'expected_1_deposit');
    let dep = *deposits.at(0);
    assert(dep.note_id == 'note_w', 'wrong_note_id');
    assert(dep.token == strk_addr, 'wrong_token');
    assert(dep.amount == 100 * ONE_STRK, 'wrong_amount');

    assert(tokens.len() == 1, 'expected_1_token');

    // Verify allowance granted to privacy pool
    assert(strk.allowance(lien_addr, pool_addr()) == 100 * ONE_STRK.into(), 'wrong_pool_strk_allowance');

    let pos = views.get_position(pos_id);
    assert(pos.collateral == 0, 'coll_zero');
    assert(pos.status == PositionStatus::Closed, 'should_be_closed');
    assert(views.get_total_collateral() == 0, 'total_coll_zero');
}

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_collateral_breaks_ltv_reverts() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 700 * ONE_USDC, 'note_b',
        );

    // Try to withdraw 100 STRK -> remaining 900 STRK * $1 = $900
    // Max debt at 75% = 675 USDC < 700 USDC debt -> reverts!
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::WithdrawCollateral, 100 * ONE_STRK, 'note_w',
        );
}

// ============================================================
// Full Lifecycle Test (Deposit -> Borrow -> Repay -> Withdraw -> Closed)
// ============================================================

#[test]
fn test_full_lifecycle_deposit_borrow_repay_withdraw() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    // 1. Deposit 1000 STRK
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    // 2. Seed liquidity
    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    // 3. Borrow 500 USDC
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_borrow',
        );

    // 4. Repay full 500 USDC
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 500 * ONE_USDC, 0,
        );

    // 5. Withdraw all 1000 STRK
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::WithdrawCollateral, 1000 * ONE_STRK, 'note_withdraw',
        );

    // Position must be fully closed
    let pos = views.get_position(pos_id);
    assert(pos.collateral == 0, 'lifecycle_coll');
    assert(pos.debt == 0, 'lifecycle_debt');
    assert(pos.status == PositionStatus::Closed, 'lifecycle_status_closed');

    // Global accounting clean
    assert(views.get_total_collateral() == 0, 'lifecycle_gcoll');
    assert(views.get_total_debt() == 0, 'lifecycle_gdebt');
    assert(views.get_available_liquidity() == 10000 * ONE_USDC, 'lifecycle_gliq');
}

// ============================================================
// Real Token Settlement: Liquidation Tests
// ============================================================

#[test]
fn test_liquidation_with_real_token_settlement() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    // 1. Alice deposits 100 STRK (simulate pool transferring STRK to LienHelper)
    strk.mint(lien_addr, 100 * ONE_STRK.into());
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    // 2. Admin seeds 10,000 USDC
    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    // 3. Alice borrows 75 USDC at $1.00/STRK (at 75% max LTV)
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 75 * ONE_USDC, 'note_b',
        );

    // 4. Price drops to $0.50 -> 100 STRK is worth $50, debt is $75 -> heavily underwater!
    set_contract_address(owner_addr());
    admin.set_price(PRICE_050);

    // 5. Liquidator prepares USDC and approves LienHelper
    usdc.mint(liquidator_addr(), 100 * ONE_USDC.into());
    set_contract_address(liquidator_addr());
    usdc.approve(lien_addr, 100 * ONE_USDC.into());

    let liquidator_strk_before = strk.balance_of(liquidator_addr());
    let liquidator_usdc_before = usdc.balance_of(liquidator_addr());

    // 6. Liquidate!
    helper.liquidate(pos_id);

    // 7. Verify real token movements!
    // Collateral seized: all 100 STRK transferred to liquidator
    let liquidator_strk_after = strk.balance_of(liquidator_addr());
    assert(liquidator_strk_after - liquidator_strk_before == 100 * ONE_STRK.into(), 'wrong_seized_strk');

    // Liquidator paid covered debt in USDC
    let liquidator_usdc_after = usdc.balance_of(liquidator_addr());
    assert(liquidator_usdc_before > liquidator_usdc_after, 'liquidator_did_not_pay');

    // Position is closed and bad debt is recorded
    let pos = views.get_position(pos_id);
    assert(pos.collateral == 0, 'coll_not_zero');
    assert(pos.status == PositionStatus::Closed, 'not_closed');

    let bad_debt = views.get_bad_debt();
    assert(bad_debt > 0, 'bad_debt_not_recorded');
}

#[test]
#[should_panic(expected: ('INSUFFICIENT_ALLOWANCE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_liquidation_without_liquidator_approval_reverts() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    strk.mint(lien_addr, 100 * ONE_STRK.into());
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 75 * ONE_USDC, 'note_b',
        );

    set_contract_address(owner_addr());
    admin.set_price(PRICE_050);

    // Liquidator has tokens but DID NOT approve LienHelper
    usdc.mint(liquidator_addr(), 100 * ONE_USDC.into());
    set_contract_address(liquidator_addr());

    helper.liquidate(pos_id);
}

#[test]
#[should_panic(expected: ('POSITION_NOT_LIQUIDATABLE', 'ENTRYPOINT_FAILED'))]
fn test_healthy_position_not_liquidatable() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    strk.mint(lien_addr, 1000 * ONE_STRK.into());
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 500 * ONE_USDC, 'note_b',
        );

    // Price is still $1.00, healthy (50% LTV < 85% threshold)
    set_contract_address(liquidator_addr());
    helper.liquidate(pos_id);
}

// ============================================================
// Multi-Position Isolation Test
// ============================================================

#[test]
fn test_two_positions_isolated() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let pos_alice = compute_position_id('alice', 0);
    let pos_bob = compute_position_id('bob', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());

    helper
        .privacy_invoke_with_computation(
            pos_alice, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );

    helper
        .privacy_invoke_with_computation(
            pos_bob, LienOperation::DepositCollateral, 500 * ONE_STRK, 0,
        );

    let alice = views.get_position(pos_alice);
    let bob = views.get_position(pos_bob);
    assert(alice.collateral == 1000 * ONE_STRK, 'alice_coll');
    assert(bob.collateral == 500 * ONE_STRK, 'bob_coll');
    assert(views.get_total_collateral() == 1500 * ONE_STRK, 'total_coll_both');
}

// ============================================================
// Interest Accrual on Position
// ============================================================

#[test]
fn test_interest_accrues_on_borrow() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(0);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 10000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 100000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 100000 * ONE_USDC.into());
    admin.seed_liquidity(100000 * ONE_USDC);

    // Borrow 1000 USDC at t=0
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 1000 * ONE_USDC, 'note_b',
        );

    // Advance 1 year (31,536,000 seconds)
    set_block_timestamp(31_536_000);

    // Borrow 1 USDC to trigger accrual
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, ONE_USDC, 'note_b2',
        );

    let pos = views.get_position(pos_id);
    // Debt = 1000 USDC + 50 USDC interest (5%) + 1 USDC = 1051 USDC
    assert(pos.debt == 1_051_000_000, 'wrong_debt_with_interest');
}

// ============================================================
// Admin & Constructor Tests
// ============================================================

#[test]
fn test_set_price() {
    let (lien_addr, _, _) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };

    set_contract_address(owner_addr());
    admin.set_price(PRICE_200);
    assert(views.get_price() == PRICE_200, 'price_not_updated');
}

#[test]
#[should_panic(expected: ('ZERO_PRICE', 'ENTRYPOINT_FAILED'))]
fn test_set_price_zero_rejected() {
    let (lien_addr, _, _) = setup();
    let admin = ILienAdminDispatcher { contract_address: lien_addr };

    set_contract_address(owner_addr());
    admin.set_price(0);
}

#[test]
fn test_views_after_constructor() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let views = ILienViewsDispatcher { contract_address: lien_addr };

    let config = views.get_market_config();
    assert(config.collateral_token == strk_addr, 'wrong_coll_token');
    assert(config.debt_token == usdc_addr, 'wrong_debt_token');
    assert(config.max_ltv_bps == MAX_LTV_BPS, 'wrong_max_ltv');
    assert(config.liquidation_threshold_bps == LIQ_THRESHOLD_BPS, 'wrong_liq_threshold');
    assert(config.liquidation_bonus_bps == LIQ_BONUS_BPS, 'wrong_liq_bonus');
    assert(config.interest_rate_bps == INTEREST_RATE_BPS, 'wrong_interest');

    assert(views.get_price() == PRICE_100, 'wrong_price');
    assert(views.get_privacy_pool() == pool_addr(), 'wrong_pool');
    assert(views.get_total_collateral() == 0, 'init_coll');
    assert(views.get_total_debt() == 0, 'init_debt');
    assert(views.get_available_liquidity() == 0, 'init_liq');
    assert(views.get_bad_debt() == 0, 'init_bad');
}

// ============================================================
// Position Lifecycle & Closed State Tests
// ============================================================

#[test]
#[should_panic(expected: ('POSITION_NOT_FOUND', 'ENTRYPOINT_FAILED'))]
fn test_cannot_liquidate_twice() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    strk.mint(lien_addr, 100 * ONE_STRK.into());
    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 75 * ONE_USDC, 'note_b',
        );

    set_contract_address(owner_addr());
    admin.set_price(PRICE_050);

    usdc.mint(liquidator_addr(), 100 * ONE_USDC.into());
    set_contract_address(liquidator_addr());
    usdc.approve(lien_addr, 100 * ONE_USDC.into());

    // First liquidation succeeds
    helper.liquidate(pos_id);

    // Second liquidation must fail because position is Closed
    helper.liquidate(pos_id);
}

#[test]
#[should_panic(expected: ('POSITION_CLOSED', 'ENTRYPOINT_FAILED'))]
fn test_cannot_deposit_to_closed_position() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(1000);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 100 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 10000 * ONE_USDC.into());
    admin.seed_liquidity(10000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 50 * ONE_USDC, 'note_b',
        );
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 50 * ONE_USDC, 0,
        );
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::WithdrawCollateral, 100 * ONE_STRK, 'note_w',
        );

    // Position is now Closed. Attempting to deposit with the same position_id must fail.
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 50 * ONE_STRK, 0,
        );
}

#[test]
#[should_panic(expected: ('ZERO_AMOUNT', 'ENTRYPOINT_FAILED'))]
fn test_repay_zero_rejected() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 0, 0,
        );
}

#[test]
#[should_panic(expected: ('ZERO_AMOUNT', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_zero_rejected() {
    let (lien_addr, _, _) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let pos_id = compute_position_id('alice', 0);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::WithdrawCollateral, 0, 'note_w',
        );
}

#[test]
fn test_repay_after_interest_accrual() {
    let (lien_addr, _, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };
    let pos_id = compute_position_id('alice', 0);

    set_block_timestamp(0);
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::DepositCollateral, 10000 * ONE_STRK, 0,
        );

    usdc.mint(owner_addr(), 100000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 100000 * ONE_USDC.into());
    admin.seed_liquidity(100000 * ONE_USDC);

    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Borrow, 1000 * ONE_USDC, 'note_b',
        );

    // Advance 1 year -> 50 USDC interest accrued
    set_block_timestamp(31_536_000);

    // Repay 500 USDC
    helper
        .privacy_invoke_with_computation(
            pos_id, LienOperation::Repay, 500 * ONE_USDC, 0,
        );

    let pos = views.get_position(pos_id);
    // Remaining debt = (1000 + 50) - 500 = 550 USDC
    assert(pos.debt == 550 * ONE_USDC, 'wrong_debt_after_accrued_repay');
    assert(views.get_total_debt() == 550 * ONE_USDC, 'wrong_total_debt_accrued');
}

// ============================================================
// Multi-User Global Accounting Invariants Test
// ============================================================

#[test]
fn test_global_accounting_invariants_multi_user() {
    let (lien_addr, strk_addr, usdc_addr) = setup();
    let helper = ILienHelperDispatcher { contract_address: lien_addr };
    let admin = ILienAdminDispatcher { contract_address: lien_addr };
    let views = ILienViewsDispatcher { contract_address: lien_addr };
    let strk = IMockERC20Dispatcher { contract_address: strk_addr };
    let usdc = IMockERC20Dispatcher { contract_address: usdc_addr };

    let pos_a = compute_position_id('alice', 0);
    let pos_b = compute_position_id('bob', 0);
    let pos_c = compute_position_id('charlie', 0);

    // Seed 50,000 USDC
    usdc.mint(owner_addr(), 50000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    usdc.approve(lien_addr, 50000 * ONE_USDC.into());
    admin.seed_liquidity(50000 * ONE_USDC);

    // Alice deposits 1000 STRK, borrows 500 USDC
    set_contract_address(pool_addr());
    helper
        .privacy_invoke_with_computation(
            pos_a, LienOperation::DepositCollateral, 1000 * ONE_STRK, 0,
        );
    helper
        .privacy_invoke_with_computation(
            pos_a, LienOperation::Borrow, 500 * ONE_USDC, 'note_a',
        );

    // Bob deposits 2000 STRK, borrows 1000 USDC
    helper
        .privacy_invoke_with_computation(
            pos_b, LienOperation::DepositCollateral, 2000 * ONE_STRK, 0,
        );
    helper
        .privacy_invoke_with_computation(
            pos_b, LienOperation::Borrow, 1000 * ONE_USDC, 'note_b',
        );

    // Charlie deposits 500 STRK
    helper
        .privacy_invoke_with_computation(
            pos_c, LienOperation::DepositCollateral, 500 * ONE_STRK, 0,
        );

    // Verify invariants
    let alice = views.get_position(pos_a);
    let bob = views.get_position(pos_b);
    let charlie = views.get_position(pos_c);

    let expected_coll = alice.collateral + bob.collateral + charlie.collateral;
    let expected_debt = alice.debt + bob.debt + charlie.debt;

    assert(views.get_total_collateral() == expected_coll, 'coll_invariant_failed');
    assert(views.get_total_debt() == expected_debt, 'debt_invariant_failed');
    assert(views.get_available_liquidity() == 50000 * ONE_USDC - 1500 * ONE_USDC, 'liq_invariant_failed');

    // Bob repays 400 USDC
    helper
        .privacy_invoke_with_computation(
            pos_b, LienOperation::Repay, 400 * ONE_USDC, 0,
        );

    let bob_after = views.get_position(pos_b);
    let expected_debt_after = alice.debt + bob_after.debt + charlie.debt;
    assert(views.get_total_debt() == expected_debt_after, 'debt_invariant_after_repay');
    assert(views.get_available_liquidity() == 50000 * ONE_USDC - 1100 * ONE_USDC, 'liq_invariant_after_repay');
}

// ============================================================
// Constructor Validation Tests
// ============================================================

#[test]
fn test_constructor_zero_owner_reverts() {
    let strk_addr = deploy_mock_token('STRK_C1');
    let usdc_addr = deploy_mock_token('USDC_C1');
    let zero_addr: ContractAddress = 0.try_into().unwrap();

    let mut calldata: Array<felt252> = array![];
    zero_addr.serialize(ref calldata);
    pool_addr().serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    usdc_addr.serialize(ref calldata);
    MAX_LTV_BPS.serialize(ref calldata);
    LIQ_THRESHOLD_BPS.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let res = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'ZERO_OWNER',
        calldata.span(),
        false,
    );
    assert(res.is_err(), 'expected_deploy_err');
}

#[test]
fn test_constructor_zero_pool_reverts() {
    let strk_addr = deploy_mock_token('STRK_C2');
    let usdc_addr = deploy_mock_token('USDC_C2');
    let zero_addr: ContractAddress = 0.try_into().unwrap();

    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    zero_addr.serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    usdc_addr.serialize(ref calldata);
    MAX_LTV_BPS.serialize(ref calldata);
    LIQ_THRESHOLD_BPS.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let res = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'ZERO_POOL',
        calldata.span(),
        false,
    );
    assert(res.is_err(), 'expected_deploy_err');
}

#[test]
fn test_constructor_identical_tokens_reverts() {
    let strk_addr = deploy_mock_token('STRK_C3');

    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    pool_addr().serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    strk_addr.serialize(ref calldata); // same token for both
    MAX_LTV_BPS.serialize(ref calldata);
    LIQ_THRESHOLD_BPS.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let res = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'IDENTICAL_TOKENS',
        calldata.span(),
        false,
    );
    assert(res.is_err(), 'expected_deploy_err');
}

#[test]
fn test_constructor_invalid_ltv_reverts() {
    let strk_addr = deploy_mock_token('STRK_C4');
    let usdc_addr = deploy_mock_token('USDC_C4');

    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    pool_addr().serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    usdc_addr.serialize(ref calldata);
    let invalid_ltv: u16 = 9000;
    let invalid_threshold: u16 = 8500; // threshold <= ltv is invalid!
    invalid_ltv.serialize(ref calldata);
    invalid_threshold.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let res = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'INVALID_LTV',
        calldata.span(),
        false,
    );
    assert(res.is_err(), 'expected_deploy_err');
}

