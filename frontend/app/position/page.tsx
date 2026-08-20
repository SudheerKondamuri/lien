"use client";

import React, { useState } from "react";
import { PositionCard } from "@/components/PositionCard";
import { usePosition } from "@/hooks/usePosition";
import { KeyRound, Shield, RefreshCw } from "lucide-react";

export default function PositionPage() {
  const [viewingKey, setViewingKey] = useState<string>("");
  const [activePositionId, setActivePositionId] = useState<string | null>(null);

  // Position hook tied to the active shielded reference
  const { position, isLoading, refreshPosition } = usePosition(activePositionId);

  const handleUnlockWithViewingKey = (e: React.FormEvent) => {
    e.preventDefault();
    if (!viewingKey) return;
    // Derive shielded position ID from viewing key reference
    setActivePositionId(viewingKey.trim());
  };

  return (
    <div className="max-w-xl mx-auto space-y-8 py-4">
      <div className="space-y-2">
        <div className="flex items-center gap-2 text-xs font-mono text-ink-light">
          <Shield className="w-3.5 h-3.5 text-shield-amber" />
          <span>Viewing-Key Decrypted State</span>
        </div>
        <h1 className="font-serif text-3xl font-normal text-ink">
          Manage Shielded Position
        </h1>
        <p className="text-xs text-ink-light leading-relaxed font-sans">
          Positions are not publicly addressable. Provide your viewing key or shielded position commitment to decrypt your collateral status.
        </p>
      </div>

      {/* Viewing Key Gate Form */}
      <form onSubmit={handleUnlockWithViewingKey} className="paper-card p-4 rounded-lg space-y-3">
        <label className="block text-xs font-medium uppercase tracking-wider text-ink font-sans">
          Viewing Key / Position Reference
        </label>
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <KeyRound className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-ink-muted" />
            <input
              type="text"
              value={viewingKey}
              onChange={(e) => setViewingKey(e.target.value)}
              placeholder="0x04a2... (Shielded Reference)"
              className="w-full pl-9 pr-3 py-2 bg-paper-100 border border-paper-300 rounded font-mono text-xs text-ink outline-none focus:border-ink transition"
            />
          </div>
          <button
            type="submit"
            className="px-4 py-2 bg-ink text-paper-50 rounded text-xs font-sans font-medium hover:bg-stone-800 transition"
          >
            Decrypt
          </button>
        </div>
      </form>

      {/* Position Display Card */}
      <PositionCard
        position={position}
        isLoading={isLoading}
        onRefresh={refreshPosition}
        onRepay={() => alert("Repay flow triggered")}
        onAddCollateral={() => alert("Add collateral flow triggered")}
      />
    </div>
  );
}
