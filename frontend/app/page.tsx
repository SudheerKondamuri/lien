import Link from "next/link";
import { Shield, EyeOff, Lock, ArrowRight, CheckCircle2 } from "lucide-react";

export default function Home() {
  return (
    <div className="space-y-12 py-6">
      {/* Hero Section */}
      <section className="space-y-6 max-w-2xl">
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-paper-200 border border-paper-300 rounded-full text-xs font-mono text-ink-light">
          <Shield className="w-3.5 h-3.5 text-shield-amber" />
          <span>Private Lending via STRK20 Shielded Pools</span>
        </div>

        <h1 className="font-serif text-4xl sm:text-5xl font-normal tracking-tight text-ink leading-tight">
          Borrow against crypto collateral without broadcasting your balance.
        </h1>

        <p className="text-base sm:text-lg text-ink-light font-sans leading-relaxed">
          Public DeFi lending leaks your liquidation price, loan size, and wallet net worth to
          predatory bots. Lien encapsulates your collateral and debt positions inside the STRK20
          shielded pool on Starknet mainnet.
        </p>

        <div className="flex flex-wrap items-center gap-4 pt-2">
          <Link
            href="/borrow"
            className="inline-flex items-center gap-2 px-6 py-3 bg-ink text-paper-50 font-sans text-sm font-medium rounded-md hover:bg-stone-800 transition shadow-sm"
          >
            <span>Open Shielded Position</span>
            <ArrowRight className="w-4 h-4" />
          </Link>

          <Link
            href="/position"
            className="inline-flex items-center gap-2 px-6 py-3 paper-card font-mono text-sm text-ink rounded-md hover:bg-paper-200 transition"
          >
            <span>Decrypt My Position</span>
          </Link>
        </div>
      </section>

      {/* 3 Privacy Pillars */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6 pt-6">
        <div className="paper-card p-6 rounded-lg space-y-3">
          <div className="w-9 h-9 rounded-md bg-paper-200 border border-paper-300 flex items-center justify-center text-ink">
            <EyeOff className="w-4 h-4" />
          </div>
          <h3 className="font-serif text-lg font-medium text-ink">
            Zero On-Chain LTV Exposure
          </h3>
          <p className="text-xs text-ink-light leading-relaxed">
            Your collateral ratio and health factor never appear in plaintext on explorers or mempools,
            preventing liquidation hunting.
          </p>
        </div>

        <div className="paper-card p-6 rounded-lg space-y-3">
          <div className="w-9 h-9 rounded-md bg-paper-200 border border-paper-300 flex items-center justify-center text-ink">
            <Lock className="w-4 h-4" />
          </div>
          <h3 className="font-serif text-lg font-medium text-ink">
            Shielded Pool Settlement
          </h3>
          <p className="text-xs text-ink-light leading-relaxed">
            All token deposits, debt issuance, and repayments route directly through STRK20 shielded notes
            instead of raw ERC-20 transfers.
          </p>
        </div>

        <div className="paper-card p-6 rounded-lg space-y-3">
          <div className="w-9 h-9 rounded-md bg-paper-200 border border-paper-300 flex items-center justify-center text-ink">
            <Shield className="w-4 h-4" />
          </div>
          <h3 className="font-serif text-lg font-medium text-ink">
            Viewing-Key Gated Access
          </h3>
          <p className="text-xs text-ink-light leading-relaxed">
            Only you (and entities you choose to delegate to via viewing key) can inspect and verify your
            active position terms.
          </p>
        </div>
      </section>

      {/* Protocol Parameters Overview */}
      <section className="paper-card p-6 sm:p-8 rounded-lg space-y-4">
        <div className="flex items-center justify-between border-b border-paper-200 pb-4">
          <div>
            <h3 className="font-serif text-xl font-medium text-ink">Mainnet Market Parameters</h3>
            <p className="text-xs text-ink-light font-sans">
              Cryptographically verified terms for STRK collateral & USDC borrowing
            </p>
          </div>
          <span className="px-2.5 py-1 bg-emerald-50 border border-emerald-200 text-emerald-800 font-mono text-xs rounded">
            Live
          </span>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-6 pt-2">
          <div>
            <span className="text-[11px] uppercase tracking-wider text-ink-light font-sans">
              Max LTV
            </span>
            <p className="font-numeric text-2xl font-medium text-ink mt-1">75.0%</p>
          </div>
          <div>
            <span className="text-[11px] uppercase tracking-wider text-ink-light font-sans">
              Liquidation Threshold
            </span>
            <p className="font-numeric text-2xl font-medium text-ink mt-1">85.0%</p>
          </div>
          <div>
            <span className="text-[11px] uppercase tracking-wider text-ink-light font-sans">
              Borrow APR
            </span>
            <p className="font-numeric text-2xl font-medium text-ink mt-1">5.0%</p>
          </div>
          <div>
            <span className="text-[11px] uppercase tracking-wider text-ink-light font-sans">
              Privacy Level
            </span>
            <p className="font-numeric text-xl font-medium text-shield-green mt-1">Shielded</p>
          </div>
        </div>
      </section>
    </div>
  );
}
