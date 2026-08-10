import Foundation
import os

final class SessionStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.montty.app",
        category: "session"
    )

    private let fileURL: URL
    private var autoSaveTimer: Timer?

    init(directory: URL? = nil) {
        let dir = directory ?? Self.resolveDirectory()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("session.json")
    }

    /// Tracks what the last load saw, so the first save can protect whatever is
    /// already on disk before overwriting it.
    private enum PriorFile {
        case none
        case readable(version: Int)
        case unreadable
    }

    private var priorFile: PriorFile = .none
    private var didProtectPriorFile = false

    func save(snapshot: SessionSnapshot) {
        protectPriorFileIfNeeded()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save session: \(error)")
        }
    }

    func load() -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            priorFile = .none
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
            priorFile = .readable(version: snapshot.version)
            guard snapshot.version <= SessionSnapshot.currentVersion else {
                Self.logger.error("""
                    Session version \(snapshot.version) is newer than \
                    \(SessionSnapshot.currentVersion); refusing to load
                    """)
                return nil
            }
            return snapshot
        } catch {
            Self.logger.error("Failed to load session: \(error)")
            priorFile = .unreadable
            return nil
        }
    }

    /// Runs once before the first save. An unreadable file is moved aside so the
    /// autosave timer cannot destroy the evidence, and a file written by a
    /// different version is copied aside so a rollback has something to read.
    private func protectPriorFileIfNeeded() {
        guard !didProtectPriorFile else { return }
        didProtectPriorFile = true

        let directory = fileURL.deletingLastPathComponent()
        switch priorFile {
        case .none:
            return
        case .unreadable:
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory
                .appendingPathComponent("session.corrupt-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: quarantine)
                Self.logger.error("Quarantined unreadable session at \(quarantine.path)")
            } catch {
                Self.logger.error("Failed to quarantine unreadable session at \(self.fileURL.path): \(error)")
            }
        case .readable(let version):
            guard version != SessionSnapshot.currentVersion else { return }
            backUpPriorFile(version: version, in: directory)
        }
    }

    /// The copy lands on a staging name first, so a failure cannot leave the
    /// previous backup deleted and the new one half-written.
    private func backUpPriorFile(version: Int, in directory: URL) {
        let backup = directory.appendingPathComponent("session.v\(version).json")
        let staged = directory.appendingPathComponent("session.v\(version).json.staging")
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: fileURL, to: staged)
            if FileManager.default.fileExists(atPath: backup.path) {
                _ = try FileManager.default.replaceItemAt(backup, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: backup)
            }
            Self.logger.info("Backed up v\(version) session to \(backup.path)")
        } catch {
            try? FileManager.default.removeItem(at: staged)
            Self.logger.error("Failed to back up v\(version) session: \(error)")
        }
    }

    func startAutoSave(
        interval: TimeInterval = 8.0,
        snapshotProvider: @escaping () -> SessionSnapshot
    ) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            self?.save(snapshot: snapshotProvider())
        }
    }

    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// Where session state lives. `MONTTY_SESSION_DIR` overrides the default so a
    /// Justfile-launched build cannot overwrite the installed app's session.
    static func resolveDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["MONTTY_SESSION_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("montty")
    }
}
