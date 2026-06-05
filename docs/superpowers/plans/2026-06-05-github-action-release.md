# Codex Menu Bar Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate the packaging and release of Codex Menu Bar as a macOS `.dmg` on GitHub.

**Architecture:** Create a `scripts/package-app.mjs` node script to build the `.app` bundle structure without modifying the host macOS system, and configure a `.github/workflows/release.yml` GitHub Action workflow to build and compile it on a `macos-14` runner, package it into a `.dmg` via `create-dmg`, and upload it to GitHub Releases.

**Tech Stack:** Node.js, Swift, GitHub Actions, `create-dmg` (Homebrew).

---

### Task 1: Create the Packaging Script

**Files:**
- Create: [package-app.mjs](file:///Users/hunchulchoi/projects/workspace/myside/codex-menu-bar/scripts/package-app.mjs)

- [ ] **Step 1: Write `scripts/package-app.mjs`**
  Write the node script to compile the application and package it into `dist/CodexMenuBar.app` bundle:
  ```javascript
  #!/usr/bin/env node
  import { spawnSync } from "node:child_process";
  import fs from "node:fs/promises";
  import path from "node:path";
  import { fileURLToPath } from "node:url";

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const projectRoot = path.resolve(scriptDir, "..");
  const binaryPath = path.join(projectRoot, ".build", "release", "CodexMenuBar");
  const inputSvg = path.join(projectRoot, "assets", "icons", "idle.svg");
  const generatorScript = path.join(projectRoot, "scripts", "make-icns.swift");

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
      throw new Error(`${command} ${args.join(" ")} failed\n${result.stderr || result.stdout}`);
    }
    return result.stdout.trim();
  }

  async function main() {
    const version = process.argv[2] || "1.0.0";
    console.log(`Building version ${version}...`);

    console.log("1. Building CodexMenuBar in release mode...");
    run("swift", ["build", "-c", "release"], { cwd: projectRoot });
    if (!(await fileExists(binaryPath))) {
      throw new Error(`Build finished but binary not found at ${binaryPath}`);
    }

    const distDir = path.join(projectRoot, "dist");
    const appBundlePath = path.join(distDir, "CodexMenuBar.app");
    console.log(`Packaging CodexMenuBar.app bundle to ${appBundlePath}...`);

    // Recreate clean dist directory
    await fs.rm(distDir, { recursive: true, force: true });
    
    const macosDir = path.join(appBundlePath, "Contents", "MacOS");
    const resourcesDir = path.join(appBundlePath, "Contents", "Resources");
    await fs.mkdir(macosDir, { recursive: true });
    await fs.mkdir(resourcesDir, { recursive: true });

    // Copy binary and set executable permission
    await fs.copyFile(binaryPath, path.join(macosDir, "CodexMenuBar"));
    await fs.chmod(path.join(macosDir, "CodexMenuBar"), 0o755);

    // Compile & Copy AppIcon.icns from idle.svg
    if (await fileExists(inputSvg) && await fileExists(generatorScript)) {
      console.log("Generating AppIcon.icns...");
      const tempIcns = path.join(projectRoot, "AppIcon.icns");
      try {
        run("swift", [generatorScript, inputSvg, tempIcns]);
        if (await fileExists(tempIcns)) {
          await fs.rename(tempIcns, path.join(resourcesDir, "AppIcon.icns"));
          console.log("AppIcon.icns successfully packaged.");
        }
      } catch (e) {
        console.error("Failed to generate AppIcon.icns:", e);
        throw e;
      }
    } else {
      console.warn("SVG or icon generator script missing.");
    }

    // Write Info.plist
    const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleExecutable</key>
      <string>CodexMenuBar</string>
      <key>CFBundleIconFile</key>
      <string>AppIcon</string>
      <key>CFBundleIdentifier</key>
      <string>com.codex.menubar</string>
      <key>CFBundleName</key>
      <string>CodexMenuBar</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>${version}</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSMinimumSystemVersion</key>
      <string>13.0</string>
      <key>LSUIElement</key>
      <true/>
  </dict>
  </plist>
  `;
    await fs.writeFile(path.join(appBundlePath, "Contents", "Info.plist"), plistContent);
    console.log("Info.plist generated successfully.");
    console.log("Packaging finished successfully.");
  }

  main().catch((err) => {
    console.error("Packaging failed:", err);
    process.exit(1);
  });
  ```
  And make the file executable: `chmod +x scripts/package-app.mjs`.

- [ ] **Step 2: Run local test of packaging script**
  Run: `node scripts/package-app.mjs 1.0.9`
  Expected: Builds without errors and creates `dist/CodexMenuBar.app` containing the compiled binary, `AppIcon.icns` and `Info.plist` with `1.0.9`.

- [ ] **Step 3: Verify output contents**
  Run: `cat dist/CodexMenuBar.app/Contents/Info.plist`
  Expected: Output contains `<string>1.0.9</string>`.

- [ ] **Step 4: Commit**
  ```bash
  git add scripts/package-app.mjs
  git commit -m "feat: add app bundle packaging script for CI/releases"
  ```

---

### Task 2: Create the GitHub Actions Release Workflow

**Files:**
- Create: [.github/workflows/release.yml](file:///Users/hunchulchoi/projects/workspace/myside/codex-menu-bar/.github/workflows/release.yml)

- [ ] **Step 1: Write workflow config**
  Create the `.github/workflows/release.yml` file with the following contents:
  ```yaml
  name: Build and Release

  on:
    push:
      tags:
        - 'v*'
    workflow_dispatch:

  jobs:
    release:
      runs-on: macos-14
      permissions:
        contents: write
      steps:
        - name: Checkout repository
          uses: actions/checkout@v4

        - name: Set up Node.js
          uses: actions/setup-node@v4
          with:
            node-version: '20'

        - name: Extract version
          id: get_version
          run: |
            TAG_NAME="${{ github.ref_name }}"
            VERSION="${TAG_NAME#v}"
            if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
              VERSION="1.0.0"
            fi
            echo "VERSION=$VERSION" >> $GITHUB_OUTPUT
            echo "TAG_NAME=$TAG_NAME" >> $GITHUB_OUTPUT

        - name: Build App Bundle
          run: node scripts/package-app.mjs "${{ steps.get_version.outputs.VERSION }}"

        - name: Install create-dmg
          run: brew install create-dmg

        - name: Build DMG
          run: |
            mkdir -p dist/release
            create-dmg \
              --volname "Codex Menu Bar" \
              --volicon "dist/CodexMenuBar.app/Contents/Resources/AppIcon.icns" \
              --window-pos 200 120 \
              --window-size 600 400 \
              --icon-size 100 \
              --icon "CodexMenuBar.app" 175 120 \
              --hide-extension "CodexMenuBar.app" \
              --app-drop-link 425 120 \
              "dist/release/CodexMenuBar.dmg" \
              "dist/CodexMenuBar.app"

        - name: Create Release
          uses: softprops/action-gh-release@v2
          with:
            tag_name: ${{ steps.get_version.outputs.TAG_NAME || 'v1.0.0' }}
            name: Release ${{ steps.get_version.outputs.TAG_NAME || 'v1.0.0' }}
            files: dist/release/CodexMenuBar.dmg
            draft: false
            prerelease: false
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

- [ ] **Step 2: Add `dist` directory to `.gitignore`**
  Make sure `dist/` is ignored by git.
  Modify: [.gitignore](file:///Users/hunchulchoi/projects/workspace/myside/codex-menu-bar/.gitignore)
  Add `dist/` to the bottom of the file.

- [ ] **Step 3: Commit files**
  ```bash
  git add .github/workflows/release.yml .gitignore
  git commit -m "feat: add GitHub Actions release workflow for packaging as DMG"
  ```

---

## Verification Plan

### Automated Tests
* None (infrastructure configuration).

### Manual Verification
* Ensure `node scripts/package-app.mjs` runs locally and builds `dist/CodexMenuBar.app`.
* Verify that `dist/` is ignored in `git status`.
