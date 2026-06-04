---
name: codex-menu-bar
description: Set up, verify, and update the local macOS Codex Menu Bar companion status while Codex is working, idle, waiting for input, reporting a message, or when the user asks about local Codex Menu Bar status.
---

# Codex Menu Bar

Use this skill when the user wants Codex work status reflected in the local menu bar companion app.

## Setup And Verification

Before relying on the menu bar app or reporting its status, verify the local setup from the plugin/project root:

```bash
node scripts/codex-menu-bar-setup.mjs
```

This command must:

- Build `.build/release/CodexMenuBar` if it is missing.
- Start the macOS menu bar app with `open -g`.
- Ensure `~/.codex-menu-bar/status.json` exists.
- Verify the local snapshot command succeeds.

If setup or verification fails, show the error to the user and do not silently continue.

To inspect the current local status, run:

```bash
node scripts/codex-status-cli.mjs snapshot --json
```

Treat this local snapshot as the source of truth for the Codex Menu Bar status file. Do not guess fields that are missing from the snapshot; say they are unavailable from the local snapshot.

## Behavior

- At the start of meaningful work, call the `codex_menu_bar_set_status` MCP tool with `status: "running"` and a short `detail`.
- When work is complete, set `status: "idle"` and summarize the result in `detail`.
- If waiting for user input, set `status: "waiting"`.
- If there is an error or approval/action needed, set `status: "message"` or `status: "error"` with a clear detail.

Keep details short enough to fit in a macOS menu item.

If the MCP tool is unavailable, use the CLI fallback from the plugin/project root:

```bash
node scripts/codex-status-cli.mjs running "Working"
node scripts/codex-status-cli.mjs waiting "Waiting for input"
node scripts/codex-status-cli.mjs message "Action needed"
node scripts/codex-status-cli.mjs error "Needs attention"
node scripts/codex-status-cli.mjs idle "Ready"
```
