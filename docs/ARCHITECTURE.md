# Lien Architecture & Privacy Matrix

Lien is a private lending protocol built natively on Starknet, orchestrating positions via the **STRK20 Shielded Pool Primitive**.

---

## High-Level Architecture Diagram

```
+-----------------------------------------------------------------------------------+
|                                  USER / CLIENT                                    |
|  +-------------------------------------+  +------------------------------------+  |
|  | Starknet Wallet (Argent / Braavos)  |  | STRK20 Wallet API / Shield Session |  |
|  +-------------------------------------+  +------------------------------------+  |
+------------------------------------------+----------------------------------------+
                                           |
                    (Shielded Call / Encrypted Intent)
                                           v
+-----------------------------------------------------------------------------------+
|                              STARKNET MAINNET                                     |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |                           LIEN LENDING PROTOCOL                             |  |
|  | - Stores Shielded Commitments (Position ID = hash(ViewingKey, Nonce))       |  |
|  | - Validates Borrow Capacity & LTV Bounds                                    |  |
|  | - Emits Shielded Events                                                     |  |
|  +--------------------------------------+--------------------------------------+  |
|                                         |                                         |
|                          Calls Pool     |  Settles Shielded Balance               |
|                                         v                                         |
|  +-----------------------------------------------------------------------------+  |
|  |                           STRK20 SHIELDED POOL                              |  |
|  | - Manages UTXOs / Shielded Notes (Collateral & Debt Assets)                 |  |
|  | - Handles Private Mint / Burn / Transfer of Shielded STRK                  |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## What's Public vs What's Private Matrix

| Aspect | Traditional DeFi (Aave / zkLend) | Lien (STRK20 Powered) |
| :--- | :--- | :--- |
| **Borrower Identity** | Public `ContractAddress` | **Private** (Shielded Commitment / Nullifier) |
| **Collateral Balance** | Public `u256` token balance | **Private** (Encrypted inside STRK20 Shielded Note) |
| **Debt Balance** | Public `u256` borrowed amount | **Private** (Shielded ledger state) |
| **Current LTV / Health Factor** | Publicly calculable by any bot | **Private** (Calculated off-chain / via viewing-key) |
| **Liquidation Target Warning** | Exposed in mempool / state scans | **Protected** (Triggered with shielded proofs) |
| **Protocol Total Value Locked (TVL)** | Exact sum across accounts | **Aggregate Pool TVL** (Shielded composition) |
| **Lending Interest Rate Model** | Public parameter / Utilization Curve | **Public** protocol parameter |

---

## Core Components

1. **`contracts/src/lending_pool.cairo`**:
   The core lending engine. Maintains position mappings keyed by `felt252` shielded references. Delegates balance transfers directly into the `STRK20Pool` contract.
2. **`contracts/src/interfaces.cairo`**:
   Interface definitions for `ILendingPool` and `ISTRK20Pool` (shielded transfer, deposit, withdraw, transfer_from).
3. **`contracts/src/types.cairo`**:
   Data structures including `Position` and `LoanTerms`.
4. **`frontend/lib/strk20-wallet-api.ts`**:
   Wallet-mediated integration layer connecting the frontend with STRK20 shielded sessions and note generation.
5. **`frontend/lib/lending.ts`**:
   Starknet contract dispatchers and transaction builders for deposit, borrow, repay, and liquidation flows.
