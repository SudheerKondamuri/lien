"use client";

import React from "react";
import { Shield, Eye, Lock, RefreshCw } from "lucide-react";
import { PositionData } from "@/lib/lending";

interface PositionCardProps {
  position: PositionData | null;
  isLoading: boolean;
  onRefresh?: () => void;
  onRepay?: () => void;
  onAddCollateral?: () => void;
}

export const PositionCard: React.FC<PositionCardProps> = ({
  position,
  isLoading,
  onRefresh,
  onRepay,
  onAddCollateral,
}) => {
  if (isLoading) {
    return (
      <div className="paper-card p-6 rounded-lg space-y-4 animate-pulse">
        <div className="h-4 bg-paper-300 rounded w-1/3"></div>
        <div className="grid grid-cols-2 gap-4 pt-2">
          <div className="h-16 bg-paper-200 rounded"></div>
          <div className="h-16 bg-paper-200 rounded"></div>
        </div>
      </div>
    );
  }

  if (!position || (position.collateralAmount === 0n && position.borrowedAmount === 0n)) {
    return (
      <div className="paper-card p-8 rounded-lg text-center space-y-3">
        <div className="w-10 h-10 mx-auto rounded-full bg-paper-200 border border-paper-300 flex items-center justify-center text-ink-light">
          <Lock className="w-5 h-5" />
        </div>
        <h3 className="font-serif text-lg text-ink font-medium">No Active Shielded Position</h3>
        <p className="text-xs text-ink-light max-w-sm mx-auto">
          Shield collateral into the STRK20 pool to open a private lending position without public ledger exposure.
        </p>
      </div>
    );
  }

  // Format bigints to human strings (assumes 18 decimals)
  const formatToken = (val: bigint) => (Number(val) / 1e18).toFixed(4);

  return (
    <div className="paper-card p-6 rounded-lg space-y-6">
      <div className="flex items-center justify-between border-b border-paper-200 pb-4">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="font-serif text-xl text-ink font-semibold">Shielded Position</h3>
            <span className="flex items-center gap-1 px-2 py-0.5 bg-paper-200 border border-paper-300 rounded text-[10px] font-mono text-shield-green">
              <Shield className="w-3 h-3" />
              Decrypted via Viewing Key
            </span>
          </div>
          <p className="text-xs font-mono text-ink-muted mt-1">
            Ref: {position.owner.slice(0, 10)}...{position.owner.slice(-6)}
          </p>
        </div>

        {onRefresh && (
          <button
            onClick={onRefresh}
            className="p-1.5 rounded hover:bg-paper-200 text-ink-light transition"
            title="Refresh on-chain state"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="paper-card-subtle p-4 rounded-md">
          <span className="text-xs font-sans text-ink-light uppercase tracking-wider">
            Shielded Collateral
          </span>
          <div className="mt-1 flex items-baseline gap-2">
            <span className="font-numeric text-2xl font-medium text-ink">
              {formatToken(position.collateralAmount)}
            </span>
            <span className="text-xs font-mono text-ink-light">STRK</span>
          </div>
        </div>

        <div className="paper-card-subtle p-4 rounded-md">
          <span className="text-xs font-sans text-ink-light uppercase tracking-wider">
            Outstanding Debt
          </span>
          <div className="mt-1 flex items-baseline gap-2">
            <span className="font-numeric text-2xl font-medium text-ink">
              {formatToken(position.borrowedAmount)}
            </span>
            <span className="text-xs font-mono text-ink-light">USDC</span>
          </div>
        </div>
      </div>

      <div className="flex items-center justify-end gap-3 pt-2">
        {onAddCollateral && (
          <button
            onClick={onAddCollateral}
            className="px-4 py-2 border border-paper-400 hover:bg-paper-200 rounded text-xs font-mono text-ink transition"
          >
            + Add Collateral
          </button>
        )}
        {onRepay && (
          <button
            onClick={onRepay}
            className="px-4 py-2 bg-ink text-paper-50 hover:bg-stone-800 rounded text-xs font-mono transition"
          >
            Repay Debt
          </button>
        )}
      </div>
    </div>
  );
};
