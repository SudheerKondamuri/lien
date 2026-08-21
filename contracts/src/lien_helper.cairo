/// LienHelper — STRK20 anonymizer contract for the Lien lending protocol.
///
/// This is the single deployed contract. It is called by the STRK20 Privacy Pool
/// during ComputeAndInvoke flows. It is NOT called directly by users.
///
/// Authorization model:
///   - privacy_compute: called off-chain by the STRK20 Virtual OS
///   - privacy_invoke_with_computation: called on-chain by the Privacy Pool ONLY
///   - liquidate: permissionless, anyone can call (executes real token settlement)
///   - admin functions: owner only (executes real token settlement)
///
/// Privacy model:
///   PRIVATE: borrower wallet identity, link between wallet and position
///   PUBLIC: position_id, collateral, debt, LTV, liquidation eligibility

#[starknet::contract]
pub mod LienHelper {
    use core::poseidon::PoseidonTrait;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    use crate::types::{
        Position, PositionStatus, MarketConfig, LienOperation, OpenNoteDeposit, LiquidationResult,
    };
    use crate::errors::errors;
    use crate::risk;
    use crate::interest;
    use crate::liquidation;
    use crate::interfaces::{
        ILienCompute, ILienHelper, ILienAdmin, ILienViews, IERC20Dispatcher, IERC20DispatcherTrait,
    };

    // ================================================================
    // Constants
    // ================================================================

    /// Domain separator for position ID derivation.
    /// position_id = Poseidon('LIEN_POSITION:V1', identity_key, position_nonce)
    const POSITION_DOMAIN_TAG: felt252 = 'LIEN_POSITION:V1';

    // ================================================================
    // Storage
    // ================================================================

    #[storage]
    struct Storage {
        /// Address of the STRK20 Privacy Pool — the ONLY allowed caller of
        /// privacy_invoke_with_computation.
        privacy_pool: ContractAddress,

        /// Protocol admin/owner address.
        owner: ContractAddress,

        /// Market configuration (single market V1: STRK/USDC).
        market_config: MarketConfig,

        /// Oracle price: USDC per STRK, scaled by 10^18.
        /// WARNING: Manual oracle — hackathon V1 limitation, NOT production-ready.
        price: u256,

        /// Per-position state, keyed by position_id (felt252).
        positions: Map<felt252, Position>,

        // ---- Global accounting ----

        /// Sum of all position collateral (STRK base units).
        total_collateral: u128,

        /// Sum of all position debt (USDC base units).
        total_debt: u128,

        /// USDC available for lending.
        available_liquidity: u128,

        /// Cumulative bad debt recognized from liquidations (USDC base units).
        bad_debt: u128,
    }

