# Implementation Spec: Rich Tabs - Phase 1

**Contract**: ./contract.md
**Estimated Effort**: M

## Overview

Introduce the `TabInfo` model and `GitInfo` derivation -- the testable foundation that all subsequent phases build on. `TabInfo` is a pure value type computed from terminal surface metadata. `GitInfo` reads git state from the filesystem given a working directory path.

## Technical Approach

Create a clean data contract: `TabInfo` is a struct computed from inputs (pwd, title, split tree) with no dependency on AppKit or Ghostty. `GitInfo` is derived from filesystem reads (`.git/HEAD`, `git rev-parse`). Both are pure functions, heavily unit-tested.

The tab model (`Tab`) gains a computed `tabInfo` property. The `TabRow` view reads from `TabInfo` instead of directly from `Tab` properties. This decouples the view from the data sources and makes the entire derivation pipeline testable.

## Feedback Strategy

**Inner-loop command**: `just test`
**Playground**: Test suite
**Why this approach**: All changes are pure model/logic. Tests are the tightest feedback loop.

## File Changes

### New Files

| File Path | Purpose |
|-----------|---------|
| `Sources/Model/TabInfo.swift` | `TabInfo` struct -- computed metadata for tab display |
| `Sources/Model/GitInfo.swift` | `GitInfo` struct + derivation from filesystem path |
| `Tests/TabInfoTests.swift` | Red/green tests for TabInfo computation |
| `Tests/GitInfoTests.swift` | Red/green tests for git derivation with fixture dirs |

### Modified Files

| File Path | Changes |
|-----------|---------|
| `Sources/View/TabRow.swift` | Read from `TabInfo` instead of raw `Tab` properties |
| `project.yml` | Ensure test target includes new model files |

## Implementation Details

### TabInfo model

```swift
// Sources/Model/TabInfo.swift
struct TabInfo: Equatable {
    let displayName: String
    let workingDirectory: String?
    let directoryName: String?      // last path component
    let gitInfo: GitInfo?           // nil if not in a git repo
    let claudeCode: ClaudeCodeStatus?  // nil if Claude Code not detected
    let splitCount: Int                 // 1 = no splits
    // Phase 3 adds: minimap: SplitMinimap?

    static func from(
        tab: TabProperties,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> TabInfo
}

/// Claude Code status for a terminal pane.
struct ClaudeCodeStatus: Equatable {
    let sessionName: String
    let state: State

    enum State: Equatable {
        case unknown    // detected Claude Code, can't determine state yet
        case working    // actively processing (future signal)
        case waiting    // needs user input (future signal)
    }
}

/// Minimal subset of Tab properties needed by TabInfo, for testability.
struct TabProperties: Equatable {
    let name: String
    let autoName: String
    let workingDirectory: String?
    let splitRoot: SplitNode
}
```

The `gitInfoProvider` parameter enables testing with mock git info.

### GitInfo derivation

```swift
// Sources/Model/GitInfo.swift
struct GitInfo: Equatable {
    let repoName: String        // basename of repo root
    let branchName: String?     // current branch, nil if detached HEAD
    let worktreeName: String?   // non-nil if in a linked worktree
    let repoPath: String        // absolute path to repo root

    /// Derive git info from a working directory path.
    /// Returns nil if the path is not inside a git repository.
    static func from(path: String) -> GitInfo?
}
```

Implementation uses pure filesystem reads (no shelling out to `git`):

1. Walk up from `path` looking for `.git` (file or directory). The directory containing `.git` is the repo root.
2. If `.git` is a **directory**: this is the main repo. Read `.git/HEAD` for branch (`ref: refs/heads/branch-name` -> `branch-name`, raw SHA -> detached HEAD).
3. If `.git` is a **file**: this is a linked worktree. The file contains `gitdir: /path/to/main-repo/.git/worktrees/worktree-name`. Parse the path to find the main repo root and the worktree name.
4. `repoName` is the basename of the repo root directory.
5. Results are cached by repo root path and invalidated when pwd changes.

This avoids a `Process` dependency, making tests straightforward with fixture directories containing real `.git` structures.

### Claude Code detection (stub)

In Phase 1, `claudeCodeSession` is derived from `autoName` (terminal title) with a simple heuristic: if the title contains "Claude Code", extract the session description. Full implementation in Phase 2.

## Red/Green Tests

### TabInfoTests.swift

Write failing tests FIRST, then implement:

- `tabInfoDisplaysUserName` -- user-set name takes precedence
- `tabInfoFallsBackToAutoName` -- empty name uses autoName
- `tabInfoExtractsDirectoryName` -- "/Users/ted/projects/montty" -> "montty"
- `tabInfoIncludesGitInfo` -- when pwd is in a git repo, gitInfo is non-nil
- `tabInfoNilGitOutsideRepo` -- when pwd is not in a git repo, gitInfo is nil
- `tabInfoSplitCount` -- single leaf = 1, split = 2, nested = 3+

### GitInfoTests.swift

Write failing tests FIRST, then implement. Use temp directories with real `.git` structures:

- `gitInfoFromRepoRoot` -- detects repo name and branch from .git/HEAD
- `gitInfoFromSubdirectory` -- finds repo when pwd is nested inside
- `gitInfoDetachHead` -- branch is nil for detached HEAD
- `gitInfoReturnsNilOutsideRepo` -- /tmp returns nil
- `gitInfoRepoName` -- basename of repo root

## Verification

- `just test` -- all new tests pass (red first, then green)
- `just build` -- compiles cleanly
- `just lint` -- no new warnings
- Tab sidebar still renders correctly (visual check)
