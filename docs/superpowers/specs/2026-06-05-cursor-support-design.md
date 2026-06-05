# Cursor Support Design Specification

This document outlines the design and implementation details for adding Cursor IDE focus and AI Agent activity detection, along with real-time usage (token / cost) tracking to the Codex Menu Bar.

## Goal Description

Add Cursor editor support to Codex Menu Bar companion app so that:
1. When the Cursor editor is active (focused), any attention state (errors, approval requests) of the menu bar is automatically acknowledged.
2. The app detects active typing or AI Agent (Composer / Agent mode) execution in Cursor, switching the menu bar icon to the running (animated) state.
3. The app fetches real-time token/request usage and quota limits from Cursor's internal dashboard API, displaying it under a dedicated Cursor section in the dropdown menu.

## User Review Required

> [!IMPORTANT]
> **Cursor Token Usage Security**
> Cursor does not offer a public usage API. We retrieve the authorization token (`cursorAuth/accessToken`) directly from Cursor's local global storage database (`state.vscdb`) and construct the session cookie `WorkosCursorSessionToken` to request `https://cursor.com/api/dashboard/get-current-period-usage`.
> - **Security Measure**: The token is never printed to stdout, logged to any file, or saved to Settings. It remains in-memory only and is sent exclusively to `cursor.com` via HTTPS.

## Proposed Changes

The changes will introduce new activity and quota readers and integrate them into the existing menu bar application loop.

### 1. New Component: `CursorActivityReader.swift`
- Checks whether Cursor is running by looking up the bundle identifier `com.todesktop.230313mzl4w4u92`.
- Tracks **User Activity** by checking the modification date of `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb-wal`.
- Tracks **Agent Activity** by scanning the folder `~/Library/Application Support/Cursor/logs/` recursively for log files containing `anysphere.cursor-agent-exec` and checking their modification dates.

### 2. New Component: `CursorLimitReader.swift`
- Accesses `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` using SQLite.
- Extracts `cursorAuth/accessToken` from `ItemTable`.
- Decodes the JWT's payload to extract the `"sub"` claim representing the user ID.
- Combines them as `userId::accessToken` to set the `WorkosCursorSessionToken` cookie.
- Calls `POST https://cursor.com/api/dashboard/get-current-period-usage` to get monthly quota spend and usage percentages.
- Optionally calls `GET https://cursor.com/api/usage` to get model-specific token counts and sums them.

### 3. Modifications to `AppSettings` and Settings UI in `main.swift`
- Add `cursorWatchEnabled: Bool` (defaults to `true`).
- Add `"Auto watch Cursor activity"` checkbox in the settings window.
- Reposition settings window elements to fit the new checkbox.

### 4. Modifications to Status Resolution and Menu Rendering in `main.swift`
- Update `codexMenuBarIsCodexApplication` to return `true` if the app bundle/name contains "cursor".
- Incorporate Cursor activity state (`CursorActivityReader`) into the icon animation trigger.
- Incorporate Cursor usage/limits state (`CursorLimitReader`) into `updateMenu()` under a dedicated Cursor menu item section.
- Implement **Smart Refresh**:
  - Only call the Cursor API if Cursor is running and active (activity detected in last 5 minutes).
  - Limit the API refresh frequency to once every 5 minutes (300 seconds), plus immediate updates on agent completion or on-demand when the menu is opened.

## Verification Plan

### Automated Verification
- Verify that SQLite reads from `state.vscdb` succeed and extract the JWT without issues.
- Verify JWT decoding is correct.
- Verify that HTTPS requests to Cursor dashboard API return valid JSON.

### Manual Verification
- Launch Cursor, write code, and verify that the menu bar app registers user activity.
- Start a Composer task in Cursor and verify that the menu bar shows the animated running state.
- Check the menu bar dropdown to verify the Cursor quota and spend match the official Cursor dashboard.
