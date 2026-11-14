#!/usr/bin/env node
// "ai-usage-bar" was renamed to "ai-spend-bar". Forward everything to the new package.
const { spawnSync } = require("child_process");
console.log("AI Usage Bar is now AI Spend Bar. Running: npx ai-spend-bar " + process.argv.slice(2).join(" "));
const r = spawnSync("npx", ["--yes", "ai-spend-bar@latest", ...process.argv.slice(2)], { stdio: "inherit" });
process.exit(r.status ?? 1);
