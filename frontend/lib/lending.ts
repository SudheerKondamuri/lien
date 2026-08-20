import { AccountInterface, Contract, uint256, CallData } from "starknet";
import { mainnetProvider, LIEN_CONTRACT_CONFIG } from "./starknet";

// ABI for the Lien Lending Pool contract
export const LENDING_POOL_ABI = [
  {
    type: "function",
    name: "deposit_collateral",
    inputs: [
      { name: "position_id", type: "core::felt252" },
      { name: "amount", type: "core::integer::u256" },
    ],
    outputs: [],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "borrow",
    inputs: [
      { name: "position_id", type: "core::felt252" },
      { name: "amount", type: "core::integer::u256" },
    ],
    outputs: [],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "repay",
    inputs: [
      { name: "position_id", type: "core::felt252" },
      { name: "amount", type: "core::integer::u256" },
    ],
    outputs: [],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "liquidate",
    inputs: [
      { name: "position_id", type: "core::felt252" },
      { name: "debt_to_cover", type: "core::integer::u256" },
      { name: "liquidator_shielded_recipient", type: "core::felt252" },
    ],
    outputs: [],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "get_position",
    inputs: [{ name: "position_id", type: "core::felt252" }],
    outputs: [
      {
        name: "position",
        type: "lien_contracts::types::Position",
      },
    ],
    state_mutability: "view",
  },
] as const;

export interface PositionData {
  owner: string;
  collateralAmount: bigint;
  borrowedAmount: bigint;
  lastUpdateTimestamp: number;
}

/**
 * Fetch a position by its shielded position ID reference
 */
export async function fetchPosition(
  positionId: string
): Promise<PositionData | null> {
  if (!positionId || positionId === "0x0") return null;

  try {
    const contract = new Contract(
      LENDING_POOL_ABI,
      LIEN_CONTRACT_CONFIG.lendingPoolAddress,
      mainnetProvider
    );

    const result: any = await contract.call("get_position", [positionId]);
    return {
      owner: result.owner.toString(),
      collateralAmount: BigInt(result.collateral_amount.toString()),
      borrowedAmount: BigInt(result.borrowed_amount.toString()),
      lastUpdateTimestamp: Number(result.last_update_timestamp.toString()),
    };
  } catch (error) {
    console.error("Failed to fetch position:", error);
    return null;
  }
}

/**
 * Deposit collateral into a shielded position
 */
export async function executeDepositCollateral(
  account: AccountInterface,
  positionId: string,
  amount: bigint
) {
  const u256Amount = uint256.bnToUint256(amount);
  const call = {
    contractAddress: LIEN_CONTRACT_CONFIG.lendingPoolAddress,
    entrypoint: "deposit_collateral",
    calldata: CallData.compile([positionId, u256Amount.low, u256Amount.high]),
  };

  return await account.execute(call);
}

/**
 * Borrow assets against shielded collateral
 */
export async function executeBorrow(
  account: AccountInterface,
  positionId: string,
  amount: bigint
) {
  const u256Amount = uint256.bnToUint256(amount);
  const call = {
    contractAddress: LIEN_CONTRACT_CONFIG.lendingPoolAddress,
    entrypoint: "borrow",
    calldata: CallData.compile([positionId, u256Amount.low, u256Amount.high]),
  };

  return await account.execute(call);
}

/**
 * Repay debt on a shielded position
 */
export async function executeRepay(
  account: AccountInterface,
  positionId: string,
  amount: bigint
) {
  const u256Amount = uint256.bnToUint256(amount);
  const call = {
    contractAddress: LIEN_CONTRACT_CONFIG.lendingPoolAddress,
    entrypoint: "repay",
    calldata: CallData.compile([positionId, u256Amount.low, u256Amount.high]),
  };

  return await account.execute(call);
}
