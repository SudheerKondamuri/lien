# The Problem: Public DeFi Lending Leaks Critical Intelligence

## Overview

In traditional transparent blockchains like Ethereum and Starknet (vanilla ERC-20), every action taken on lending protocols (Aave, Compound, Nostra, zkLend) is permanently visible on a public ledger.

While transparency is hailed as an advantage of DeFi, in lending it introduces severe negative externalities for institutional participants, whales, and everyday users alike.

---

## The 3 Critical Leaks in Public Lending Protocols

### 1. Position Size Exposure (Whale Hunting & Front-running)
- **The Issue:** Anyone can track the exact collateral balance, borrow amount, and health factor of every address.
- **The Consequence:** Large positions are actively monitored by MEV bots, copy-traders, and predatory market participants. Traders cannot build leverage without giving away their entire strategy.

### 2. Loan-to-Value (LTV) & Health Factor Surveillance
- **The Issue:** Public health factors create exact liquidation triggers known in advance by liquidators and adversarial market makers.
- **The Consequence:** Adversaries can purposefully manipulate oracle feeds or trigger price cascades in thin markets to force liquidations of known stressed positions ("liquidation hunting").

### 3. Identity-to-Balance Linkability
- **The Issue:** Public addresses connect user identity/activity directly to their net worth and credit profile.
- **The Consequence:** Lack of financial privacy prevents traditional institutions, fintechs, and high-net-worth individuals from adopting decentralized lending markets.

---

## The Lien Solution: Private Lending via STRK20

Lien solves this by routing all collateral deposits, borrows, repayments, and position management through **STRK20 shielded pool primitives**.

1. **Shielded Position References:** Positions are indexed not by raw `ContractAddress`, but by private shielded commitments/references.
2. **Encrypted State Transitions:** Collateral and borrowed tokens reside inside the STRK20 shielded pool.
3. **Private Solvency & Liquidation:** Health factor verifications and liquidation calls are verified cryptographically via zero-knowledge proofs or viewing-key delegation without revealing aggregate balance or real identity to the public mempool.
