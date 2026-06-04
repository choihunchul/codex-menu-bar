#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDir, "..");
const binaryPath = path.join(projectRoot, ".build", "release", "CodexMenuBar");
const statusFile = process.env.CODEX_MENU_BAR_STATUS_FILE
  ? expandHome(process.env.CODEX_MENU_BAR_STATUS_FILE)
  : path.join(os.homedir(), ".codex-menu-bar", "status.json");

await ensureBinary();
await ensureStatusFile();
await openMenuBarApp();
await verifySnapshot();

console.log(JSON.stringify({
  ok: true,
  app: binaryPath,
  statusFile,
}, null, 2));

async function ensureBinary() {
  if (await fileExists(binaryPath)) {
    return;
  }
  run("swift", ["build", "-c", "release"], { cwd: projectRoot });
}

async function ensureStatusFile() {
  await fs.mkdir(path.dirname(statusFile), { recursive: true });
  if (await fileExists(statusFile)) {
    return;
  }
  await fs.writeFile(statusFile, `${JSON.stringify({
    status: "idle",
    detail: "Ready",
    updatedAt: new Date().toISOString(),
  }, null, 2)}\n`);
}

async function openMenuBarApp() {
  if (process.platform === "darwin") {
    run("open", ["-g", binaryPath], { cwd: projectRoot });
    return;
  }

  const child = spawn(binaryPath, {
    cwd: projectRoot,
    detached: true,
    stdio: "ignore",
  });
  child.unref();
}

async function verifySnapshot() {
  const result = spawnSync(process.execPath, [
    path.join(scriptDir, "codex-status-cli.mjs"),
    "snapshot",
    "--json",
  ], {
    cwd: projectRoot,
    encoding: "utf8",
  });

  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || "snapshot verification failed");
  }

  const snapshot = JSON.parse(result.stdout);
  if (!snapshot || !snapshot.statusFile || snapshot.status === "unknown") {
    throw new Error(`invalid snapshot: ${result.stdout}`);
  }
}

async function fileExists(file) {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    ...options,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  if (result.status !== 0) {
    const rendered = [command, ...args].join(" ");
    throw new Error(`${rendered} failed\n${result.stderr || result.stdout}`);
  }
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}
