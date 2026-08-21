use core::poseidon::PoseidonTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use starknet::testing::{set_contract_address, set_block_timestamp};

use lien_contracts::types::{Position, PositionStatus, LienOperation};
use lien_contracts::lien_helper::LienHelper;
use lien_contracts::interfaces::{
    ILienComputeDispatcher, ILienComputeDispatcherTrait, ILienHelperDispatcher,
    ILienHelperDispatcherTrait, ILienAdminDispatcher, ILienAdminDispatcherTrait,
    ILienViewsDispatcher, ILienViewsDispatcherTrait,
};
use lien_contracts::tests::mock_erc20::{
    MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
};
use lien_contracts::tests::mock_privacy_pool::{
    MockPrivacyPool, IMockPrivacyPoolDispatcher, IMockPrivacyPoolDispatcherTrait,
};

// ============================================================
// Constants
// ============================================================

const ONE_STRK: u128 = 1_000_000_000_000_000_000; // 10^18
const ONE_USDC: u128 = 1_000_000; // 10^6

const PRICE_100: u256 = 1_000_000_000_000_000_000; // $1.00
const PRICE_050: u256 = 500_000_000_000_000_000;   // $0.50
const PRICE_200: u256 = 2_000_000_000_000_000_000; // $2.00

const MAX_LTV_BPS: u16 = 7500;             // 75%
const LIQ_THRESHOLD_BPS: u16 = 8500;       // 85%
const LIQ_BONUS_BPS: u16 = 500;            // 5%
const INTEREST_RATE_BPS: u16 = 500;        // 5%

const POSITION_DOMAIN_TAG: felt252 = 'LIEN_POSITION:V1';

fn owner_addr() -> ContractAddress {
    let addr: felt252 = 0x100;
    addr.try_into().unwrap()
}
fn liquidator_addr() -> ContractAddress {
    let addr: felt252 = 0x300;
    addr.try_into().unwrap()
}
fn alice_wallet() -> ContractAddress {
    let addr: felt252 = 0x401;
    addr.try_into().unwrap()
}
fn bob_wallet() -> ContractAddress {
    let addr: felt252 = 0x402;
    addr.try_into().unwrap()
}

// ============================================================
// Setup Fixture
// ============================================================

#[derive(Drop, Copy)]
struct TestFixture {
    lien_addr: ContractAddress,
    pool_addr: ContractAddress,
    strk_addr: ContractAddress,
    usdc_addr: ContractAddress,
    lien_helper: ILienHelperDispatcher,
    lien_admin: ILienAdminDispatcher,
    lien_views: ILienViewsDispatcher,
    lien_compute: ILienComputeDispatcher,
    pool: IMockPrivacyPoolDispatcher,
    strk: IMockERC20Dispatcher,
    usdc: IMockERC20Dispatcher,
}

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

fn setup_integration() -> TestFixture {
    let strk_addr = deploy_mock_token('STRK_TOKEN');
    let usdc_addr = deploy_mock_token('USDC_TOKEN');

    // Deploy Mock Privacy Pool
    let (pool_addr, _) = deploy_syscall(
        MockPrivacyPool::TEST_CLASS_HASH.try_into().unwrap(),
        'PRIVACY_POOL',
        array![].span(),
        false,
    )
        .unwrap();

    // Deploy LienHelper with the real deployed MockPrivacyPool address
    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    pool_addr.serialize(ref calldata);
    strk_addr.serialize(ref calldata);
    usdc_addr.serialize(ref calldata);
    MAX_LTV_BPS.serialize(ref calldata);
    LIQ_THRESHOLD_BPS.serialize(ref calldata);
    LIQ_BONUS_BPS.serialize(ref calldata);
    INTEREST_RATE_BPS.serialize(ref calldata);
    PRICE_100.serialize(ref calldata);

    let (lien_addr, _) = deploy_syscall(
        LienHelper::TEST_CLASS_HASH.try_into().unwrap(),
        'LIEN_HELPER',
        calldata.span(),
        false,
    )
        .unwrap();

    TestFixture {
        lien_addr,
        pool_addr,
        strk_addr,
        usdc_addr,
        lien_helper: ILienHelperDispatcher { contract_address: lien_addr },
        lien_admin: ILienAdminDispatcher { contract_address: lien_addr },
        lien_views: ILienViewsDispatcher { contract_address: lien_addr },
        lien_compute: ILienComputeDispatcher { contract_address: lien_addr },
        pool: IMockPrivacyPoolDispatcher { contract_address: pool_addr },
        strk: IMockERC20Dispatcher { contract_address: strk_addr },
        usdc: IMockERC20Dispatcher { contract_address: usdc_addr },
    }
}

