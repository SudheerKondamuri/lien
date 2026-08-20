#[cfg(test)]
mod tests {
    use starknet::contract_address_const;
    use lien_contracts::types::{Position, LoanTerms};
    use lien_contracts::interfaces::{ILendingPoolDispatcher, ILendingPoolDispatcherTrait};

    #[test]
    fn test_position_struct_creation() {
        let owner_ref: felt252 = 0x123456789abcdef;
        let pos = Position {
            owner: owner_ref,
            collateral_amount: 1000000000000000000_u256,
            borrowed_amount: 500000000000000000_u256,
            last_update_timestamp: 1718900000_u64,
        };

        assert(pos.owner == owner_ref, 'Owner ref mismatch');
        assert(pos.collateral_amount == 1000000000000000000_u256, 'Collateral mismatch');
        assert(pos.borrowed_amount == 500000000000000000_u256, 'Borrow mismatch');
    }

    #[test]
    fn test_loan_terms_configuration() {
        let collateral_pool = contract_address_const::<0x111>();
        let borrow_pool = contract_address_const::<0x222>();

        let terms = LoanTerms {
            collateral_pool,
            borrow_pool,
            max_ltv_bps: 7500_u16,
            liquidation_threshold_bps: 8500_u16,
            interest_rate_bps: 500_u16,
        };

        assert(terms.max_ltv_bps == 7500_u16, 'Max LTV mismatch');
        assert(terms.liquidation_threshold_bps == 8500_u16, 'Liq threshold mismatch');
        assert(terms.interest_rate_bps == 500_u16, 'Interest rate mismatch');
    }
}
