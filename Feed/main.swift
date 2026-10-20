// gondar-feed: Claude Code's status line command, wrapped.
//
//     gondar-feed <the existing status line command…>
//
// Reads Claude Code's JSON from stdin, merges only its rate limits and the time into
// ~/Library/Application Support/Gondar/statusline.json, then runs the wrapped command with the same
// stdin, its stdout and stderr inherited, and exits with its status. Saving never fails the command.
import Darwin
import Foundation
import GondarCore

/// The child, once spawned, so the termination signals Claude Code may send reach it too.
nonisolated(unsafe) var child: pid_t = 0

/// Merges the input's limits into the feed file (see `StatusLineFeed.mergeStored`) and writes it atomically,
/// mode 0600, in a 0700 folder. Any failure is ignored.
func save(_ input: Data) {
    let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    let folder = home + "/Library/Application Support/Gondar"
    let path = folder + "/statusline.json"
    mkdir(home + "/Library", 0o700)
    mkdir(home + "/Library/Application Support", 0o755)
    mkdir(folder, 0o700)
    removeStaleTempFiles(in: folder)

    // Sessions run this at once; the lock makes each read-merge-write see the one before it.
    // It is released when the descriptor closes, or when the process dies.
    let lock = open(folder + "/statusline.lock", O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
    defer { if lock >= 0 { close(lock) } }
    if lock >= 0 { flock(lock, LOCK_EX) }

    let existing = FileManager.default.contents(atPath: path)
    guard let feed = StatusLineFeed.mergeStored(existing: existing, incoming: input, receivedAt: Date()) else { return }
    // A temp name of its own per process, so a writer that ignores the lock never writes into another's file.
    let temp = folder + "/.statusline.json.\(getpid()).tmp"
    let fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return }
    let written = feed.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    let closed = close(fd)
    guard written == feed.count, closed == 0, rename(temp, path) == 0 else {
        unlink(temp)
        return
    }
}

/// Temp files a killed writer left behind; any older than a minute is no one's.
func removeStaleTempFiles(in folder: String) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
    let cutoff = time(nil) - 60
    for name in names where name.hasPrefix(".statusline.json.") && name.hasSuffix(".tmp") {
        var info = stat()
        let file = folder + "/" + name
        if lstat(file, &info) == 0 && info.st_mtimespec.tv_sec < cutoff { unlink(file) }
    }
}

/// Spawns `arguments` (found on PATH) with `stdin` piped in and stdout and stderr inherited.
/// Returns its exit status, 128 + n when it died by signal n, or 127/126 when it could not be started, as a shell would.
func run(_ arguments: [String], stdin: Data) -> Int32 {
    var pipeEnds: [Int32] = [0, 0]
    guard pipe(&pipeEnds) == 0 else { return fail(arguments[0], errno) }
    let (readEnd, writeEnd) = (pipeEnds[0], pipeEnds[1])
    // Neither end leaks into the child as is; dup2 onto 0 clears close-on-exec for the copy it makes.
    _ = fcntl(readEnd, F_SETFD, FD_CLOEXEC)
    _ = fcntl(writeEnd, F_SETFD, FD_CLOEXEC)

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, readEnd, 0)

    // SIGPIPE is ignored here, so a child that stops reading early cannot kill this process;
    // the child gets the default back, as it would when run directly.
    signal(SIGPIPE, SIG_IGN)
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var defaults = sigset_t()
    sigemptyset(&defaults)
    sigaddset(&defaults, SIGPIPE)
    posix_spawnattr_setsigdefault(&attributes, &defaults)

    // Termination signals are blocked across the spawn, so one that arrives meanwhile reaches the child once it exists;
    // before that, the handler just exits. The child starts with the signal mask this process started with.
    let forwarded = [SIGTERM, SIGINT, SIGHUP]
    for name in forwarded { signal(name, forward) }
    var blocked = sigset_t(), original = sigset_t()
    sigemptyset(&blocked)
    for name in forwarded { sigaddset(&blocked, name) }
    sigprocmask(SIG_BLOCK, &blocked, &original)
    defer { sigprocmask(SIG_SETMASK, &original, nil) }
    posix_spawnattr_setsigmask(&attributes, &original)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    let spawned = posix_spawnp(&pid, arguments[0], &actions, &attributes, argv, environ)
    close(readEnd)
    guard spawned == 0 else {
        close(writeEnd)
        return fail(arguments[0], spawned)
    }
    child = pid
    sigprocmask(SIG_SETMASK, &original, nil)

    // Written before waiting: a child that never reads stdin either exits (EPIPE ends the write) or is
    // still running, so this cannot deadlock. The pipe closes afterwards, giving the child its EOF.
    stdin.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let n = write(writeEnd, buffer.baseAddress! + offset, buffer.count - offset)
            if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { break }
        }
    }
    close(writeEnd)

    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 {
        guard errno == EINTR else { return 1 }
    }
    let signalNumber = status & 0x7f
    return signalNumber == 0 ? (status >> 8) & 0xff : 128 + signalNumber
}

func forward(_ signalNumber: Int32) {
    if child > 0 { kill(child, signalNumber) } else { _exit(128 + signalNumber) }
}

func fail(_ command: String, _ code: Int32) -> Int32 {
    let reason = code == ENOENT ? "command not found" : String(cString: strerror(code))
    FileHandle.standardError.write(Data("gondar-feed: \(command): \(reason)\n".utf8))
    return code == ENOENT ? 127 : 126
}

// A closed stdin reads as empty rather than crashing, so the wrapped command still runs.
let input = (try? FileHandle.standardInput.readToEnd()) ?? Data()
save(input)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty { exit(0) }
exit(run(arguments, stdin: input))
