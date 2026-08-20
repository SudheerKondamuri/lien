"use client";

import React from "react";
import { AlertTriangle, ShieldCheck } from "lucide-react";

interface LiquidationWarningProps {
  currentLtvBps: number;
  maxLtvBps: number;
  liquidationThresholdBps: number;
}

export const LiquidationWarning: React.FC<LiquidationWarningProps> = ({
  currentLtvBps,
  maxLtvBps,
  liquidationThresholdBps,
}) => {
  const currentLtvPercent = (currentLtvBps / 100).toFixed(1);
  const maxLtvPercent = (maxLtvBps / 100).toFixed(1);
  const liqThresholdPercent = (liquidationThresholdBps / 100).toFixed(1);

  const isAtRisk = currentLtvBps >= maxLtvBps;

  return (
    <div
      className={`p-4 rounded-lg border font-sans text-xs ${
        isAtRisk
          ? "bg-amber-50 border-amber-200 text-amber-900"
          : "bg-paper-200 border-paper-300 text-ink-light"
      }`}
    >
      <div className="flex items-start gap-2.5">
        {isAtRisk ? (
          <AlertTriangle className="w-4 h-4 text-amber-700 shrink-0 mt-0.5" />
        ) : (
          <ShieldCheck className="w-4 h-4 text-shield-green shrink-0 mt-0.5" />
        )}
        <div className="space-y-1">
          <p className="font-medium">
            {isAtRisk
              ? "Position Approaches Liquidation Threshold"
              : "Private Solvency Status: Healthy"}
          </p>
          <p className="text-[11px] leading-relaxed text-ink-light">
            Current LTV: <span className="font-numeric font-medium">{currentLtvPercent}%</span> · Max Allowed:{" "}
            <span className="font-numeric">{maxLtvPercent}%</span> · Liquidation Trigger:{" "}
            <span className="font-numeric">{liqThresholdPercent}%</span>.
          </p>
          <p className="text-[11px] text-ink-muted italic">
            Note: Your position metrics are encrypted and shielded from public mempool surveillance.
          </p>
        </div>
      </div>
    </div>
  );
};
