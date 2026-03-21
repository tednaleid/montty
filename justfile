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

# Build and launch the app
run: build
    {{build_dir}}/Debug/montty.app/Contents/MacOS/montty

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

# Remove build artifacts
clean:
    rm -rf {{build_dir}} DerivedData
    xcodebuild -project montty.xcodeproj -scheme montty -configuration Debug clean 2>/dev/null || true
    @echo "Clean complete."
