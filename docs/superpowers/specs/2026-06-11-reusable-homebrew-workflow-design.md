# Reusable Homebrew Workflow Integration Design

This design specifies replacing the inline Homebrew Cask publishing workflow in the `choihunchul/codex-menu-bar` repository with a reusable workflow hosted in the `choihunchul/github--actions` repository.

## Requirements & Scope

1. **Tap**: `choihunchul/homebrew-tap` (under the `Casks/codex-menu-bar.rb` formula).
2. **Access Secret**: `HOMEBREW_TAP_TOKEN` (provided by the caller repository).
3. **Usage**: `brew install --cask choihunchul/tap/codex-menu-bar`.
4. **Trigger Actions**:
   - `workflow_run` (triggered by the completion of the "Build and Release" workflow).
   - `workflow_dispatch` (triggered manually, accepting a `tag` input).
5. **Tag Handling for `workflow_run`**:
   - Because `GITHUB_REF` in a `workflow_run` context is not the release tag, the workflow will use the GitHub Releases API to fetch the latest tag name.
   - Set `verify-tag: false` as an input to the reusable workflow.

## Component Design

### 1. Reusable Workflow (`choihunchul/github--actions`)
**Path**: `.github/workflows/publish-homebrew-cask.yml`

This workflow accepts inputs and secrets from any caller repository and performs the tap checkout, hash calculation, formula generation, and commit/push.

#### Inputs
- `repository`: Source repository (e.g., `choihunchul/codex-menu-bar`).
- `cask`: Name of the cask (e.g., `codex-menu-bar`).
- `asset`: Name of the asset (e.g., `CodexMenuBar.dmg`).
- `app`: App bundle name (e.g., `CodexMenuBar.app`).
- `tag`: The git tag (e.g., `v1.0.8`).
- `verify-tag`: Boolean flag.
- `tap`: Tap repository (defaults to `choihunchul/homebrew-tap`).

#### Secrets
- `token`: GitHub Personal Access Token (PAT) with repository push privileges to the tap.

### 2. Caller Workflow (`choihunchul/codex-menu-bar`)
**Path**: `.github/workflows/publish-homebrew-cask.yml`

This workflow calls the reusable workflow. It contains a two-job hierarchy:
1. **`resolve-tag`**: Outputs the target tag name. Resolves dynamically via GitHub API if triggered by `workflow_run`.
2. **`publish`**: Binds the tag and passes inputs/secrets.

---

## Verification & Testing Plan

### 1. Version Bump (`v1.0.8`)
- Update version references in the codebase (`main.swift` fallback).
- Commit and create git tag `v1.0.8`.

### 2. Local Builds
- Run `swift build` and `swift test` locally to ensure there are no compile or execution issues with the version bump.

### 3. Remote Execution
- Push the commit and the tag `v1.0.8` to GitHub.
- Observe the "Build and Release" run, followed by the "Publish Homebrew Cask" run triggering via `workflow_run`.
- Verify the cask file `Casks/codex-menu-bar.rb` updates correctly with the new version and calculated SHA-256 in `choihunchul/homebrew-tap`.
