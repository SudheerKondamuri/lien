import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { WalletConnect } from "@/components/WalletConnect";

export const metadata: Metadata = {
  title: "Lien | Private Lending Protocol on Starknet",
  description:
    "Private, shielded collateralized lending on Starknet mainnet powered by STRK20 pool primitives.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen flex flex-col bg-paper-100 text-ink antialiased">
        {/* Navigation Header */}
        <header className="border-b border-paper-300 bg-paper-50 sticky top-0 z-50">
          <div className="max-w-5xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
            <div className="flex items-center gap-8">
              <Link href="/" className="flex items-center gap-2">
                <span className="font-serif text-2xl font-bold tracking-tight text-ink">
                  Lien
                </span>
                <span className="px-2 py-0.5 text-[10px] font-mono uppercase bg-paper-200 border border-paper-300 rounded text-ink-light">
                  STRK20 Mainnet
                </span>
              </Link>

              <nav className="hidden md:flex items-center gap-6 text-sm font-sans">
                <Link
                  href="/borrow"
                  className="text-ink-light hover:text-ink transition font-medium"
                >
                  Borrow
                </Link>
                <Link
                  href="/position"
                  className="text-ink-light hover:text-ink transition font-medium"
                >
                  My Position
                </Link>
              </nav>
            </div>

            <div className="flex items-center gap-4">
              <WalletConnect />
            </div>
          </div>
        </header>

        {/* Main Content Area */}
        <main className="flex-1 max-w-5xl w-full mx-auto px-4 sm:px-6 py-8">
          {children}
        </main>

        {/* Editorial Footer */}
        <footer className="border-t border-paper-300 bg-paper-50 py-6 text-xs text-ink-light font-mono">
          <div className="max-w-5xl mx-auto px-4 sm:px-6 flex flex-col sm:flex-row items-center justify-between gap-4">
            <div>
              <span>Lien Protocol · STRK20 Private Sprint</span>
            </div>
            <div className="flex items-center gap-6">
              <a
                href="https://starknet.io"
                target="_blank"
                rel="noreferrer"
                className="hover:underline"
              >
                Starknet Mainnet
              </a>
              <span className="text-paper-400">/</span>
              <span>Zero-Knowledge Shielded Credit</span>
            </div>
          </div>
        </footer>
      </body>
    </html>
  );
}
