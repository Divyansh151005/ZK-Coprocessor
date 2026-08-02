/**
 * Phase 6 TypeScript SDK bindings (journal decode + address book helpers).
 */
export type Network = "anvil" | "sepolia" | "base" | "arbitrum" | "optimism" | "mainnet";

export interface AddressBook {
  network: Network;
  programRegistry: string;
  requestRouter: string;
  fulfillment: string;
  sp1VerifierGateway: string;
}

export interface Phase0Journal {
  a: bigint;
  b: bigint;
  sum: bigint;
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

export function assertSum(j: Phase0Journal): void {
  const expected = (j.a + j.b) & ((1n << 64n) - 1n);
  if (j.sum !== expected) throw new Error("journal sum mismatch");
}

export function bountyEstimateEth(proveCostEth: number, gasEth: number, buffer = 1.2): number {
  return (proveCostEth + gasEth) * buffer;
}
