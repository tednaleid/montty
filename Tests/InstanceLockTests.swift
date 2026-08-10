// ABOUTME: Verifies the startup lock lets exactly one process claim a socket,
// ABOUTME: and reports a lock it cannot use as unavailable rather than as taken.

import Foundation
import Testing

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
