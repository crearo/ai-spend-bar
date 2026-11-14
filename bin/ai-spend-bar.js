#!/usr/bin/env node
"use strict";
const { spawnSync } = require("child_process");
const path = require("path");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const cmd = args.find((a) => !a.startsWith("-")) || (args.some((a) => a === "-h" || a === "--help") ? "help" : "setup");

if (cmd === "help") {
  console.log(`Usage: npx ai-spend-bar [command] [--dry-run]

Commands:
  setup      Install or repair AI Spend Bar (default)
  uninstall  Remove the app and turn off start at login
  help       Show this help

--dry-run   Print what would happen without changing anything`);
  process.exit(0);
}
if (cmd !== "setup" && cmd !== "uninstall") {
  console.error(`Unknown command: ${cmd} (try: npx ai-spend-bar help)`);
  process.exit(2);
}

const script = path.join(__dirname, "..", "install.sh");
const flags = [];
if (cmd === "uninstall") flags.push("--uninstall");
if (dryRun) flags.push("--dry-run");
const r = spawnSync("bash", [script, ...flags], { stdio: "inherit" });
process.exit(r.status === null ? 1 : r.status);
