# Lien 🏛️🔒

> **Private, shielded lending protocol on Starknet mainnet powered by STRK20.**

Lien enables users to deposit collateral, borrow assets, and manage loans without revealing their wallet address, position sizes, loan-to-value (LTV) ratios, or liquidation proximity on-chain.

Built for the **STRK20 Private Sprint Hackathon**.

---

## 🛑 The Problem

In public lending protocols (e.g., Aave, Compound, zkLend, Nostra), every loan parameter is transparent:
- **Whale Hunting & MEV:** Predatory actors and arbitrage bots monitor large positions to front-run movements.
- **Liquidation Sniping:** Public LTV and health factor values allow adversarial traders to manipulate thin markets and trigger forced liquidations.
- **Financial Surveillance:** Public linkability between wallet addresses and loan amounts prevents institutional and privacy-conscious users from adopting DeFi credit.

For deeper analysis, read [docs/PROBLEM.md](docs/PROBLEM.md).

---

## ⚡ The Solution

Lien routes all lending actions through the **STRK20 Shielded Pool Primitive**:
- **Shielded Position References:** Positions are stored as cryptographic commitments rather than raw user addresses.
- **Private Collateral & Borrow Balances:** Balances are transferred and maintained inside the STRK20 shielded pool.
- **Protected Solvency Checks:** Position health is evaluated private to the user using viewing keys and zero-knowledge proofs.

---

## 📊 What's Public vs. What's Private

| Feature | Traditional Lending | Lien (STRK20) |
| :--- | :--- | :--- |
| **Borrower Identity** | Public `ContractAddress` | 🔒 **Private** (Shielded Commitment / Nullifier) |
| **Collateral Amount** | Publicly visible on explorer | 🔒 **Private** (Encrypted in STRK20 note) |
| **Borrowed Amount** | Publicly visible on explorer | 🔒 **Private** (Shielded debt balance) |
| **Position LTV & Health** | Trackable by bots | 🔒 **Private** (Viewing-key accessible) |
| **Liquidation Target Alert** | Public mempool beacon | 🔒 **Protected** (Zero-knowledge liquidation verification) |
| **Interest Rate Parameters** | Public rule | 🌐 **Public** (Transparent rate curve) |

For architecture diagrams and technical details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 📁 Repository Structure

```
lien/
├── README.md                          # Project overview, problem statement, architecture
├── .gitignore
├── contracts/                         # Cairo lending protocol (Scarb + Starknet Foundry)
│   ├── Scarb.toml
│   ├── src/
│   │   ├── lib.cairo
│   │   ├── lending_pool.cairo         # Core: deposit, borrow, repay, liquidate
│   │   ├── interfaces.cairo           # ILendingPool, ISTRK20Pool trait defs
│   │   └── types.cairo                # Position struct, LoanTerms struct
│   └── tests/
│       └── test_lending_pool.cairo
├── frontend/                          # Next.js 14 App Router + Tailwind CSS (Editorial theme)
│   ├── package.json
│   ├── next.config.js
│   ├── tailwind.config.ts
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx                   # Landing & wallet connect
│   │   ├── borrow/page.tsx            # Shield collateral + borrow flow
│   │   ├── position/page.tsx          # Private position management (viewing-key gated)
│   │   └── globals.css
│   ├── components/                    # Typed UI components
│   ├── lib/                           # Starknet.js + STRK20 Wallet API + Contract bindings
│   └── hooks/                         # usePosition hook
├── docs/
│   ├── ARCHITECTURE.md                # Privacy matrix & high-level architecture
│   └── PROBLEM.md                     # Problem statement & market research
└── scripts/
    └── deploy.sh                      # Starknet mainnet deployment script
```

---

## 🚀 Quick Start

### Prerequisites
- [Scarb](https://docs.swmansion.com/scarb/) (Cairo package manager, v2.5.0+)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) (Testing & deployment tools, `snforge` / `sncast`)
- [Node.js](https://nodejs.org/) (v18.17+ or v20+) & `npm` / `pnpm`

### 1. Smart Contracts Setup

```bash
# Navigate to contracts directory
cd contracts

# Build Cairo contracts
scarb build

# Run unit tests
snforge test
```

### 2. Frontend Setup

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000) to access the Lien interface.

---

## 📜 Deployment (Starknet Mainnet)

Configure your deployment environment variables and run:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

---

## 🛡️ License

MIT License.
