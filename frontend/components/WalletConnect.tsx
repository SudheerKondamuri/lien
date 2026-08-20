"use client";

import React, { useState } from "react";
import { ShieldCheck, ShieldAlert, Wallet, KeyRound } from "lucide-react";
import { initializeShieldedSession, ShieldedSession } from "@/lib/strk20-wallet-api";

interface WalletConnectProps {
  onSessionChange?: (session: ShieldedSession | null) => void;
}

export const WalletConnect: React.FC<WalletConnectProps> = ({ onSessionChange }) => {
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [shieldedSession, setShieldedSession] = useState<ShieldedSession | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);

  const handleConnectWallet = async () => {
    setIsConnecting(true);
    try {
      // Connect to Starknet wallet (ArgentX / Braavos)
      if (typeof window !== "undefined" && (window as any).starknet) {
        const starknet = (window as any).starknet;
        const [address] = await starknet.enable();
        setWalletAddress(address);

        // Derive/Request STRK20 Shielded Session
        const session = await initializeShieldedSession();
        setShieldedSession(session);
        onSessionChange?.(session);
      } else {
        alert("Please install ArgentX or Braavos wallet with STRK20 support.");
      }
    } catch (error) {
      console.error("Wallet connection error:", error);
    } finally {
      setIsConnecting(false);
    }
  };

  const handleDisconnect = () => {
    setWalletAddress(null);
    setShieldedSession(null);
    onSessionChange?.(null);
  };

  return (
    <div className="flex items-center gap-3">
      {walletAddress ? (
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 px-3 py-1.5 paper-card rounded-md text-xs font-mono text-ink">
            <span className="w-2 h-2 rounded-full bg-emerald-600 animate-pulse" />
            <span>
              {walletAddress.slice(0, 6)}...{walletAddress.slice(-4)}
            </span>
          </div>

          <div className="flex items-center gap-1.5 px-3 py-1.5 bg-paper-200 border border-paper-300 rounded-md text-xs font-mono text-shield-amber">
            <KeyRound className="w-3.5 h-3.5" />
            <span>Shield Session Active</span>
          </div>

          <button
            onClick={handleDisconnect}
            className="px-2.5 py-1.5 text-xs text-ink-light hover:text-ink hover:underline font-mono"
          >
            Disconnect
          </button>
        </div>
      ) : (
        <button
          onClick={handleConnectWallet}
          disabled={isConnecting}
          className="flex items-center gap-2 px-4 py-2 bg-ink text-paper-50 rounded-md text-sm font-medium hover:bg-stone-800 transition shadow-sm font-sans"
        >
          <Wallet className="w-4 h-4" />
          <span>{isConnecting ? "Connecting..." : "Connect Shielded Wallet"}</span>
        </button>
      )}
    </div>
  );
};
