#!/usr/bin/env node
/**
 * Thin npx-style entry: forwards to cargo-run create-zk-coprocessor when available.
 */
const { spawnSync } = require("child_process");
const args = process.argv.slice(2);
const r = spawnSync(
  "cargo",
  ["run", "-q", "-p", "create-zk-coprocessor", "--", ...args],
  { stdio: "inherit", shell: process.platform === "win32" }
);
process.exit(r.status ?? 1);
