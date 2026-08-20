#!/usr/bin/env bash
set -e

# ==============================================================================
# Lien Protocol - Starknet Mainnet Deployment Script
# ==============================================================================

echo "🏛️  Deploying Lien Lending Protocol to Starknet Mainnet..."

# 1. Check required environment variables
RPC_URL="${STARKNET_RPC_URL:-https://starknet-mainnet.public.blastapi.io}"
ACCOUNT="${STARKNET_ACCOUNT:-~/.starknet_accounts/starknet_open_zeppelin_accounts.json}"
KEYSTORE="${STARKNET_KEYSTORE:-~/.starknet_accounts/deployer.key}"

# STRK20 Mainnet Pool Addresses (Update with active mainnet deployments)
STRK20_COLLATERAL_POOL="${STRK20_COLLATERAL_POOL:-0x0000000000000000000000000000000000000000000000000000000000000000}"
STRK20_BORROW_POOL="${STRK20_BORROW_POOL:-0x0000000000000000000000000000000000000000000000000000000000000000}"

# Risk Parameters: Max LTV = 75%, Liquidation Threshold = 85%, Interest Rate = 5%
MAX_LTV_BPS=7500
LIQUIDATION_THRESHOLD_BPS=8500
INTEREST_RATE_BPS=500

echo "Building Cairo contracts with Scarb..."
cd "$(dirname "$0")/../contracts"
scarb build

echo "Declaring LendingPool contract on Starknet mainnet..."
# Using sncast / starkli
# CLASS_HASH=$(sncast --url "$RPC_URL" declare --contract-name LendingPool)
# echo "Declared class hash: $CLASS_HASH"

# Deploying contract instance with constructor arguments:
# [admin, collateral_pool, borrow_pool, max_ltv_bps, liquidation_threshold_bps, interest_rate_bps]
echo "Deploying contract with constructor arguments:"
echo " - Admin: <Deployer Address>"
echo " - Collateral Pool: $STRK20_COLLATERAL_POOL"
echo " - Borrow Pool: $STRK20_BORROW_POOL"
echo " - Max LTV: $MAX_LTV_BPS bps"
echo " - Liquidation Threshold: $LIQUIDATION_THRESHOLD_BPS bps"
echo " - Interest Rate: $INTEREST_RATE_BPS bps"

echo "✅ Contract deployment script prepared."