/// Helper to verify all protocol accounting and token balance invariants
fn assert_protocol_invariants(
    f: @TestFixture,
    expected_strk_balance: u128,
    expected_usdc_balance: u128,
    expected_total_collateral: u128,
    expected_total_debt: u128,
    expected_available_liquidity: u128,
) {
    let actual_strk: u128 = (*f.strk).balance_of(*f.lien_addr).try_into().unwrap();
    let actual_usdc: u128 = (*f.usdc).balance_of(*f.lien_addr).try_into().unwrap();
    let tracked_coll = (*f.lien_views).get_total_collateral();
    let tracked_debt = (*f.lien_views).get_total_debt();
    let tracked_liq = (*f.lien_views).get_available_liquidity();

    assert(actual_strk == expected_strk_balance, 'inv_actual_strk');
    assert(actual_usdc == expected_usdc_balance, 'inv_actual_usdc');
    assert(tracked_coll == expected_total_collateral, 'inv_tracked_coll');
    assert(tracked_debt == expected_total_debt, 'inv_tracked_debt');
    assert(tracked_liq == expected_available_liquidity, 'inv_tracked_liq');

    // Strict balance match invariant
    assert(actual_strk == tracked_coll, 'inv_strk_eq_coll');
    assert(actual_usdc == tracked_liq, 'inv_usdc_eq_liq');
}

// ============================================================
// End-to-End STRK20 Full Lifecycle Test
// ============================================================

