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

    func save(snapshot: SessionSnapshot) {
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
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            Self.logger.error("Failed to load session: \(error)")
            return nil
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
