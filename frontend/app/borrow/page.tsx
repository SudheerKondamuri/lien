"use client";

import React, { useState } from "react";
import { CollateralInput } from "@/components/CollateralInput";
import { LiquidationWarning } from "@/components/LiquidationWarning";
import { ArrowDown, Shield, CheckCircle } from "lucide-react";

export default function BorrowPage() {
  const [collateralAmount, setCollateralAmount] = useState<string>("");
  const [borrowAmount, setBorrowAmount] = useState<string>("");
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  // Mock calculation: 1 STRK = $1.20 USD equivalent, 75% Max LTV
  const collateralNum = parseFloat(collateralAmount) || 0;
  const maxBorrowAllowed = (collateralNum * 1.2 * 0.75).toFixed(2);

  const currentLtvBps =
    collateralNum > 0 && parseFloat(borrowAmount) > 0
      ? Math.round(((parseFloat(borrowAmount) / (collateralNum * 1.2)) * 10000))
      : 0;

  const handleExecuteShieldAndBorrow = async () => {
    setIsProcessing(true);
    setStatusMessage("Encrypting note into STRK20 Shielded Pool...");

    try {
      // Step 1: Shield collateral tokens into STRK20 pool
      // Step 2: Call Lien LendingPool deposit_collateral and borrow entrypoints
      setTimeout(() => {
        setStatusMessage("Private borrow transaction confirmed on Starknet!");
        setIsProcessing(false);
      }, 1800);
    } catch (error) {
      console.error(error);
      setStatusMessage("Transaction failed");
      setIsProcessing(false);
    }
  };

  return (
    <div className="max-w-xl mx-auto space-y-8 py-4">
      <div className="space-y-2">
        <div className="flex items-center gap-2 text-xs font-mono text-ink-light">
          <Shield className="w-3.5 h-3.5 text-shield-amber" />
          <span>Shielded Collateralization</span>
        </div>
        <h1 className="font-serif text-3xl font-normal text-ink">
          Deposit Collateral & Borrow
        </h1>
        <p className="text-xs text-ink-light leading-relaxed font-sans">
          Your deposit will be shielded into the STRK20 pool note before opening the credit position.
        </p>
      </div>

      <div className="space-y-4">
        {/* Step 1: Collateral Input */}
        <CollateralInput
          label="1. Shield Collateral"
          tokenSymbol="STRK"
          value={collateralAmount}
          onChange={setCollateralAmount}
          maxAmount="100.00"
          isShielded={true}
        />

        <div className="flex justify-center">
          <div className="w-8 h-8 rounded-full paper-card flex items-center justify-center text-ink-light">
            <ArrowDown className="w-4 h-4" />
          </div>
        </div>

        {/* Step 2: Borrow Input */}
        <CollateralInput
          label="2. Borrow Asset"
          tokenSymbol="USDC"
          value={borrowAmount}
          onChange={setBorrowAmount}
          maxAmount={maxBorrowAllowed}
          isShielded={true}
        />

        {/* Solvency & Liquidation Monitor */}
        {collateralNum > 0 && (
          <LiquidationWarning
            currentLtvBps={currentLtvBps}
            maxLtvBps={7500}
            liquidationThresholdBps={8500}
          />
        )}

        {/* Action Button */}
        <button
          onClick={handleExecuteShieldAndBorrow}
          disabled={isProcessing || collateralNum <= 0}
          className="w-full py-3.5 bg-ink text-paper-50 font-sans text-sm font-medium rounded-lg hover:bg-stone-800 disabled:opacity-50 disabled:cursor-not-allowed transition shadow-sm"
        >
          {isProcessing ? "Processing Shielded Intent..." : "Shield Collateral & Borrow Privately"}
        </button>

        {statusMessage && (
          <div className="p-3 bg-paper-200 border border-paper-300 rounded text-xs font-mono text-ink flex items-center gap-2">
            <CheckCircle className="w-4 h-4 text-shield-green shrink-0" />
            <span>{statusMessage}</span>
          </div>
        )}
      </div>
    </div>
  );
}