#[test]
fn test_e2e_strk20_full_lifecycle() {
    let f = setup_integration();
    let alice_identity = 'alice_secret_identity_key';
    let alice_nonce = 0;
    let pos_id = f.lien_compute.privacy_compute(alice_identity, alice_nonce);

    // Initial state: Lien has 0 tokens, 0 collateral, 0 debt, 0 liquidity
    assert_protocol_invariants(@f, 0, 0, 0, 0, 0);

    // -------------------------------------------------------------
    // Step 1: Alice shields 1000 STRK into Privacy Pool
    // -------------------------------------------------------------
    f.strk.mint(alice_wallet(), 1000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 1000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 1000 * ONE_STRK, alice_wallet());

    assert(f.strk.balance_of(f.pool_addr) == 1000 * ONE_STRK.into(), 'pool_strk_after_shield');
    assert(f.strk.balance_of(alice_wallet()) == 0, 'alice_strk_shielded');

    // -------------------------------------------------------------
    // Step 2: STRK20 executes Collateral Deposit (1000 STRK) to Lien
    // - STRK20 transfers 1000 STRK to Lien
    // - STRK20 calls privacy_invoke_with_computation
    // - Lien updates position and total collateral
    // -------------------------------------------------------------
    set_block_timestamp(1000);
    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(
        f.lien_addr, alice_identity, alice_nonce, f.strk_addr, 1000 * ONE_STRK,
    );

    // INVARIANT CHECK after deposit:
    // actual STRK increase in Lien == deposit amount (1000 STRK)
    assert_protocol_invariants(@f, 1000 * ONE_STRK, 0, 1000 * ONE_STRK, 0, 0);
    let pos = f.lien_views.get_position(pos_id);
    assert(pos.collateral == 1000 * ONE_STRK, 'pos_coll_1000');
    assert(pos.debt == 0, 'pos_debt_0');
    assert(pos.status == PositionStatus::Active, 'pos_active');

    // -------------------------------------------------------------
    // Step 3: Admin seeds 50,000 USDC liquidity into Lien
    // -------------------------------------------------------------
    f.usdc.mint(owner_addr(), 50000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 50000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(50000 * ONE_USDC);

    // INVARIANT CHECK after seed liquidity:
    assert_protocol_invariants(@f, 1000 * ONE_STRK, 50000 * ONE_USDC, 1000 * ONE_STRK, 0, 50000 * ONE_USDC);

    // -------------------------------------------------------------
    // Step 4: STRK20 executes Borrow (600 USDC)
    // - Pool invokes privacy_invoke_with_computation
    // - Lien approves pool for exact 600 USDC
    // - Lien returns OpenNoteDeposit
    // - Pool consumes approval via transfer_from
    // - USDC leaves Lien exactly once
    // - Open note credited in pool
    // -------------------------------------------------------------
    let borrow_note_id = 'open_note_borrow_alice_1';
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(
        f.lien_addr, alice_identity, alice_nonce, 600 * ONE_USDC, borrow_note_id, f.usdc_addr,
    );

    // Verify open note in pool
    assert(f.pool.get_open_note_balance(borrow_note_id) == 600 * ONE_USDC, 'pool_note_balance');
    assert(f.pool.get_open_note_token(borrow_note_id) == f.usdc_addr, 'pool_note_token');
    assert(f.usdc.balance_of(f.pool_addr) == 600 * ONE_USDC.into(), 'pool_usdc_received');

    // INVARIANT CHECK after borrow:
    // actual USDC decrease from Lien == borrowed amount (600 USDC)
    // tracked total_debt == 600 USDC
    // tracked available_liquidity == 49,400 USDC
    assert_protocol_invariants(
        @f,
        1000 * ONE_STRK,
        49400 * ONE_USDC,
        1000 * ONE_STRK,
        600 * ONE_USDC,
        49400 * ONE_USDC,
    );
    let pos_after_borrow = f.lien_views.get_position(pos_id);
    assert(pos_after_borrow.debt == 600 * ONE_USDC, 'pos_debt_600');

    // -------------------------------------------------------------
    // Step 5: STRK20 executes Repayment (600 USDC)
    // - Pool transfers 600 USDC to Lien
    // - Pool calls privacy_invoke_with_computation
    // - Lien decreases total_debt, increases available_liquidity
    // -------------------------------------------------------------
    f.pool.execute_repay(
        f.lien_addr, alice_identity, alice_nonce, f.usdc_addr, 600 * ONE_USDC,
    );

    // INVARIANT CHECK after repayment:
    // actual USDC increase in Lien == repayment amount (600 USDC)
    // tracked total_debt == 0
    // tracked available_liquidity == 50,000 USDC
    assert_protocol_invariants(
        @f,
        1000 * ONE_STRK,
        50000 * ONE_USDC,
        1000 * ONE_STRK,
        0,
        50000 * ONE_USDC,
    );
    let pos_after_repay = f.lien_views.get_position(pos_id);
    assert(pos_after_repay.debt == 0, 'pos_debt_0_repaid');

    // -------------------------------------------------------------
    // Step 6: STRK20 executes Collateral Withdrawal (1000 STRK)
    // - Pool calls privacy_invoke_with_computation
    // - Lien approves pool for exact 1000 STRK
    // - Lien returns OpenNoteDeposit
    // - Pool consumes approval via transfer_from
    // - STRK leaves Lien exactly once
    // - Position transitions to Closed
    // -------------------------------------------------------------
    let withdraw_note_id = 'open_note_withdraw_alice_1';
    f.pool.execute_withdraw_collateral(
        f.lien_addr, alice_identity, alice_nonce, 1000 * ONE_STRK, withdraw_note_id, f.strk_addr,
    );

    // Verify open note in pool
    assert(f.pool.get_open_note_balance(withdraw_note_id) == 1000 * ONE_STRK, 'pool_strk_note_balance');
    assert(f.pool.get_open_note_token(withdraw_note_id) == f.strk_addr, 'pool_strk_note_token');
    assert(f.strk.balance_of(f.pool_addr) == 1000 * ONE_STRK.into(), 'pool_strk_received_back');

    // INVARIANT CHECK after complete withdrawal:
    // actual STRK decrease from Lien == withdrawal amount (1000 STRK)
    // actual STRK balance of Lien == 0
    // tracked total_collateral == 0
    assert_protocol_invariants(
        @f,
        0,
        50000 * ONE_USDC,
        0,
        0,
        50000 * ONE_USDC,
    );

    let pos_closed = f.lien_views.get_position(pos_id);
    assert(pos_closed.collateral == 0, 'pos_coll_zero');
    assert(pos_closed.debt == 0, 'pos_debt_zero');
    assert(pos_closed.status == PositionStatus::Closed, 'pos_status_closed');
}

// ============================================================
// Partial Repayment and Partial Withdrawal Invariants
// ============================================================

#[test]
fn test_e2e_strk20_partial_repay_and_withdraw() {
    let f = setup_integration();
    let alice_identity = 'alice_key_partial';
    let alice_nonce = 0;
    let pos_id = f.lien_compute.privacy_compute(alice_identity, alice_nonce);

    // 1. Shield and deposit 2000 STRK
    f.strk.mint(alice_wallet(), 2000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 2000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 2000 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(
        f.lien_addr, alice_identity, alice_nonce, f.strk_addr, 2000 * ONE_STRK,
    );

    // 2. Admin seeds 100,000 USDC
    f.usdc.mint(owner_addr(), 100000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 100000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(100000 * ONE_USDC);

    assert_protocol_invariants(@f, 2000 * ONE_STRK, 100000 * ONE_USDC, 2000 * ONE_STRK, 0, 100000 * ONE_USDC);

    // 3. Borrow 1000 USDC (max LTV is 75% of $2000 = $1500)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(
        f.lien_addr, alice_identity, alice_nonce, 1000 * ONE_USDC, 'note_borrow_p1', f.usdc_addr,
    );
    assert_protocol_invariants(@f, 2000 * ONE_STRK, 99000 * ONE_USDC, 2000 * ONE_STRK, 1000 * ONE_USDC, 99000 * ONE_USDC);

    // 4. Partial Repay 400 USDC
    f.pool.execute_repay(
        f.lien_addr, alice_identity, alice_nonce, f.usdc_addr, 400 * ONE_USDC,
    );
    // Remaining debt = 600 USDC
    assert_protocol_invariants(@f, 2000 * ONE_STRK, 99400 * ONE_USDC, 2000 * ONE_STRK, 600 * ONE_USDC, 99400 * ONE_USDC);

    // 5. Partial Withdraw 500 STRK
    // Remaining collateral = 1500 STRK ($1500). Max debt at 75% = $1125 > $600 -> safe!
    f.pool.execute_withdraw_collateral(
        f.lien_addr, alice_identity, alice_nonce, 500 * ONE_STRK, 'note_withdraw_p1', f.strk_addr,
    );
    assert_protocol_invariants(@f, 1500 * ONE_STRK, 99400 * ONE_USDC, 1500 * ONE_STRK, 600 * ONE_USDC, 99400 * ONE_USDC);

    let pos = f.lien_views.get_position(pos_id);
    assert(pos.collateral == 1500 * ONE_STRK, 'pos_coll_1500');
    assert(pos.debt == 600 * ONE_USDC, 'pos_debt_600');
    assert(pos.status == PositionStatus::Active, 'pos_still_active');
}

// ============================================================
// Multi-User Isolation & Invariant Verification
// ============================================================

#[test]
fn test_e2e_strk20_multi_user_isolation_and_invariants() {
    let f = setup_integration();
    let alice_key = 'alice_key_multi';
    let bob_key = 'bob_key_multi';
    let pos_a = f.lien_compute.privacy_compute(alice_key, 0);
    let pos_b = f.lien_compute.privacy_compute(bob_key, 0);

    // 1. Seed liquidity
    f.usdc.mint(owner_addr(), 200000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 200000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(200000 * ONE_USDC);

    // 2. Alice shields and deposits 3000 STRK
    f.strk.mint(alice_wallet(), 3000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 3000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 3000 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 3000 * ONE_STRK);

    // 3. Bob shields and deposits 5000 STRK
    f.strk.mint(bob_wallet(), 5000 * ONE_STRK.into());
    set_contract_address(bob_wallet());
    f.strk.approve(f.pool_addr, 5000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 5000 * ONE_STRK, bob_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, bob_key, 0, f.strk_addr, 5000 * ONE_STRK);

    assert_protocol_invariants(@f, 8000 * ONE_STRK, 200000 * ONE_USDC, 8000 * ONE_STRK, 0, 200000 * ONE_USDC);

    // 4. Alice borrows 1500 USDC
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 1500 * ONE_USDC, 'note_a_b', f.usdc_addr);

    // 5. Bob borrows 3000 USDC
    f.pool.execute_borrow(f.lien_addr, bob_key, 0, 3000 * ONE_USDC, 'note_b_b', f.usdc_addr);

    assert_protocol_invariants(
        @f,
        8000 * ONE_STRK,
        195500 * ONE_USDC,
        8000 * ONE_STRK,
        4500 * ONE_USDC,
        195500 * ONE_USDC,
    );

    // 6. Alice repays 500 USDC
    f.pool.execute_repay(f.lien_addr, alice_key, 0, f.usdc_addr, 500 * ONE_USDC);

    // 7. Bob withdraws 1000 STRK (remaining 4000 STRK > 3000 / 0.75 = 4000)
    f.pool.execute_withdraw_collateral(f.lien_addr, bob_key, 0, 1000 * ONE_STRK, 'note_b_w', f.strk_addr);

    assert_protocol_invariants(
        @f,
        7000 * ONE_STRK,
        196000 * ONE_USDC,
        7000 * ONE_STRK,
        4000 * ONE_USDC,
        196000 * ONE_USDC,
    );

    let alice_pos = f.lien_views.get_position(pos_a);
    let bob_pos = f.lien_views.get_position(pos_b);
    assert(alice_pos.collateral == 3000 * ONE_STRK, 'alice_coll');
    assert(alice_pos.debt == 1000 * ONE_USDC, 'alice_debt');
    assert(bob_pos.collateral == 4000 * ONE_STRK, 'bob_coll');
    assert(bob_pos.debt == 3000 * ONE_USDC, 'bob_debt');
}

// ============================================================
// Liquidation End-to-End Settlement & Invariants
// ============================================================

#[test]
fn test_e2e_strk20_liquidation_flow() {
    let f = setup_integration();
    let alice_key = 'alice_key_liq';
    let pos_id = f.lien_compute.privacy_compute(alice_key, 0);

    // 1. Alice deposits 100 STRK via STRK20
    f.strk.mint(alice_wallet(), 100 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 100 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 100 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 100 * ONE_STRK);

    // 2. Admin seeds 10,000 USDC
    f.usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 10000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(10000 * ONE_USDC);

    // 3. Alice borrows 75 USDC ($1.00/STRK, max 75% LTV)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 75 * ONE_USDC, 'note_b_liq', f.usdc_addr);

    assert_protocol_invariants(@f, 100 * ONE_STRK, 9925 * ONE_USDC, 100 * ONE_STRK, 75 * ONE_USDC, 9925 * ONE_USDC);

    // 4. Price drops to $0.50 -> 100 STRK is worth $50, debt is $75 (liquidatable!)
    set_contract_address(owner_addr());
    f.lien_admin.set_price(PRICE_050);

    // 5. Liquidator prepares USDC and approves LienHelper
    f.usdc.mint(liquidator_addr(), 100 * ONE_USDC.into());
    set_contract_address(liquidator_addr());
    f.usdc.approve(f.lien_addr, 100 * ONE_USDC.into());

    let liquidator_strk_before = f.strk.balance_of(liquidator_addr());
    let liquidator_usdc_before = f.usdc.balance_of(liquidator_addr());
    let lien_usdc_before = f.usdc.balance_of(f.lien_addr);
    let lien_strk_before = f.strk.balance_of(f.lien_addr);

    // 6. Execute liquidation
    f.lien_helper.liquidate(pos_id);

    // 7. Balance assertions:
    // actual USDC increase in Lien == debt_repaid (liquidator paid debt)
    let lien_usdc_after = f.usdc.balance_of(f.lien_addr);
    let lien_strk_after = f.strk.balance_of(f.lien_addr);
    let liquidator_usdc_after = f.usdc.balance_of(liquidator_addr());
    let liquidator_strk_after = f.strk.balance_of(liquidator_addr());

    let debt_repaid_by_liquidator = liquidator_usdc_before - liquidator_usdc_after;
    let collateral_seized_by_liquidator = liquidator_strk_after - liquidator_strk_before;

    assert(lien_usdc_after - lien_usdc_before == debt_repaid_by_liquidator, 'usdc_increase_eq_repaid');
    assert(lien_strk_before - lien_strk_after == collateral_seized_by_liquidator, 'strk_decrease_eq_seized');
    assert(collateral_seized_by_liquidator == 100 * ONE_STRK.into(), 'all_collateral_seized');

    // Position is closed and bad debt is recorded
    let pos = f.lien_views.get_position(pos_id);
    assert(pos.collateral == 0, 'coll_zero');
    assert(pos.debt == 0, 'debt_zero');
    assert(pos.status == PositionStatus::Closed, 'status_closed');
    assert(f.lien_views.get_total_collateral() == 0, 'total_coll_zero');
    assert(f.lien_views.get_total_debt() == 0, 'total_debt_zero');
    assert(f.lien_views.get_bad_debt() > 0, 'bad_debt_recorded');
}

// ============================================================
// STRK20 Interest Accrual & Invariant Test
// ============================================================

#[test]
fn test_e2e_strk20_interest_accrual_borrow_and_repay() {
    let f = setup_integration();
    let alice_key = 'alice_key_interest';
    let pos_id = f.lien_compute.privacy_compute(alice_key, 0);

    // 1. Alice deposits 10,000 STRK
    f.strk.mint(alice_wallet(), 10000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 10000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 10000 * ONE_STRK, alice_wallet());

    set_block_timestamp(0);
    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 10000 * ONE_STRK);

    // 2. Admin seeds 100,000 USDC
    f.usdc.mint(owner_addr(), 100000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 100000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(100000 * ONE_USDC);

    // 3. Alice borrows 1000 USDC at t=0 (Pool now holds 1000 USDC)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 1000 * ONE_USDC, 'note_interest_b1', f.usdc_addr);

    // 4. Advance 1 year -> 50 USDC interest accrued
    set_block_timestamp(31_536_000);

    // Alice shields an additional 50 USDC into Privacy Pool to pay interest
    f.usdc.mint(alice_wallet(), 50 * ONE_USDC.into());
    set_contract_address(alice_wallet());
    f.usdc.approve(f.pool_addr, 50 * ONE_USDC.into());
    f.pool.shield_deposit(f.usdc_addr, 50 * ONE_USDC, alice_wallet());

    // 5. Alice repays the full 1050 USDC (1000 principal + 50 interest) from Pool
    set_contract_address(f.pool_addr);
    f.pool.execute_repay(f.lien_addr, alice_key, 0, f.usdc_addr, 1050 * ONE_USDC);

    // INVARIANT CHECK:
    // Lien USDC balance increased by 1050 USDC
    // Lien available_liquidity = 100,050 USDC (includes 50 USDC interest paid)
    // tracked total_debt = 0
    assert_protocol_invariants(
        @f,
        10000 * ONE_STRK,
        100050 * ONE_USDC,
        10000 * ONE_STRK,
        0,
        100050 * ONE_USDC,
    );

    let pos = f.lien_views.get_position(pos_id);
    assert(pos.debt == 0, 'debt_zero_after_accrued_repay');
}

// ============================================================
// STRK20 Boundary & Revert Tests
// ============================================================

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_e2e_strk20_borrow_exceeds_ltv_reverts() {
    let f = setup_integration();
    let alice_key = 'alice_key_rev1';

    // Deposit 1000 STRK ($1000 value)
    f.strk.mint(alice_wallet(), 1000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 1000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 1000 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 1000 * ONE_STRK);

    f.usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 10000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(10000 * ONE_USDC);

    // Attempt to borrow 751 USDC (> 75% max LTV of $1000)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 751 * ONE_USDC, 'note_b_fail', f.usdc_addr);
}

#[test]
#[should_panic(expected: ('REPAY_EXCEEDS_DEBT', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_e2e_strk20_overpayment_reverts() {
    let f = setup_integration();
    let alice_key = 'alice_key_rev2';

    f.strk.mint(alice_wallet(), 1000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 1000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 1000 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 1000 * ONE_STRK);

    f.usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 10000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(10000 * ONE_USDC);

    // Borrow 200 USDC (Pool receives 200 USDC)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 200 * ONE_USDC, 'note_b_200', f.usdc_addr);

    // Alice shields 100 additional USDC into pool so pool has 300 USDC
    f.usdc.mint(alice_wallet(), 100 * ONE_USDC.into());
    set_contract_address(alice_wallet());
    f.usdc.approve(f.pool_addr, 100 * ONE_USDC.into());
    f.pool.shield_deposit(f.usdc_addr, 100 * ONE_USDC, alice_wallet());

    // Attempt to repay 201 USDC when debt is 200 USDC -> strictly rejected by LienHelper!
    set_contract_address(f.pool_addr);
    f.pool.execute_repay(f.lien_addr, alice_key, 0, f.usdc_addr, 201 * ONE_USDC);
}

#[test]
#[should_panic(expected: ('EXCEEDS_MAX_LTV', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_e2e_strk20_withdraw_breaks_ltv_reverts() {
    let f = setup_integration();
    let alice_key = 'alice_key_rev3';

    f.strk.mint(alice_wallet(), 1000 * ONE_STRK.into());
    set_contract_address(alice_wallet());
    f.strk.approve(f.pool_addr, 1000 * ONE_STRK.into());
    f.pool.shield_deposit(f.strk_addr, 1000 * ONE_STRK, alice_wallet());

    set_contract_address(f.pool_addr);
    f.pool.execute_deposit_collateral(f.lien_addr, alice_key, 0, f.strk_addr, 1000 * ONE_STRK);

    f.usdc.mint(owner_addr(), 10000 * ONE_USDC.into());
    set_contract_address(owner_addr());
    f.usdc.approve(f.lien_addr, 10000 * ONE_USDC.into());
    f.lien_admin.seed_liquidity(10000 * ONE_USDC);

    // Borrow 700 USDC (70% LTV)
    set_contract_address(f.pool_addr);
    f.pool.execute_borrow(f.lien_addr, alice_key, 0, 700 * ONE_USDC, 'note_b_700', f.usdc_addr);

    // Attempt to withdraw 100 STRK (leaving 900 STRK, max borrow 675 < 700 debt) -> reverts!
    f.pool.execute_withdraw_collateral(f.lien_addr, alice_key, 0, 100 * ONE_STRK, 'note_w_fail', f.strk_addr);
}