    // ================================================================
    // Events
    // ================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DepositCollateral: DepositCollateral,
        Borrow: Borrow,
        Repay: Repay,
        WithdrawCollateral: WithdrawCollateral,
        Liquidated: Liquidated,
        BadDebtRecognized: BadDebtRecognized,
        PriceUpdated: PriceUpdated,
        LiquiditySeeded: LiquiditySeeded,
        LiquidityWithdrawn: LiquidityWithdrawn,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositCollateral {
        #[key]
        pub position_id: felt252,
        pub amount: u128,
        pub new_collateral: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Borrow {
        #[key]
        pub position_id: felt252,
        pub amount: u128,
        pub new_debt: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Repay {
        #[key]
        pub position_id: felt252,
        pub amount: u128,
        pub remaining_debt: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawCollateral {
        #[key]
        pub position_id: felt252,
        pub amount: u128,
        pub remaining_collateral: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Liquidated {
        #[key]
        pub position_id: felt252,
        pub collateral_seized: u128,
        pub debt_repaid: u128,
        pub liquidator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BadDebtRecognized {
        #[key]
        pub position_id: felt252,
        pub amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PriceUpdated {
        pub new_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquiditySeeded {
        pub amount: u128,
        pub admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityWithdrawn {
        pub amount: u128,
        pub admin: ContractAddress,
    }

    // ================================================================
    // Constructor
    // ================================================================

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        privacy_pool: ContractAddress,
        collateral_token: ContractAddress,
        debt_token: ContractAddress,
        max_ltv_bps: u16,
        liquidation_threshold_bps: u16,
        liquidation_bonus_bps: u16,
        interest_rate_bps: u16,
        initial_price: u256,
    ) {
        // Address sanity checks
        assert(!owner.is_zero(), errors::ZERO_ADDRESS);
        assert(!privacy_pool.is_zero(), errors::ZERO_ADDRESS);
        assert(!collateral_token.is_zero(), errors::ZERO_ADDRESS);
        assert(!debt_token.is_zero(), errors::ZERO_ADDRESS);
        assert(collateral_token != debt_token, errors::IDENTICAL_TOKENS);

        // Market parameter sanity checks
        assert(max_ltv_bps > 0 && max_ltv_bps < 10000, errors::INVALID_MARKET_CONFIG);
        assert(
            liquidation_threshold_bps > max_ltv_bps
                && liquidation_threshold_bps <= 10000,
            errors::INVALID_MARKET_CONFIG,
        );
        assert(liquidation_bonus_bps <= 2000, errors::INVALID_MARKET_CONFIG); // max 20% bonus
        assert(interest_rate_bps <= 10000, errors::INVALID_MARKET_CONFIG); // max 100% APR
        assert(initial_price > 0, errors::ZERO_PRICE);

        self.owner.write(owner);
        self.privacy_pool.write(privacy_pool);
        self.price.write(initial_price);

        self
            .market_config
            .write(
                MarketConfig {
                    collateral_token,
                    debt_token,
                    max_ltv_bps,
                    liquidation_threshold_bps,
                    liquidation_bonus_bps,
                    interest_rate_bps,
                },
            );
    }

    // ================================================================
    // ILienCompute — called off-chain by STRK20 Virtual OS
    // ================================================================

    #[abi(embed_v0)]
    pub impl LienComputeImpl of ILienCompute<ContractState> {
        /// Derives the pseudonymous position identifier.
        ///
        /// position_id = Poseidon(POSITION_DOMAIN_TAG, identity_key, position_nonce)
        ///
        /// identity_key is derived by the STRK20 Virtual OS from:
        ///   h('IDENTITY_KEY_TAG:V1', user_addr, user_private_key, LienHelper_address)
        /// and is NEVER visible on-chain.
        fn privacy_compute(
            self: @ContractState, identity_key: felt252, position_nonce: felt252,
        ) -> felt252 {
            PoseidonTrait::new()
                .update_with(POSITION_DOMAIN_TAG)
                .update_with(identity_key)
                .update_with(position_nonce)
                .finalize()
        }
    }

    // ================================================================
    // ILienHelper — called on-chain by the STRK20 Privacy Pool
    // ================================================================

    #[abi(embed_v0)]
    pub impl LienHelperImpl of ILienHelper<ContractState> {
        /// Executes a position state transition.
        ///
        /// CRITICAL: Only callable by the configured STRK20 Privacy Pool.
        /// position_id is the verified output of privacy_compute, injected by the pool.
        ///
        /// Token movement:
        ///   For DepositCollateral/Repay: tokens were already transferred TO this contract
        ///   by the STRK20 Privacy Pool before calling privacy_invoke_with_computation.
        ///   For Borrow/WithdrawCollateral: this contract approves the Privacy Pool to pull
        ///   tokens, and returns OpenNoteDeposit instructions for the pool to mint shielded notes.
        fn privacy_invoke_with_computation(
            ref self: ContractState,
            position_id: felt252,
            operation: LienOperation,
            amount: u128,
            note_id: felt252,
        ) -> (Span<OpenNoteDeposit>, Span<ContractAddress>) {
            // Auth: only the privacy pool may call this
            assert(get_caller_address() == self.privacy_pool.read(), errors::UNAUTHORIZED_CALLER);
            assert(amount > 0, errors::ZERO_AMOUNT);

            match operation {
                LienOperation::DepositCollateral => {
                    self._deposit_collateral(position_id, amount);
                    (array![].span(), array![].span())
                },
                LienOperation::Borrow => {
                    let config = self.market_config.read();
                    let deposit = self._borrow(position_id, amount, note_id, config);
                    (array![deposit].span(), array![config.debt_token].span())
                },
                LienOperation::Repay => {
                    self._repay(position_id, amount);
                    (array![].span(), array![].span())
                },
                LienOperation::WithdrawCollateral => {
                    let config = self.market_config.read();
                    let deposit = self._withdraw_collateral(position_id, amount, note_id, config);
                    (array![deposit].span(), array![config.collateral_token].span())
                },
            }
        }

        /// Public, permissionless liquidation.
        /// NOT routed through the privacy pool — anyone can call.
        ///
        /// Full-close model with real token settlement:
        /// 1. Liquidator transfers debt_repaid USDC to this contract via transfer_from.
        /// 2. This contract transfers collateral_seized STRK to the liquidator via transfer.
        /// Checks-effects-interactions: all storage updated BEFORE external ERC-20 transfers.
        fn liquidate(ref self: ContractState, position_id: felt252) {
            let liquidator = get_caller_address();
            assert(!liquidator.is_zero(), errors::ZERO_ADDRESS);

            let config = self.market_config.read();
            let current_price = self.price.read();
            assert(current_price > 0, errors::ZERO_PRICE);

            // Read position and verify active status
            let mut position = self.positions.read(position_id);
            assert(position.status == PositionStatus::Active, errors::POSITION_NOT_FOUND);
            assert(position.collateral > 0 || position.debt > 0, errors::POSITION_NOT_FOUND);

            // Accrue interest up to now
            let now = get_block_timestamp();
            let elapsed = now - position.last_updated;
            let accrued = interest::compute_accrued_interest(
                position.debt, config.interest_rate_bps, elapsed,
            );
            position.debt = position.debt + accrued;
            self.total_debt.write(self.total_debt.read() + accrued);

            // Check liquidatability
            let coll_value = risk::collateral_value_in_debt(position.collateral, current_price);
            assert(
                risk::is_liquidatable(coll_value, position.debt, config.liquidation_threshold_bps),
                errors::POSITION_NOT_LIQUIDATABLE,
            );

            // Compute liquidation outcome
            let result: LiquidationResult = liquidation::compute_liquidation(
                position.collateral, position.debt, current_price, config.liquidation_bonus_bps,
            );

            // Effects: update position
            position.collateral = position.collateral - result.collateral_seized;
            position.debt = position.debt - (result.debt_repaid + result.bad_debt_incurred);
            position.last_updated = now;
            if position.collateral == 0 && position.debt == 0 {
                position.status = PositionStatus::Closed;
            }
            self.positions.write(position_id, position);

            // Effects: update global accounting
            self
                .total_collateral
                .write(self.total_collateral.read() - result.collateral_seized);
            self
                .total_debt
                .write(self.total_debt.read() - (result.debt_repaid + result.bad_debt_incurred));
            self.available_liquidity.write(self.available_liquidity.read() + result.debt_repaid);

            if result.bad_debt_incurred > 0 {
                self.bad_debt.write(self.bad_debt.read() + result.bad_debt_incurred);
                self
                    .emit(
                        BadDebtRecognized {
                            position_id, amount: result.bad_debt_incurred,
                        },
                    );
            }

            self
                .emit(
                    Liquidated {
                        position_id,
                        collateral_seized: result.collateral_seized,
                        debt_repaid: result.debt_repaid,
                        liquidator,
                    },
                );

            // Interactions: Real ERC-20 token settlement
            // 1. Liquidator transfers debt tokens (USDC) to this contract
            if result.debt_repaid > 0 {
                let debt_token = IERC20Dispatcher { contract_address: config.debt_token };
                let success = debt_token
                    .transfer_from(
                        liquidator, get_contract_address(), result.debt_repaid.into(),
                    );
                assert(success, errors::TRANSFER_FROM_FAILED);
            }

            // 2. Contract transfers seized collateral tokens (STRK) to liquidator
            if result.collateral_seized > 0 {
                let coll_token = IERC20Dispatcher { contract_address: config.collateral_token };
                let success = coll_token.transfer(liquidator, result.collateral_seized.into());
                assert(success, errors::TRANSFER_FAILED);
            }
        }
    }

    // ================================================================
    // ILienAdmin — owner-only configuration with token settlement
    // ================================================================

    #[abi(embed_v0)]
    pub impl LienAdminImpl of ILienAdmin<ContractState> {
        /// Sets the oracle price.
        /// WARNING: Manual oracle — hackathon V1 limitation. NOT production-ready.
        fn set_price(ref self: ContractState, price: u256) {
            assert(get_caller_address() == self.owner.read(), errors::UNAUTHORIZED_CALLER);
            assert(price > 0, errors::ZERO_PRICE);
            self.price.write(price);
            self.emit(PriceUpdated { new_price: price });
        }

        /// Seeds USDC liquidity for borrowing.
        /// Transfers USDC from caller (owner) to this contract.
        fn seed_liquidity(ref self: ContractState, amount: u128) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), errors::UNAUTHORIZED_CALLER);
            assert(amount > 0, errors::ZERO_AMOUNT);

            let config = self.market_config.read();
            let debt_token = IERC20Dispatcher { contract_address: config.debt_token };

            // Real token settlement: transfer USDC into the contract
            let success = debt_token
                .transfer_from(caller, get_contract_address(), amount.into());
            assert(success, errors::TRANSFER_FROM_FAILED);

            self.available_liquidity.write(self.available_liquidity.read() + amount);
            self.emit(LiquiditySeeded { amount, admin: caller });
        }

        /// Withdraws excess USDC liquidity (admin only).
        /// Transfers USDC from this contract to caller (owner).
        fn withdraw_liquidity(ref self: ContractState, amount: u128) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), errors::UNAUTHORIZED_CALLER);
            assert(amount > 0, errors::ZERO_AMOUNT);

            let current = self.available_liquidity.read();
            assert(amount <= current, errors::INSUFFICIENT_LIQUIDITY);

            // Effect before interaction
            self.available_liquidity.write(current - amount);

            // Real token settlement: transfer USDC out to owner
            let config = self.market_config.read();
            let debt_token = IERC20Dispatcher { contract_address: config.debt_token };
            let success = debt_token.transfer(caller, amount.into());
            assert(success, errors::TRANSFER_FAILED);

            self.emit(LiquidityWithdrawn { amount, admin: caller });
        }
    }

    // ================================================================
    // ILienViews — public read-only state inspection
    // ================================================================

    #[abi(embed_v0)]
    pub impl LienViewsImpl of ILienViews<ContractState> {
        fn get_position(self: @ContractState, position_id: felt252) -> Position {
            self.positions.read(position_id)
        }

        fn get_market_config(self: @ContractState) -> MarketConfig {
            self.market_config.read()
        }

        fn get_price(self: @ContractState) -> u256 {
            self.price.read()
        }

        fn get_total_collateral(self: @ContractState) -> u128 {
            self.total_collateral.read()
        }

        fn get_total_debt(self: @ContractState) -> u128 {
            self.total_debt.read()
        }

        fn get_available_liquidity(self: @ContractState) -> u128 {
            self.available_liquidity.read()
        }

        fn get_bad_debt(self: @ContractState) -> u128 {
            self.bad_debt.read()
        }

        fn get_privacy_pool(self: @ContractState) -> ContractAddress {
            self.privacy_pool.read()
        }
    }

    // ================================================================
    // Internal operation handlers
    // ================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Deposit collateral into a position.
        /// Activates position if inactive.
        /// STRK tokens are transferred into this contract by the STRK20 Privacy Pool
        /// prior to this call.
        fn _deposit_collateral(
            ref self: ContractState, position_id: felt252, amount: u128,
        ) {
            let mut position = self.positions.read(position_id);
            assert(position.status != PositionStatus::Closed, errors::POSITION_CLOSED);

            let now = get_block_timestamp();

            if position.status == PositionStatus::Active {
                let config = self.market_config.read();
                let elapsed = now - position.last_updated;
                let accrued = interest::compute_accrued_interest(
                    position.debt, config.interest_rate_bps, elapsed,
                );
                position.debt = position.debt + accrued;
                self.total_debt.write(self.total_debt.read() + accrued);
            } else {
                position.status = PositionStatus::Active;
            }

            position.collateral = position.collateral + amount;
            position.last_updated = now;
            self.positions.write(position_id, position);

            self.total_collateral.write(self.total_collateral.read() + amount);

            self
                .emit(
                    DepositCollateral {
                        position_id, amount, new_collateral: position.collateral,
                    },
                );
        }

        /// Borrow debt tokens against existing collateral.
        /// Approves the STRK20 Privacy Pool to pull debt tokens, and returns
        /// OpenNoteDeposit for the pool to create a shielded note for the borrower.
        fn _borrow(
            ref self: ContractState,
            position_id: felt252,
            amount: u128,
            note_id: felt252,
            config: MarketConfig,
        ) -> OpenNoteDeposit {
            let now = get_block_timestamp();
            let current_price = self.price.read();
            assert(current_price > 0, errors::ZERO_PRICE);

            let mut position = self.positions.read(position_id);
            assert(position.status == PositionStatus::Active, errors::POSITION_NOT_FOUND);
            assert(position.collateral > 0, errors::INSUFFICIENT_COLLATERAL);

            // Accrue interest
            let elapsed = now - position.last_updated;
            let accrued = interest::compute_accrued_interest(
                position.debt, config.interest_rate_bps, elapsed,
            );
            position.debt = position.debt + accrued;
            self.total_debt.write(self.total_debt.read() + accrued);

            // Check LTV after adding new borrow
            let new_debt = position.debt + amount;
            let coll_value = risk::collateral_value_in_debt(position.collateral, current_price);
            let max_debt = risk::max_debt_for_collateral_value(coll_value, config.max_ltv_bps);
            let new_debt_u256: u256 = new_debt.into();
            assert(new_debt_u256 <= max_debt, errors::EXCEEDS_MAX_LTV);

            // Check liquidity
            let liquidity = self.available_liquidity.read();
            assert(amount <= liquidity, errors::INSUFFICIENT_LIQUIDITY);

            // Effects
            position.debt = new_debt;
            position.last_updated = now;
            self.positions.write(position_id, position);

            self.total_debt.write(self.total_debt.read() + amount);
            self.available_liquidity.write(liquidity - amount);

            self.emit(Borrow { position_id, amount, new_debt: position.debt });

            // Settlement: approve privacy pool to pull the borrowed debt tokens
            let pool = self.privacy_pool.read();
            let debt_token = IERC20Dispatcher { contract_address: config.debt_token };
            let success = debt_token.approve(pool, amount.into());
            assert(success, errors::APPROVE_FAILED);

            // Return deposit instruction for the pool to create a shielded note
            OpenNoteDeposit { note_id, token: config.debt_token, amount }
        }

        /// Repay debt on an active position.
        /// Tokens were already transferred to this contract by the pool before this call.
        /// Strictly rejects repayment exceeding outstanding debt to avoid unrecorded overpayment.
        fn _repay(ref self: ContractState, position_id: felt252, amount: u128) {
            let config = self.market_config.read();
            let now = get_block_timestamp();

            let mut position = self.positions.read(position_id);
            assert(position.status == PositionStatus::Active, errors::POSITION_NOT_FOUND);
            assert(position.debt > 0, errors::ZERO_DEBT);

            // Accrue interest
            let elapsed = now - position.last_updated;
            let accrued = interest::compute_accrued_interest(
                position.debt, config.interest_rate_bps, elapsed,
            );
            position.debt = position.debt + accrued;
            self.total_debt.write(self.total_debt.read() + accrued);

            // Strict check: do not accept overpayment without refund mechanism
            assert(amount <= position.debt, errors::REPAY_EXCEEDS_DEBT);

            // Effects
            position.debt = position.debt - amount;
            position.last_updated = now;
            if position.debt == 0 && position.collateral == 0 {
                position.status = PositionStatus::Closed;
            }
            self.positions.write(position_id, position);

            self.total_debt.write(self.total_debt.read() - amount);
            self.available_liquidity.write(self.available_liquidity.read() + amount);

            self.emit(Repay { position_id, amount, remaining_debt: position.debt });
        }

        /// Withdraw collateral from an active position.
        /// Approves the STRK20 Privacy Pool to pull collateral tokens, and returns
        /// OpenNoteDeposit for the pool to create a shielded note for the borrower.
        fn _withdraw_collateral(
            ref self: ContractState,
            position_id: felt252,
            amount: u128,
            note_id: felt252,
            config: MarketConfig,
        ) -> OpenNoteDeposit {
            let now = get_block_timestamp();
            let current_price = self.price.read();
            assert(current_price > 0, errors::ZERO_PRICE);

            let mut position = self.positions.read(position_id);
            assert(position.status == PositionStatus::Active, errors::POSITION_NOT_FOUND);
            assert(amount <= position.collateral, errors::INSUFFICIENT_COLLATERAL);

            // Accrue interest
            let elapsed = now - position.last_updated;
            let accrued = interest::compute_accrued_interest(
                position.debt, config.interest_rate_bps, elapsed,
            );
            position.debt = position.debt + accrued;
            self.total_debt.write(self.total_debt.read() + accrued);

            // Check that remaining collateral still covers debt at max LTV
            let remaining_collateral = position.collateral - amount;
            if position.debt > 0 {
                let remaining_value = risk::collateral_value_in_debt(
                    remaining_collateral, current_price,
                );
                let max_debt = risk::max_debt_for_collateral_value(
                    remaining_value, config.max_ltv_bps,
                );
                let debt_u256: u256 = position.debt.into();
                assert(debt_u256 <= max_debt, errors::EXCEEDS_MAX_LTV);
            }

            // Effects
            position.collateral = remaining_collateral;
            position.last_updated = now;
            if position.collateral == 0 && position.debt == 0 {
                position.status = PositionStatus::Closed;
            }
            self.positions.write(position_id, position);

            self.total_collateral.write(self.total_collateral.read() - amount);

            self
                .emit(
                    WithdrawCollateral {
                        position_id, amount, remaining_collateral: position.collateral,
                    },
                );

            // Settlement: approve privacy pool to pull the collateral tokens
            let pool = self.privacy_pool.read();
            let collateral_token = IERC20Dispatcher { contract_address: config.collateral_token };
            let success = collateral_token.approve(pool, amount.into());
            assert(success, errors::APPROVE_FAILED);

            // Return deposit instruction for the pool to create a shielded note
            OpenNoteDeposit { note_id, token: config.collateral_token, amount }
        }
    }
}
