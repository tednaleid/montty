// ABOUTME: An exclusive file lock naming one owner for a control socket, so two
// ABOUTME: montty processes racing to launch cannot both decide the socket is free.

import Foundation

/// The kernel decides who owns a socket, atomically. Asking a socket whether
/// anyone answers and then binding it are two steps, and a second launch that
/// lands between them passes the same check and takes the socket over. `flock`
/// collapses that into one step: of two processes racing for the same path,
/// exactly one gets `.acquired` and the other gets `.takenByAnotherProcess`.
///
/// The lock lives on the open file description, not on the file, so the kernel
/// drops it when the holder dies for any reason, `kill -9` and a crash
/// included. A lock file left on disk is therefore never a stale lock, and
/// nothing has to clean one up.
enum InstanceLock {
    /// Concluding `.takenByAnotherProcess` wrongly refuses to launch montty at
    /// all, so only the one errno that proves another holder produces it.
    /// Every other way locking can fall short is `.unavailable`, which leaves
    /// the caller to launch with whatever weaker guard it has.
    enum Outcome: Equatable {
        /// This process holds the lock, and holds it until it exits.
        case acquired
        /// Another live process holds the lock and owns the socket it names.
        case takenByAnotherProcess
        /// The lock could not be used at all: the path could not be opened, or
        /// the kernel refused for a reason other than another holder.
        case unavailable(code: Int32)
    }

    /// Derives the lock path from the socket it guards, so `MONTTY_SOCKET`
    /// scopes both together and a build with its own socket locks its own
    /// path. Sockets are capped at 103 bytes by `sun_path`; a lock file has no
    /// such limit, and sitting directly beside the socket keeps it predictable.
    static func path(forSocket socketPath: String) -> String {
        socketPath + ".lock"
    }

    /// Takes the lock without blocking and keeps it for the life of the
    /// process. The descriptor is never returned and never closed, because
    /// closing it releases the lock silently and leaves the caller believing it
    /// is still guarded.
    static func acquire(path: String) -> Outcome {
        // O_CLOEXEC keeps the lock out of the shells montty spawns in its
        // panes. A pane that outlived montty would otherwise hold the lock and
        // lock out every later launch.
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return .unavailable(code: errno) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            return code == EWOULDBLOCK ? .takenByAnotherProcess : .unavailable(code: code)
        }

        hold(descriptor)
        return .acquired
    }

    /// Every lock descriptor this process has taken. Nothing removes an entry
    /// and nothing hands one out; the kernel releases them when the process
    /// ends.
    private nonisolated(unsafe) static var heldDescriptors: [Int32] = []
    private static let heldLock = NSLock()

    private static func hold(_ descriptor: Int32) {
        heldLock.lock()
        defer { heldLock.unlock() }
        heldDescriptors.append(descriptor)
    }
}
