"use client";

import React from "react";
import { Shield } from "lucide-react";

interface CollateralInputProps {
  label: string;
  tokenSymbol: string;
  value: string;
  onChange: (val: string) => void;
  maxAmount?: string;
  isShielded?: boolean;
  disabled?: boolean;
}

export const CollateralInput: React.FC<CollateralInputProps> = ({
  label,
  tokenSymbol,
  value,
  onChange,
  maxAmount = "0.00",
  isShielded = true,
  disabled = false,
}) => {
  return (
    <div className="paper-card p-4 rounded-lg space-y-3">
      <div className="flex items-center justify-between text-xs text-ink-light font-sans">
        <span className="font-medium uppercase tracking-wider text-ink">{label}</span>
        {isShielded && (
          <span className="flex items-center gap-1 text-shield-amber font-mono text-[11px]">
            <Shield className="w-3 h-3" />
            Shielded Pool Note
          </span>
        )}
      </div>

      <div className="flex items-center justify-between gap-4">
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="0.00"
          disabled={disabled}
          className="w-full bg-transparent font-numeric text-2xl md:text-3xl text-ink outline-none placeholder:text-paper-400"
        />
        <div className="flex items-center gap-2 px-3 py-1.5 paper-card-subtle rounded text-xs font-mono font-medium text-ink">
          <span>{tokenSymbol}</span>
        </div>
      </div>

      <div className="flex items-center justify-between text-xs font-mono text-ink-muted pt-1 border-t border-paper-200">
        <span>Available in Pool</span>
        <button
          type="button"
          onClick={() => onChange(maxAmount)}
          className="text-ink hover:underline"
        >
          {maxAmount} {tokenSymbol} (MAX)
        </button>
      </div>
    </div>
  );
};
