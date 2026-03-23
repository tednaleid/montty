# justfile for montty

# Required zig version (must match ghostty/build.zig.zon minimum_zig_version)
zig_version := "0.15.2"

# Initialize submodules and build GhosttyKit
setup:
    git submodule update --init --recursive
    @command -v zig >/dev/null || { echo "Error: zig not installed. Run: brew install zig"; exit 1; }
    @test "$(zig version)" = "{{zig_version}}" || { echo "Error: zig $(zig version) found, need {{zig_version}}"; exit 1; }
    @xcrun -sdk macosx metal --version >/dev/null 2>&1 || { echo "Error: Metal Toolchain missing. Run: xcodebuild -downloadComponent MetalToolchain"; exit 1; }
    # Build the xcframework. The zig install step may fail on Ghostty's own
    # app build (DockTilePlugin signing) even when the xcframework succeeds,
    # so we check for the framework explicitly.
    -cd ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    @test -d ghostty/macos/GhosttyKit.xcframework || { echo "Error: GhosttyKit.xcframework not found after build"; exit 1; }
    # Ad-hoc sign the libraries so macOS codesign accepts the embedded framework
    find ghostty/macos/GhosttyKit.xcframework -name '*.a' -exec codesign --force --sign - {} \;
    ln -sfn ghostty/macos/GhosttyKit.xcframework GhosttyKit.xcframework
    @echo "Setup complete. Run: just generate && just build"

# Copy Swift bindings from the Ghostty submodule.
# After copying, MONTTY adaptations must be re-applied (see ghostty-binding-adaptation.md).
sync-bindings:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOSTTY=ghostty/macos/Sources/Ghostty
    SURFACE="$GHOSTTY/Surface View"
    HELPERS=ghostty/macos/Sources/Helpers
    FEATURES=ghostty/macos/Sources/Features
    DEST=Sources/Ghostty
    HDEST=Sources/Ghostty/Helpers

    mkdir -p "$DEST" "$HDEST"

    # Core binding files (from ghostty/macos/Sources/Ghostty/)
    for f in \
        GhosttyPackageMeta.swift \
        GhosttyPackage.swift \
        GhosttyDelegate.swift \
        Ghostty.App.swift \
        Ghostty.Surface.swift \
        Ghostty.Config.swift \
        Ghostty.ConfigTypes.swift \
        Ghostty.Input.swift \
        Ghostty.Action.swift \
        Ghostty.Command.swift \
        Ghostty.Error.swift \
        Ghostty.Event.swift \
        Ghostty.Shell.swift \
        NSEvent+Extension.swift; do
        cp "$GHOSTTY/$f" "$DEST/$f"
    done

    # Surface view files (from ghostty/macos/Sources/Ghostty/Surface View/)
    for f in \
        SurfaceView.swift \
        SurfaceView_AppKit.swift \
        SurfaceScrollView.swift \
        SurfaceProgressBar.swift \
        SurfaceGrabHandle.swift; do
        cp "$SURFACE/$f" "$DEST/$f"
    done

    # Helper files (from various locations outside Sources/Ghostty/)
    cp "$HELPERS/CrossKit.swift"                        "$HDEST/"
    cp "$HELPERS/Weak.swift"                            "$HDEST/"
    cp "$HELPERS/Cursor.swift"                          "$HDEST/"
    cp "$HELPERS/KeyboardLayout.swift"                  "$HDEST/"
    cp "$HELPERS/AppInfo.swift"                         "$HDEST/"
    cp "$HELPERS/Extensions/NSPasteboard+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/NSColor+Extension.swift"    "$HDEST/"
    cp "$HELPERS/Extensions/NSMenuItem+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/NSScreen+Extension.swift"   "$HDEST/"
    cp "$HELPERS/Extensions/NSWorkspace+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/UserDefaults+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/OSColor+Extension.swift"    "$HDEST/"
    cp "$HELPERS/Extensions/NSAppearance+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/EventModifiers+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/Optional+Extension.swift" "$HDEST/"
    cp "$HELPERS/Extensions/Array+Extension.swift"    "$HDEST/"
    cp "$HELPERS/Extensions/KeyboardShortcut+Extension.swift" "$HDEST/"
    cp "$HELPERS/Backport.swift"                       "$HDEST/"
    cp "$FEATURES/Secure Input/SecureInput.swift"       "$HDEST/"

    @echo "Copied {{num_cpus()}} binding files. Apply MONTTY adaptations next."

# Generate Xcode project from project.yml
generate:
    xcodegen generate

# Build output lives outside the project tree to avoid iCloud resource forks
# that break codesign.
build_dir := "/tmp/montty-build"

# Build the app
build:
    xcodebuild -project montty.xcodeproj -scheme montty -configuration Debug build SYMROOT={{build_dir}}

