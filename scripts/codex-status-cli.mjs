#!/usr/bin/env node

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const status = process.argv[2] ?? "idle";
const allowed = new Set([
  "running",
  "thinking",
  "running_command",
  "working",
  "idle",
  "waiting",
  "approval_required",
  "awaiting approval",
  "message",
  "error",
  "failed",
  "complete",
  "completed",
  "done",
]);

const statusFile = process.env.CODEX_MENU_BAR_STATUS_FILE
  ? expandHome(process.env.CODEX_MENU_BAR_STATUS_FILE)
  : path.join(os.homedir(), ".codex-menu-bar", "status.json");

if (status === "snapshot") {
  await printSnapshot();
  process.exit(0);
}

const detail = process.argv.slice(3).join(" ");

if (!allowed.has(status)) {
  console.error(`Invalid status: ${status}`);
  console.error("Use one of: running, thinking, running_command, working, idle, waiting, approval_required, awaiting approval, message, error, failed, complete, completed, done, snapshot");
  process.exit(2);
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

async function readPrevious() {
  try {
    return JSON.parse(await fs.readFile(statusFile, "utf8"));
  } catch {
    return {};
  }
}

await fs.mkdir(path.dirname(statusFile), { recursive: true });
const previous = await readPrevious();
const now = new Date().toISOString();
const next = {
  ...previous,
  status,
  detail: detail || defaultDetail(status),
  updatedAt: now,
};

if (isRunningStatus(status) && !next.startedAt) {
  next.startedAt = now;
}
if (!isRunningStatus(status) && !isCompletedStatus(status)) {
  delete next.startedAt;
}

const tmp = `${statusFile}.${process.pid}.tmp`;
await fs.writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`);
await fs.rename(tmp, statusFile);
console.log(`${statusFile}: ${status}`);

async function printSnapshot() {
  let payload = {};
  let exists = false;
  try {
    payload = JSON.parse(await fs.readFile(statusFile, "utf8"));
    exists = true;
  } catch (error) {
    if (error?.code !== "ENOENT") {
      console.error(`Failed to read ${statusFile}: ${error.message}`);
      process.exit(1);
    }
  }

  const snapshot = {
    source: "codex-menu-bar",
    statusFile,
    exists,
    status: payload.status ?? "unknown",
    detail: payload.detail ?? "",
    updatedAt: payload.updatedAt ?? null,
    startedAt: payload.startedAt ?? null,
    tokenUsage: payload.tokenUsage ?? null,
  };

  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(snapshot, null, 2));
  } else {
    console.log(`${snapshot.statusFile}: ${snapshot.status}`);
  }
}

function defaultDetail(value) {
  switch (normalizeStatus(value)) {
    case "running":
      return "Codex is working";
    case "waiting":
      return "Codex is waiting for input";
    case "awaiting approval":
      return "Codex is awaiting approval";
    case "message":
      return "Codex has a message";
    case "error":
      return "Codex needs attention";
    case "completed":
      return "Codex completed";
    default:
      return "Codex is idle";
  }
}

function normalizeStatus(value) {
  const normalized = value.trim().toLowerCase().replace(/-/g, "_");
  if (normalized.includes("approval")) return "awaiting approval";
  if (normalized.includes("complete") || normalized.includes("done")) return "completed";
  if (normalized.includes("thinking") || normalized.includes("running_command") || normalized.includes("running command") || normalized.includes("working") || normalized === "running") return "running";
  if (normalized.includes("waiting")) return "waiting";
  if (normalized.includes("message")) return "message";
  if (normalized.includes("fail") || normalized.includes("error")) return "error";
  if (normalized === "idle") return "idle";
  return normalized.replace(/_/g, " ");
}

function isRunningStatus(value) {
  return normalizeStatus(value) === "running";
}

function isCompletedStatus(value) {
  return normalizeStatus(value) === "completed";
}
