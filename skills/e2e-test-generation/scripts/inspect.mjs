#!/usr/bin/env node
// Selector discovery for the e2e-test-generation skill (Phase 3).
//
// Opens one route of an already-running app in a real browser, optionally signed in by seeding
// localStorage before any page script runs, and saves what a test author needs to pick locators:
//   aria.yml     - the accessibility tree (roles + accessible names) of the page
//   page.png     - a full-page screenshot
//   testids.txt  - every data-testid on the page (empty if the app has none)
//
// Generic: every project-specific value (URL, auth key/value, init script) comes from arguments.
// See PROJECT.md for this project's values.
//
// Usage:
//   node scripts/inspect.mjs --url <base-url> --route <path> --out <dir>
//        [--storage-key <key> --storage-value <json-string>] [--init <js-file>]
//        [--wait-text <text>] [--headed]
//
// Run it from the repo root so `playwright` resolves from the repo's node_modules.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";

const require = createRequire(path.join(process.cwd(), "package.json"));
const { chromium } = require("playwright");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) continue;
    const name = key.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) args[name] = true;
    else {
      args[name] = next;
      i += 1;
    }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
if (!args.url || !args.route || !args.out) {
  console.error("Required: --url <base-url> --route <path> --out <dir>");
  process.exit(2);
}

const browser = await chromium.launch({ headless: !args.headed });
const context = await browser.newContext({ locale: "en-US", timezoneId: "UTC" });
const page = await context.newPage();

if (args["storage-key"] && args["storage-value"]) {
  await page.addInitScript(
    ([key, value]) => window.localStorage.setItem(key, value),
    [args["storage-key"], args["storage-value"]],
  );
}
if (args.init) {
  await page.addInitScript({ content: await readFile(args.init, "utf8") });
}

const target = new URL(args.route, args.url).toString();
await page.goto(target);
if (args["wait-text"]) {
  await page.getByText(args["wait-text"]).first().waitFor({ state: "visible", timeout: 15_000 });
} else {
  await page.locator("h1").first().waitFor({ state: "visible", timeout: 15_000 });
}

await mkdir(args.out, { recursive: true });
const aria = await page.locator("body").ariaSnapshot();
const testIds = await page
  .locator("[data-testid]")
  .evaluateAll((els) => els.map((el) => `${el.getAttribute("data-testid")}\t<${el.tagName.toLowerCase()}>`));
await writeFile(path.join(args.out, "aria.yml"), aria + "\n");
await writeFile(path.join(args.out, "testids.txt"), testIds.join("\n") + (testIds.length ? "\n" : ""));
await page.screenshot({ path: path.join(args.out, "page.png"), fullPage: true });

console.log(`Inspected ${page.url()}`);
console.log(`  aria.yml     ${aria.split("\n").length} lines`);
console.log(`  testids.txt  ${testIds.length} data-testid(s)`);
console.log(`  page.png     full-page screenshot`);
console.log(`Saved to ${args.out}`);

await browser.close();
