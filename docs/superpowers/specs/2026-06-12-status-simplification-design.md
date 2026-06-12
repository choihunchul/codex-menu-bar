# Spec: Codex Status Simplification

This document details the simplification of the Codex Menu Bar status representation. The status indicator is reduced to strictly three states: `running`, `idle`, and `update`. All complex intermediate states (`waiting`, `awaiting approval`, `completed`, `error`, `message`) are removed or normalized to `idle` (or `running` where appropriate) to optimize drawing routines, avoid inaccurate status reporting, and maintain low CPU usage.

---

## 1. Goal & Requirements
- Reduce overall state representation to strictly `running`, `idle`, or `update` (when update version is available).
- Simplify logic branches inside `CodexStatusKind`, `CodexMenuBarIconKind`, and transition hooks to match the reduced cases.
- Eliminate unused drawing mechanisms (such as completed sparkle blinking, waiting indicator blinks) to optimize CPU/WindowServer draw calls.
- De-clutter popover status rendering (which is no longer needed since intermediate alert states are mapped to `idle`).

---

## 2. Technical Proposed Changes

### 2.1. Status Normalization & Kind Enum
#### File: [CodexStatusTransitionHooks.swift](file:///Users/hunchulchoi/projects/workspace/myside/mac/codex-menu-bar/Sources/CodexMenuBar/CodexStatusTransitionHooks.swift)
- Change `CodexStatusKind` enum to only contain:
  ```swift
  enum CodexStatusKind: String {
      case running
      case idle
  }
  ```
- Modify `codexNormalizedStatus(_:)` to only return `"running"` or `"idle"`.
- Modify `codexResolvedRuntimeStatus(from:)` to map runtime snapshots strictly to `.running` or `.idle`.
- Modify `CodexStatusHookName` to:
  ```swift
  enum CodexStatusHookName: String, CaseIterable {
      case onRunning
      case onCompleted
  }
  ```
- Simplify `recordResolvedStatus(_:at:)` to only handle `.running` and `.idle`.

### 2.2. Icon Renderer Simplification
#### File: [CodexMenuBarIconRenderer.swift](file:///Users/hunchulchoi/projects/workspace/myside/mac/codex-menu-bar/Sources/CodexMenuBar/CodexMenuBarIconRenderer.swift)
- Change `CodexMenuBarIconKind` enum to only contain:
  ```swift
  enum CodexMenuBarIconKind {
      case idle
      case running
  }
  ```
- Simplify `codexMenuBarIconKind(status:isRecentlyCompleted:)` to match `CodexStatusKind` cases.
- Force `codexMenuBarTopRightSparkleShouldBlink(status:isRecentlyCompleted:)` to return `false`.
- Simplify the drawing switch in `draw(...)` to only handle `.idle` and `.running`.

### 2.3. Popover stubbing
#### File: [StatusPopoverPresentation.swift](file:///Users/hunchulchoi/projects/workspace/myside/mac/codex-menu-bar/Sources/CodexMenuBar/StatusPopoverPresentation.swift)
- Simplify `statusPopoverPresentation(status:detail:)` to always return `nil` since popovers are no longer shown for simplified states.

### 2.4. Main App Status Routing
#### File: [main.swift](file:///Users/hunchulchoi/projects/workspace/myside/mac/codex-menu-bar/Sources/CodexMenuBar/main.swift)
- Simplify `canonicalStatusText(for:)` and `defaultDetail(for:)` to handle only `.running` and `.idle`.
- Simplify `shouldAnimateMenuBarIcon()` to only animate for `.running`.
- Normalize Antigravity status representation inside `updateMenu()` to only report `Running` or `Idle`.

---

## 3. Verification Plan
- Run existing and modified unit tests using `swift test`.
- Manually run `swift build` to ensure successful compilation.
