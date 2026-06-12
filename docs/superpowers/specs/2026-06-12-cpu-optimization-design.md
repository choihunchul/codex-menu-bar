# Spec: CPU and WindowServer Optimization for Codex Menu Bar

Date: 2026-06-12
Author: Antigravity

## Goal

To resolve the high CPU usage of `CodexMenuBar` (nearly 100% CPU) and `WindowServer` (over 50% CPU) by:
1. Optimizing filesystem traversals to targeted paths (avoiding recursive walks).
2. Offloading all disk/DB reads to a background thread with the lowest priority QoS (`.background`).
3. Implementing throttling to limit disk/DB scans to run at most once every 3.0 seconds.
4. Implementing dirty-state check caching to avoid redrawing the menu bar icon and updating the menus when there are no visual changes.

---

## 1. Directory Traversal Optimization (Cursor Logs)

### Problem
In `CursorActivityReader.swift`, `findLatestAgentActivityDate()` scans the session subdirectory inside `~/Library/Application Support/Cursor/logs` using `fileManager.enumerator(at:dir...)` which recursively visits every subfolder and file. This causes severe CPU and disk I/O load every 0.8 seconds.

### Solution
Instead of recursive walk, perform a target-focused shallow scan since the target log files are always at:
`logs/<session_id>/window<num>/exthost/anysphere.cursor-agent-exec/Cursor Agent Exec*`

**Steps**:
1. Retrieve the latest session directories (shallow scan of `logs/`).
2. Shallow scan the target session directory to find subdirectories starting with `window` (e.g. `window1`, `window2`).
3. For each window directory, check if `window/exthost/anysphere.cursor-agent-exec` exists.
4. If it exists, perform a shallow scan of that specific folder and retrieve the modification dates of files starting with `Cursor Agent Exec`.

---

## 2. Background Thread Migration & QoS Throttling

### Problem
Disk reads, file modification queries, and SQLite queries are executed synchronously on the main thread in `CodexMenuBarApp.refresh()` every 0.8 seconds.

### Solution
1. **Cache `readPayload()`**: Only re-read and decode `status.json` if its file modification date actually changes.
2. **QoS `.background` & Throttling (3.0s)**:
   - Run `antigravityActivityReader.readSnapshot()`, `cursorActivityReader.readSnapshot()`, and `limitStateReader.readRuntimeSignalSnapshot()` on a background queue with `.background` Quality of Service.
   - On macOS/Apple Silicon, `.background` QoS runs code strictly on Efficiency Cores (E-cores) with restricted scheduling priority.
   - Restrict these background checks so they are performed **at most once every 3.0 seconds** (even though the main refresh timer runs every 0.8 seconds to keep UI responsive).
   - Use boolean flags (`isRefreshingAntigravity`, `isRefreshingCursorSnapshot`, `isRefreshingRuntimeSignal`) to prevent concurrent queued scans.
3. **Asynchronous Runtime Signal SQLite Query**:
   - Run `limitStateReader.readRuntimeSignalSnapshot()` asynchronously on the `.background` QoS queue.
   - Cache the resulting snapshot on `CodexMenuBarApp`.

---

## 3. Throttled Redraws (WindowServer Optimization)

### Problem
Even when idle, `refresh()` (0.8s) and the animation timer (0.2s) constantly call `updateMenuBarIcon()` and `updateMenu()`, creating a new `NSImage` and resetting it to `statusItem.button.image`. This causes AppKit and WindowServer to continuously repaint the menu bar area.

### Solution
Cache the last drawn state parameters. We will only recreate the `NSImage` and update the status item button if any of the following parameters change:
- `status`
- `isRecentlyCompleted`
- `frameIndex` (only relevant when animating)
- `fiveHourUsagePercent`
- `weeklyUsagePercent`
- `agActive`
- `agStatus`
- `cursorActive`
- `cursorStatus`
- `hasUpdate`

We will similarly throttle `updateMenu()` by comparing cached state values.

---

## Verification Plan

### Manual Verification
1. Run `swift build` and `swift test` to ensure it compiles and passes all existing tests.
2. Run the menu bar app locally.
3. Verify that CPU usage for `CodexMenuBar` stays near 0.0% to 0.5% when idle, and WindowServer CPU usage returns to normal.
4. Verify that menu items and visual status updates (orange/green/purple/teal dots) still react correctly when Cursor/Antigravity/Codex activities are simulated.
