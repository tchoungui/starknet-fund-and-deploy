// Shared helpers for the Sepolia demos (starknet.js v7).
import "dotenv/config";
import { Account, CallData, RpcProvider, hash, num, uint256 } from "starknet";

export const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"; // same on Sepolia + mainnet

// OpenZeppelin account (constructor: public_key). Override with ACCOUNT_CLASS_HASH after checking the
// class hash published with the OpenZeppelin Cairo contracts release you want.
export const ACCOUNT_CLASS_HASH =
  process.env.ACCOUNT_CLASS_HASH || "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f";

export const FUND_AMOUNT = BigInt(process.env.FUND_AMOUNT_WEI || "10000000000000000"); // 0.01 STRK

export function env(name) {
  const v = process.env[name];
  if (!v) throw new Error(`missing ${name} in .env (see .env.example)`);
  return v;
}

export function provider() {
  return new RpcProvider({ nodeUrl: env("RPC_URL") });
}

export function funder(p = provider()) {
  return new Account(p, env("FUNDER_ADDRESS"), env("FUNDER_PRIVATE_KEY"));
}

/** Counterfactual address = what DEPLOY_ACCOUNT and deploy_from_zero both produce. */
export function counterfactualAddress(classHash, constructorCalldata, salt) {
  return hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
}

export function strkTransferCall(recipient, amount) {
  return {
    contractAddress: STRK,
    entrypoint: "transfer",
    calldata: CallData.compile({ recipient, amount: uint256.bnToUint256(amount) }),
  };
}

export function strkApproveCall(spender, amount) {
  return {
    contractAddress: STRK,
    entrypoint: "approve",
    calldata: CallData.compile({ spender, amount: uint256.bnToUint256(amount) }),
  };
}

export async function strkBalance(p, address) {
  const res = await p.callContract({ contractAddress: STRK, entrypoint: "balanceOf", calldata: [address] });
  return uint256.uint256ToBN({ low: res[0], high: res[1] });
}

export const fmt = (wei) => `${Number(wei) / 1e18} STRK`;
export const hex = (v) => num.toHex(v);
