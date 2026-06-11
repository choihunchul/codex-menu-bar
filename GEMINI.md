# Codex Menu Bar Project Rules

This document outlines the development, testing, and release guidelines for the `codex-menu-bar` project.

## Development & Testing Rules

1. **Build Verification**:
   Ensure the Swift binary builds cleanly before committing:
   ```bash
   swift build
   ```
2. **Unit Tests**:
   Always run the unit tests and ensure they all pass before pushing changes:
   ```bash
   swift test
   ```
3. **CPU Optimization**:
   Ensure status checks (e.g. Cursor log scanning, SQLite queries) run efficiently and use query caching where possible to maintain low CPU footprint.

---

## Release & Cask Deployment Workflow

Follow these steps when release version updates are made:

1. **Version Bump**:
   Update the fallback version string in `Sources/CodexMenuBar/main.swift` (inside the `currentVersion` variable, changing e.g. `"1.0.7"` to `"1.0.8"`).

2. **Commit & Push**:
   Commit your changes and push them to the `main` branch:
   ```bash
   git commit -am "ci: release bump to v1.0.8"
   git push origin main
   ```

3. **Tag Push**:
   Create a new release tag `v*` and push it:
   ```bash
   git tag v1.0.8
   git push origin v1.0.8
   ```

4. **GitHub Workflows**:
   - Pushing the version tag automatically triggers the **Build and Release** workflow, which compiles the app, generates the `.dmg` asset, and publishes the GitHub Release.
   - Once completed, the **Publish Homebrew Cask** workflow is triggered automatically via `workflow_run` (or can be triggered manually via `workflow_dispatch`). This workflow resolves the latest tag, downloads the release asset, calculates the SHA-256 hash, and calls the reusable workflow in `choihunchul/github--actions` to update the Cask in `choihunchul/homebrew-tap`.
