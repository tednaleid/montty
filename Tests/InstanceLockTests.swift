// ABOUTME: Verifies the startup lock lets exactly one process claim a socket,
// ABOUTME: and reports a lock it cannot use as unavailable rather than as taken.

import Foundation
import Testing

/// A separate process holding an exclusive `flock` on a path. A lock belongs to
/// the open file description that took it, so a second lock attempt from within
/// this process would not prove that the lock keeps anyone out. Only a real
/// second process does.
private final class LockHolder {
    private let process = Process()
    private let toChild = Pipe()
    private let fromChild = Pipe()

    /// Returns once the child reports the lock is in hand.
    init(path: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e",
            """
            $| = 1;
            open(my $f, '>', $ARGV[0]) or exit 3;
            flock($f, 6) or exit 4;
            print "locked\\n";
            <STDIN>;
            """,
            path
        ]
        process.standardInput = toChild
        process.standardOutput = fromChild
        try? process.run()
        let ready = fromChild.fileHandleForReading.availableData
        #expect(String(bytes: ready, encoding: .utf8) == "locked\n")
    }

    /// Ends the holder. The kernel drops its lock as the process dies, which is
    /// the only way this lock is ever released.
    func stop() {
        try? toChild.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

/// Asks a separate process whether the lock on `path` is still held. The answer
/// is the only one that counts: a lock is invisible from inside the process
/// that took it.
private func anotherProcessFindsTheLockTaken(_ path: String) -> Bool {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = [
        "-e",
        """
        $| = 1;
        open(my $f, '>', $ARGV[0]) or exit 3;
        print flock($f, 6) ? "free\\n" : "taken\\n";
        """,
        path
    ]
    process.standardOutput = output
    try? process.run()
    let answer = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(bytes: answer, encoding: .utf8) == "taken\n"
}

@Suite struct InstanceLockTests {
    /// Lock paths have no `sun_path` limit, but they sit beside socket paths
    /// that do, so the suite keeps its scratch tree as short as the socket
    /// suites keep theirs.
    private func scratchDirectory() -> URL {
        let directory = URL(fileURLWithPath: "/tmp/mtylock-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    @Test func takesTheLockOnAPathNobodyHolds() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("free.lock").path
        #expect(InstanceLock.acquire(path: path) == .acquired)
    }

    @Test func keepsHoldingTheLockAfterAcquireReturns() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("kept.lock").path

        #expect(anotherProcessFindsTheLockTaken(path) == false)
        #expect(InstanceLock.acquire(path: path) == .acquired)

        #expect(anotherProcessFindsTheLockTaken(path) == true)
    }

    @Test func reportsTakenWhileAnotherProcessHoldsTheLock() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("taken.lock").path

        let holder = LockHolder(path: path)
        defer { holder.stop() }

        #expect(InstanceLock.acquire(path: path) == .takenByAnotherProcess)
    }

    @Test func takesTheLockOnceTheHolderExits() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("handoff.lock").path

        let holder = LockHolder(path: path)
        #expect(InstanceLock.acquire(path: path) == .takenByAnotherProcess)

        holder.stop()

        #expect(InstanceLock.acquire(path: path) == .acquired)
    }

    @Test func reportsUnavailableRatherThanTakenForAPathItCannotOpen() {
        let directory = scratchDirectory()
        let permissions: (Int) -> Void = { mode in
            try? FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: directory.path
            )
        }
        defer {
            permissions(0o700)
            try? FileManager.default.removeItem(at: directory)
        }
        permissions(0o500)

        let outcome = InstanceLock.acquire(
            path: directory.appendingPathComponent("denied.lock").path
        )

        #expect(outcome != .takenByAnotherProcess)
        #expect(outcome == .unavailable(code: EACCES))
    }

    @Test func reportsUnavailableForAPathUnderADirectoryThatIsNotThere() {
        let missing = "/tmp/mtylock-gone-\(UUID().uuidString.prefix(8))/x.lock"

        let outcome = InstanceLock.acquire(path: missing)

        #expect(outcome != .takenByAnotherProcess)
        #expect(outcome == .unavailable(code: ENOENT))
    }

    @Test func scopesTheLockToTheSocketItGuards() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let guarded = directory.appendingPathComponent("a.sock").path
        let separate = directory.appendingPathComponent("b.sock").path

        let holder = LockHolder(path: InstanceLock.path(forSocket: guarded))
        defer { holder.stop() }

        #expect(InstanceLock.acquire(path: InstanceLock.path(forSocket: guarded))
            == .takenByAnotherProcess)
        #expect(InstanceLock.acquire(path: InstanceLock.path(forSocket: separate)) == .acquired)
    }
}
