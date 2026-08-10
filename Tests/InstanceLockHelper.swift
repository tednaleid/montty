// ABOUTME: Spawns the separate processes the lock tests need, bounded by a
// ABOUTME: deadline so a child that never reports back fails rather than hangs.

import Foundation
import Testing

/// The lock tests need a second process, and macOS ships no `flock` command.
/// Perl and Python both expose the syscall, and a machine missing one usually
/// has the other, so the suite takes whichever is installed.
enum LockScript {
    struct Interpreter {
        let path: String
        /// The flag that introduces an inline script: `-e` for perl, `-c` for python.
        let flag: String
        /// Takes the lock, says so, and holds it until stdin closes.
        let hold: String
        /// Reports whether the lock is free, then exits.
        let probe: String
    }

    private static let candidates = [
        Interpreter(
            path: "/usr/bin/perl",
            flag: "-e",
            hold: """
                $| = 1;
                open(my $f, '>', $ARGV[0]) or exit 3;
                flock($f, 6) or exit 4;
                print "locked\\n";
                <STDIN>;
                """,
            probe: """
                $| = 1;
                open(my $f, '>', $ARGV[0]) or exit 3;
                print flock($f, 6) ? "free\\n" : "taken\\n";
                """
        ),
        Interpreter(
            path: "/usr/bin/python3",
            flag: "-c",
            hold: """
                import fcntl, sys
                handle = open(sys.argv[1], 'w')
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except OSError:
                    sys.exit(4)
                sys.stdout.write('locked\\n')
                sys.stdout.flush()
                sys.stdin.readline()
                """,
            probe: """
                import fcntl, sys
                handle = open(sys.argv[1], 'w')
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    print('free')
                except OSError:
                    print('taken')
                """
        )
    ]

    /// The first installed interpreter. Nil leaves the caller to fail with a
    /// message naming what it looked for, which beats a test that quietly
    /// proves nothing.
    static let available: Interpreter? = candidates.first {
        FileManager.default.isExecutableFile(atPath: $0.path)
    }

    static var missingMessage: String {
        "no interpreter for the lock helper: looked for "
            + candidates.map(\.path).joined(separator: ", ")
    }
}

/// Reads until `handle` yields a newline, the child closes the pipe, or the
/// deadline passes. The deadline is the point: a child that dies before it
/// reports leaves nobody to write, and a blocking read would wait forever.
private func readLine(from handle: FileHandle, within seconds: TimeInterval) -> String {
    let descriptor = handle.fileDescriptor
    _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL, 0) | O_NONBLOCK)

    let deadline = Date().addingTimeInterval(seconds)
    var text = ""
    while Date() < deadline {
        var buffer = [UInt8](repeating: 0, count: 128)
        let count = read(descriptor, &buffer, buffer.count)
        if count > 0 {
            text += String(bytes: buffer[0..<count], encoding: .utf8) ?? ""
            if text.contains("\n") { return text }
        } else if count == 0 {
            return text
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
            return text
        }
        usleep(20_000)
    }
    return text
}

/// A separate process holding an exclusive `flock` on a path. A lock belongs to
/// the open file description that took it, so a second lock attempt from within
/// this process would not prove that the lock keeps anyone out. Only a real
/// second process does.
final class LockHolder {
    private let process = Process()
    private let toChild = Pipe()
    private let fromChild = Pipe()

    /// Returns once the child reports the lock is in hand.
    init(path: String) {
        guard let interpreter = LockScript.available else {
            Issue.record(Comment(rawValue: LockScript.missingMessage))
            return
        }
        process.executableURL = URL(fileURLWithPath: interpreter.path)
        process.arguments = [interpreter.flag, interpreter.hold, path]
        process.standardInput = toChild
        process.standardOutput = fromChild
        do {
            try process.run()
        } catch {
            Issue.record(Comment(rawValue: "could not start the lock holder: \(error)"))
            return
        }
        // The child owns the writing end now. Holding a copy here would keep the
        // pipe from ever reaching end of file, so a child that died before
        // printing would leave the read below with nothing to wait for.
        try? fromChild.fileHandleForWriting.close()

        let greeting = readLine(from: fromChild.fileHandleForReading, within: 10)
        #expect(greeting == "locked\n", "lock holder never reported holding \(path)")
    }

    /// Ends the holder. The kernel drops its lock as the process dies, which is
    /// the only way this lock is ever released.
    func stop() {
        guard process.isRunning else { return }
        try? toChild.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

/// Asks a separate process whether the lock on `path` is still held. The answer
/// is the only one that counts: a lock is invisible from inside the process
/// that took it.
func anotherProcessFindsTheLockTaken(_ path: String) -> Bool {
    guard let interpreter = LockScript.available else {
        Issue.record(Comment(rawValue: LockScript.missingMessage))
        return false
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: interpreter.path)
    process.arguments = [interpreter.flag, interpreter.probe, path]
    process.standardOutput = output
    do {
        try process.run()
    } catch {
        Issue.record(Comment(rawValue: "could not start the lock probe: \(error)"))
        return false
    }
    try? output.fileHandleForWriting.close()

    let answer = readLine(from: output.fileHandleForReading, within: 10)
    process.waitUntilExit()
    return answer == "taken\n"
}
