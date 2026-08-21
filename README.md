# Lien 🏛️🔒

> **Anonymous, overcollateralized lending protocol on Starknet mainnet powered by STRK20.**

Lien enables users to deposit collateral, borrow assets, and manage loans without publicly linking their wallet identity to their lending position. Position collateral, debt, LTV, and liquidation status remain publicly auditable under STRK20's current anonymizer model.

Built for the **STRK20 Private Sprint Hackathon**.

---

## 🛑 The Problem

In public lending protocols (e.g., Aave, Compound, zkLend, Nostra), every loan is linkable to a wallet:
- **Whale Hunting & MEV:** Predatory actors monitor *specific users'* large positions to front-run their movements.
- **Liquidation Sniping:** Knowing *who* holds an underwater position lets adversarial traders target them with market manipulation.
- **Credit Profiling:** Public linkability between wallet addresses and borrowing history enables financial surveillance and discriminatory behavior.

For deeper analysis, read [docs/PROBLEM.md](docs/PROBLEM.md).

---

## ⚡ The Solution

Lien routes all lending actions through the **STRK20 Privacy Pool** as an anonymizer contract:
- **Anonymous Positions:** Borrowing, repaying, and liquidating happen via `privacy_invoke` — observers see the Lien helper contract interact with the pool, not which wallet initiated the action.
- **Unlinkable Identity:** Position IDs are hash-based secrets known only to the borrower. No on-chain mapping connects a position to a wallet address.
- **Composable Privacy:** After repayment, borrowed funds return to the STRK20 pool as private notes, fully unlinkable from the original loan.

---

## 📊 What's Public vs. What's Private

| Feature | Traditional Lending | Lien (STRK20) |
| :--- | :--- | :--- |
| **Borrower Identity** | Public wallet address | 🔒 **Hidden** — STRK20 anonymizer breaks the wallet→position link |
| **Position ↔ Wallet Link** | Trivially observable | 🔒 **Hidden** — hash-based position ID, no on-chain wallet reference |
| **Collateral Amount** | Publicly visible | 🌐 **Public** — stored on-chain in the Lien helper contract |
| **Borrowed Amount** | Publicly visible | 🌐 **Public** — stored on-chain in the Lien helper contract |
| **Position LTV & Health** | Trackable and linkable to a user | 🌐 **Public** — derivable from position state, but not attributable to any user |
| **Liquidation Eligibility** | Public and targetable per-user | 🌐 **Public** — anyone can liquidate, but can't identify *who* they're liquidating |
| **Interest Rate Parameters** | Public | 🌐 **Public** — transparent rate model |

> **Privacy model:** Identity privacy (anonymity), not financial state privacy (confidentiality). This matches the STRK20 anonymizer model used by all STRK20 DeFi integrations (Vesu, AVNU).

For architecture diagrams and technical details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 📁 Repository Structure

```
lien/
├── README.md                          # Project overview, privacy model, architecture
├── .gitignore
├── contracts/                         # Cairo lending protocol (Scarb + Starknet Foundry)
│   ├── Scarb.toml
│   ├── src/
│   │   ├── lib.cairo
│   │   ├── lien_helper.cairo          # Anonymizer contract: privacy_invoke entry point
│   │   ├── interfaces.cairo           # ILienHelper trait definition
│   │   └── types.cairo                # Position, MarketConfig structs
│   └── tests/
│       └── test_lien_helper.cairo
├── frontend/                          # Next.js 14 App Router + Tailwind CSS
│   ├── package.json
│   ├── next.config.js
│   ├── tailwind.config.ts
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx                   # Landing & wallet connect
│   │   ├── borrow/page.tsx            # Shield collateral + borrow flow
│   │   ├── position/page.tsx          # Position management (position secret required)
│   │   └── globals.css
│   ├── components/
│   ├── lib/                           # starknet.js + STRK20 Wallet API integration
│   └── hooks/
├── docs/
│   ├── ARCHITECTURE.md                # Privacy model, call flow, security invariants
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
cd contracts
scarb build
snforge test
```

### 2. Frontend Setup

```bash
cd frontend
npm install
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
