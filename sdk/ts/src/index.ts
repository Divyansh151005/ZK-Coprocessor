/**
 * TypeScript SDK — journal decode + request helpers (End_Goal A).
 */
export type Network = "anvil" | "sepolia" | "base" | "arbitrum" | "optimism" | "mainnet";

export interface AddressBook {
  network: Network;
  programRegistry?: string | null;
  requestRouter: string;
  fulfillment: string;
  sp1VerifierGateway?: string;
  MockSP1Verifier?: string;
  MinimalRequestRouter?: string;
  MinimalFulfillment?: string;
  MockConsumer?: string;
}

export interface Phase0Journal {
  a: bigint;
  b: bigint;
  sum: bigint;
}

export interface StorageJournal {
  stateRoot: `0x${string}`;
  account: `0x${string}`;
  slot: `0x${string}`;
  value: `0x${string}`;
}

/** Decode abi.encode(uint64,uint64,uint64) journal (Phase 0). */
export function decodePhase0Journal(hex: string): Phase0Journal {
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (h.length !== 192) {
    throw new Error(`expected 96-byte abi encoding, got ${h.length / 2} bytes`);
  }
  const word = (i: number) => BigInt("0x" + h.slice(i * 64, i * 64 + 64));
  return { a: word(0), b: word(1), sum: word(2) };
}

/** Decode StorageProofPublicValues abi.encode(bytes32,address,bytes32,bytes32). */
export function decodeStorageJournal(hex: string): StorageJournal {
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (h.length !== 256) {
    throw new Error(`expected 128-byte storage journal, got ${h.length / 2} bytes`);
  }
  const word = (i: number) => h.slice(i * 64, i * 64 + 64);
  const stateRoot = ("0x" + word(0)) as `0x${string}`;
  const account = ("0x" + word(1).slice(24)) as `0x${string}`;
  const slot = ("0x" + word(2)) as `0x${string}`;
  const value = ("0x" + word(3)) as `0x${string}`;
  return { stateRoot, account, slot, value };
}

export function assertSum(j: Phase0Journal): void {
  const expected = (j.a + j.b) & ((1n << 64n) - 1n);
  if (j.sum !== expected) throw new Error("journal sum mismatch");
}

export function bountyEstimateEth(proveCostEth: number, gasEth: number, buffer = 1.2): number {
  return (proveCostEth + gasEth) * buffer;
}

/** Minimal ABI fragment for MinimalRequestRouter.request */
export const REQUEST_ABI = [
  "function request(bytes32 programVKey,uint64 a,uint64 b,address callback) payable returns (uint256)",
] as const;
