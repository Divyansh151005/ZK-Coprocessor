import test from "node:test";
import assert from "node:assert/strict";
import {
  decodePhase0Journal,
  decodeStorageJournal,
  assertSum,
  bountyEstimateEth,
} from "../src/index.ts";

function encodeWord(n: bigint): string {
  return n.toString(16).padStart(64, "0");
}

test("decodePhase0Journal", () => {
  const a = 2n;
  const b = 3n;
  const sum = 5n;
  const hex = "0x" + encodeWord(a) + encodeWord(b) + encodeWord(sum);
  const j = decodePhase0Journal(hex);
  assert.equal(j.a, 2n);
  assert.equal(j.b, 3n);
  assert.equal(j.sum, 5n);
  assertSum(j);
});

test("assertSum rejects tamper", () => {
  const hex = "0x" + encodeWord(2n) + encodeWord(3n) + encodeWord(9n);
  const j = decodePhase0Journal(hex);
  assert.throws(() => assertSum(j));
});

test("decodeStorageJournal", () => {
  const stateRoot = encodeWord(0x11n);
  const account = "0".repeat(24) + "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const slot = encodeWord(0n);
  const value = encodeWord(42n);
  const hex = "0x" + stateRoot + account + slot + value;
  const j = decodeStorageJournal(hex);
  assert.equal(j.account.toLowerCase(), "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
  assert.equal(j.value, ("0x" + value) as `0x${string}`);
});

test("bountyEstimateEth", () => {
  assert.ok(bountyEstimateEth(0.01, 0.01) > 0.02);
});
