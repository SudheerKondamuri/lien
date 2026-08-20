import { RpcProvider, constants, Account, AccountInterface } from "starknet";

// Starknet Mainnet RPC endpoint (fallback to default public node or custom env)
export const STARKNET_MAINNET_RPC =
  process.env.NEXT_PUBLIC_STARKNET_RPC_URL ||
  "https://starknet-mainnet.public.blastapi.io";

export const STARKNET_CHAIN_ID = constants.StarknetChainId.SN_MAIN;

// Standard RPC Provider pointed at Starknet Mainnet
export const mainnetProvider = new RpcProvider({
  nodeUrl: STARKNET_MAINNET_RPC,
});

// Lien Protocol Contract Configuration
export const LIEN_CONTRACT_CONFIG = {
  lendingPoolAddress:
    process.env.NEXT_PUBLIC_LIEN_POOL_ADDRESS ||
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  strk20CollateralPool:
    process.env.NEXT_PUBLIC_STRK20_COLLATERAL_POOL ||
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  strk20BorrowPool:
    process.env.NEXT_PUBLIC_STRK20_BORROW_POOL ||
    "0x0000000000000000000000000000000000000000000000000000000000000000",
};

export interface WalletState {
  isConnected: boolean;
  address: string | null;
  account: AccountInterface | null;
  chainId: string | null;
}
