import test from "node:test";
import assert from "node:assert/strict";
import { decodePhase0Journal, assertSum, bountyEstimateEth } from "../src/index.ts";

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

test("bountyEstimateEth", () => {
  assert.ok(bountyEstimateEth(0.01, 0.01) > 0.02);
});
