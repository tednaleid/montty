// ABOUTME: Builds and restores SessionSnapshot state -- tab layout, per-surface
// ABOUTME: working directories, and color overrides survive a relaunch.

import AppKit
import Foundation

extension AppDelegate {
    /// Calls into the use case's builder, supplying the two values only this
    /// layer can: a window's real on-screen frame, and a surface's live
    /// working directory.
    func createSnapshot() -> SessionSnapshot {
        var frames: [UUID: WindowFrame] = [:]
        for window in registry.windows {
            if let live = controllers[window.id]?.window.frame {
                frames[window.id] = WindowFrame(live)
            }
        }
        // A surface's tracked directory is set the moment it is created and
        // kept current by its pwd observer, so it is correct even before the
        // pty has reported anything of its own -- a save that ran that early
        // would otherwise record no directory at all for a brand new surface.
        var directories: [UUID: String] = [:]
        for window in registry.windows {
            for tab in window.tabStore.tabs {
                directories.merge(tab.surfaceDirectories) { _, tracked in tracked }
            }
        }
        for (surfaceID, view) in surfaces {
            if let pwd = view.pwd { directories[surfaceID] = pwd }
        }
        return useCases.snapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            repoColorOverrides: repoColorOverrides,
            frames: frames,
            directories: directories
        )
    }

    /// Rebuilds the registry from a saved session (or opens one fresh window
    /// when there is none) and creates every surface it names. `nil` reaches
    /// the use case as-is -- a cold launch with nothing saved still needs to
    /// tell `restore` that, rather than being coerced into an empty snapshot
    /// that looks the same as a saved-but-empty one.
    func restoreSession(_ snapshot: SessionSnapshot?) {
        apply(useCases.restore(snapshot))

        // Per-surface color overrides are saved keyed by leaf id, because
        // Ghostty mints a fresh surface id on every restore. `apply` above
        // binds each leaf to that fresh id, so the override map is re-keyed
        // here now that the mapping exists. `restore` returns before any
        // surface exists and keeps no reference to the snapshot afterward,
        // so the re-key has to happen here, where the snapshot is still in
        // scope.
        for windowSnap in snapshot?.windows ?? [] {
            guard let window = registry.window(id: windowSnap.windowID) else { continue }
            for tabSnap in windowSnap.tabs where !tabSnap.leafColorOverrides.isEmpty {
                guard let tab = window.tabStore.tabs.first(where: { $0.id == tabSnap.tabID })
                else { continue }
                for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                    if let tint = tabSnap.leafColorOverrides[leaf.id] {
                        tab.surfaceColorOverrides[leaf.surfaceID] = tint
                    }
                }
            }
        }

        // `apply` above already triggered a save once surfaces were bound,
        // which ran before the color re-key loop above and before any
        // surface had a pwd of its own -- that save is missing colors this
        // layer only just re-keyed. Directories are covered by
        // `createSnapshot`'s fallback to the tracked directory, but colors
        // are not tracked anywhere but `surfaceColorOverrides`, so saving
        // again now is the only way to get them onto disk before the next
        // scheduled autosave.
        saveSession()

        // Frames and focus settle after SwiftUI lays the hierarchy out. Each
        // surface calls becomeFirstResponder when it joins a window, so focus
        // needs the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let visible = NSScreen.screens.map(\.visibleFrame)
            for window in self.registry.windows where !window.frame.isEmpty {
                self.controllers[window.id]?.window.setFrame(
                    window.frame.clamped(toVisible: visible).rect, display: true
                )
            }
            self.syncSurfaceFocus()
            self.focusActiveSurface()
        }
    }
}