# Run unit tests
test:
    xcodebuild -project montty.xcodeproj -scheme montty-unit -destination 'platform=macOS' test SYMROOT={{build_dir}}

# Run SwiftLint
lint:
    swiftlint lint --strict

# Run tests, lint, and build (CI check)
check: test lint build

# Build and launch the app (foreground)
run: build
    {{build_dir}}/Debug/montty.app/Contents/MacOS/montty

# Build and launch the app (background, for scripted testing)
run-bg: build
    @{{build_dir}}/Debug/montty.app/Contents/MacOS/montty &
    @sleep 2
    @echo "montty launched in background. Use 'just stop' to quit."

# Quit the running app gracefully
stop:
    @osascript -e 'tell application "montty" to quit' 2>/dev/null || echo "montty is not running"

# Force-kill the running app (no cleanup)
kill:
    @pkill -f 'montty.app/Contents/MacOS/montty' 2>/dev/null || echo "montty is not running"

# -- Debug server inspection (localhost:9876, debug builds only) --

# List all terminal surfaces
inspect-surfaces:
    @curl -sf localhost:9876/surfaces | jq .

# Send text to the running terminal
inspect-type text surface="":
    @curl -sf -X POST 'localhost:9876/type{{ if surface != "" { "?surface=" + surface } else { "" } }}' -d '{{text}}'

# Send a key event (e.g., return, ctrl+c, tab, escape)
inspect-key key surface="":
    @curl -sf -X POST 'localhost:9876/key{{ if surface != "" { "?surface=" + surface } else { "" } }}' -d '{{key}}'

# Read visible terminal text
inspect-screen surface="":
    @curl -sf 'localhost:9876/screen{{ if surface != "" { "?surface=" + surface } else { "" } }}' | jq .

# Capture terminal screenshot
inspect-screenshot surface="" path=(".llm/inspect/screenshot-" + `date +%Y%m%d-%H%M%S` + ".png"):
    @mkdir -p .llm/inspect && curl -sf 'localhost:9876/screenshot{{ if surface != "" { "?surface=" + surface } else { "" } }}' -o '{{path}}' && echo '{{path}}'

# Get terminal state (title, pwd, size)
inspect-state surface="":
    @curl -sf 'localhost:9876/state{{ if surface != "" { "?surface=" + surface } else { "" } }}' | jq .

# Trigger a Ghostty action (e.g., new_tab, close_tab, "goto_tab:1")
inspect-action action surface="":
    @curl -sf -X POST 'localhost:9876/action{{ if surface != "" { "?surface=" + surface } else { "" } }}' -d '{{action}}' | jq .

# Bump version in Info.plist, commit, tag with release notes, and push
bump version:
    #!/usr/bin/env bash
    set -euo pipefail
    test -n "{{version}}" || { echo "Usage: just bump 0.2.0"; exit 1; }

    # Update version in Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {{version}}" Resources/Info.plist
    git add Resources/Info.plist
    git commit -m "Bump version to {{version}}"

    # Generate release notes from commits since last tag
    prev_tag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
    if [ -n "$prev_tag" ]; then
        commit_log=$(git log "${prev_tag}..HEAD" --oneline --no-merges)
    else
        commit_log=$(git log --oneline --no-merges -20)
    fi

    notes_file=$(mktemp)
    trap 'rm -f "$notes_file"' EXIT

    if command -v claude &>/dev/null; then
        prompt="Generate concise release notes for version {{version}} of montty (a macOS terminal app).
    Here are the commits since ${prev_tag:-the beginning}:

    ${commit_log}

    Guidelines:
    - Group related commits into a single bullet point
    - Focus on user-facing changes, not implementation details
    - Skip version bumps, CI changes, and purely internal refactors
    - Keep each bullet to one line, use past tense
    - Output only a bullet list (- item), nothing else"

        echo "Generating release notes with Claude..."
        if claude -p "$prompt" > "$notes_file" 2>/dev/null; then
            echo "Release notes (generated by Claude):"
        else
            echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
            echo "Release notes (from commit log, Claude failed):"
        fi
    else
        echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
        echo "Release notes (from commit log):"
    fi
    cat "$notes_file"

    git tag -a "{{version}}" -F "$notes_file"
    git push && git push --tags

# Delete a GitHub release and re-tag the current commit to re-trigger release workflow
retag tag:
    gh release delete {{tag}} --yes || true
    git push origin :refs/tags/{{tag}} || true
    git tag -f {{tag}}
    git push && git push --tags

# Remove build artifacts
clean:
    rm -rf {{build_dir}} DerivedData
    xcodebuild -project montty.xcodeproj -scheme montty -configuration Debug clean 2>/dev/null || true
    @echo "Clean complete."
