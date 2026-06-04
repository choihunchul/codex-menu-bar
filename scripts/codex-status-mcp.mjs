#!/usr/bin/env node

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const statusFile = process.env.CODEX_MENU_BAR_STATUS_FILE
  ? expandHome(process.env.CODEX_MENU_BAR_STATUS_FILE)
  : path.join(os.homedir(), ".codex-menu-bar", "status.json");

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

async function readStatus() {
  try {
    return JSON.parse(await fs.readFile(statusFile, "utf8"));
  } catch {
    return {};
  }
}

async function writeStatus(update) {
  await fs.mkdir(path.dirname(statusFile), { recursive: true });
  const previous = await readStatus();
  const now = new Date().toISOString();
  const next = {
    ...previous,
    ...update,
    updatedAt: now,
  };

  if (isRunningStatus(next.status) && !next.startedAt) {
    next.startedAt = now;
  }
  if (next.status && !isRunningStatus(next.status) && !isCompletedStatus(next.status)) {
    delete next.startedAt;
  }

  const tmp = `${statusFile}.${process.pid}.tmp`;
  await fs.writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`);
  await fs.rename(tmp, statusFile);
  return next;
}

const tools = [
  {
    name: "codex_menu_bar_set_status",
    description: "Set the local Codex menu bar status.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: [
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
          ],
        },
        detail: { type: "string" },
        thread: { type: "string" },
        progress: { type: "number", minimum: 0, maximum: 1 },
        tokenUsage: {
          type: "object",
          properties: {
            inputTokens: { type: "number" },
            outputTokens: { type: "number" },
            totalTokens: { type: "number" },
          },
          additionalProperties: true,
        },
      },
      required: ["status"],
      additionalProperties: false,
    },
  },
  {
    name: "codex_menu_bar_get_status",
    description: "Read the local Codex menu bar status.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
];

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function normalizeStatus(value) {
  const normalized = String(value ?? "").trim().toLowerCase().replace(/-/g, "_");
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

function result(id, payload) {
  send({ jsonrpc: "2.0", id, result: payload });
}

function error(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

async function handle(message) {
  const { id, method, params } = message;

  if (method === "initialize") {
    result(id, {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "codex-menu-bar", version: "0.1.0" },
    });
    return;
  }

  if (method === "notifications/initialized") {
    return;
  }

  if (method === "tools/list") {
    result(id, { tools });
    return;
  }

  if (method === "tools/call") {
    const name = params?.name;
    const args = params?.arguments ?? {};

    if (name === "codex_menu_bar_set_status") {
      const next = await writeStatus(args);
      result(id, {
        content: [
          {
            type: "text",
            text: `Codex menu bar status set to ${next.status}.`,
          },
        ],
      });
      return;
    }

    if (name === "codex_menu_bar_get_status") {
      const current = await readStatus();
      result(id, {
        content: [
          {
            type: "text",
            text: JSON.stringify(current, null, 2),
          },
        ],
      });
      return;
    }

    error(id, -32601, `Unknown tool: ${name}`);
    return;
  }

  if (id !== undefined) {
    error(id, -32601, `Unknown method: ${method}`);
  }
}
async function checkAntigravityStatus() {
  try {
    const home = os.homedir();
    const convsDir = path.join(home, ".gemini", "antigravity", "conversations");
    const brainDir = path.join(home, ".gemini", "antigravity", "brain");

    let files;
    try {
      files = await fs.readdir(convsDir);
    } catch {
      return;
    }

    const pbFiles = files.filter(f => f.endsWith(".pb"));
    if (pbFiles.length === 0) return;

    let latestFile = null;
    let latestMtime = 0;

    for (const file of pbFiles) {
      const filePath = path.join(convsDir, file);
      try {
        const stats = await fs.stat(filePath);
        if (stats.mtimeMs > latestMtime) {
          latestMtime = stats.mtimeMs;
          latestFile = file;
        }
      } catch {}
    }

    if (!latestFile) return;

    const convId = path.basename(latestFile, ".pb");
    const convBrainDir = path.join(brainDir, convId);

    const now = Date.now();
    const isActive = (now - latestMtime) <= 60000;

    let status = "idle";
    let detail = "Ready";

    if (isActive) {
      status = "running";
      detail = "Running tasks...";
    } else {
      const ipMetaPath = path.join(convBrainDir, "implementation_plan.md.metadata.json");
      const taskMetaPath = path.join(convBrainDir, "task.md.metadata.json");
      const wtMetaPath = path.join(convBrainDir, "walkthrough.md.metadata.json");

      let ipMeta = null;
      let taskMeta = null;
      let wtMeta = null;

      try { ipMeta = JSON.parse(await fs.readFile(ipMetaPath, "utf8")); } catch {}
      try { taskMeta = JSON.parse(await fs.readFile(taskMetaPath, "utf8")); } catch {}
      try { wtMeta = JSON.parse(await fs.readFile(wtMetaPath, "utf8")); } catch {}

      if (wtMeta) {
        status = "completed";
        detail = wtMeta.summary || "Task completed successfully";
      } else if (ipMeta && ipMeta.requestFeedback) {
        let isApproved = false;
        if (taskMeta) {
          try {
            const ipStats = await fs.stat(ipMetaPath);
            const taskStats = await fs.stat(taskMetaPath);
            if (taskStats.mtimeMs > ipStats.mtimeMs) {
              isApproved = true;
            }
          } catch {}
        }
        if (!isApproved) {
          status = "awaiting approval";
          detail = ipMeta.summary || "Awaiting your approval on the implementation plan";
        }
      }
    }

    const current = await readStatus();
    const prevAgy = current.antigravity || {};
    if (prevAgy.status !== status || prevAgy.detail !== detail) {
      await writeStatus({
        antigravity: {
          status,
          detail,
          updatedAt: new Date(latestMtime).toISOString()
        }
      });
    }
  } catch (err) {
    // ignore
  }
}

// Start periodic poller for Antigravity status
checkAntigravityStatus();
setInterval(checkAntigravityStatus, 2000);

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      void handle(JSON.parse(line));
    } catch (err) {
      send({
        jsonrpc: "2.0",
        error: {
          code: -32700,
          message: err instanceof Error ? err.message : String(err),
        },
      });
    }
  }
});
