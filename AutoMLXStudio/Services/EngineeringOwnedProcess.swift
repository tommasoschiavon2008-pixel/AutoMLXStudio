import Darwin // Supplies atomic process-group creation, descriptor isolation, exact-child waiting, and group signals.
import Foundation // Supplies URLs, pipes, locks, and a background wait queue.

final class EngineeringOwnedProcess: @unchecked Sendable { // Owns a dedicated process group; configuration is frozen before launch and lifecycle state is locked.
    var executableURL: URL? // Receives only the trusted sandbox launcher before run.
    var arguments: [String] = [] // Receives a prevalidated argument vector before run.
    var currentDirectoryURL: URL? // Receives the canonical workspace cwd before run.
    var environment: [String: String] = [:] // Receives only the sanitized command environment before run.
    var standardOutput = Pipe() // Connects command output to the runner's bounded collector.
    var standardError = Pipe() // Connects command diagnostics to the runner's bounded collector.
    var terminationHandler: (@Sendable (EngineeringOwnedProcess) -> Void)? // Receives completion only after group cleanup and leader reaping.
    private let lock = NSLock() // Serializes signals with reaping so a reused PID can never be targeted.
    private var identifier: pid_t = 0 // Retains the exact unreaped leader identity.
    private var running = false // Tracks whether this object still owns its unreaped child.
    private var status: Int32 = 0 // Retains the normalized terminal status after reaping.

    var processIdentifier: Int32 { lock.withLock { identifier } } // Exposes the owned leader identity without a race.
    var isRunning: Bool { lock.withLock { running } } // Exposes lifecycle state without testing a potentially reused host PID.
    var terminationStatus: Int32 { lock.withLock { status } } // Exposes the captured exit code or signal.

    func run() throws { // Creates the process group atomically, before any requested executable instruction runs.
        guard let executableURL, let currentDirectoryURL else { throw EngineeringRuntimeError.processLaunchFailed("Missing contained process configuration.") } // Refuses incomplete launch metadata.
        var actions: posix_spawn_file_actions_t? // Holds descriptor and cwd actions executed in the child before exec.
        var attributes: posix_spawnattr_t? // Holds process-group and descriptor isolation attributes.
        try check(posix_spawn_file_actions_init(&actions)) // Initializes child actions or fails before launch.
        defer { posix_spawn_file_actions_destroy(&actions) } // Releases only the local spawn-action allocation.
        try check(posix_spawnattr_init(&attributes)) // Initializes the child attributes or fails before launch.
        defer { posix_spawnattr_destroy(&attributes) } // Releases only the local spawn-attribute allocation.
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))) // Creates a dedicated group and closes every unspecified inherited descriptor.
        try check(posix_spawnattr_setpgroup(&attributes, 0)) // Gives the child a group whose ID equals its own PID atomically.
        try check(posix_spawn_file_actions_addchdir_np(&actions, currentDirectoryURL.path)) // Sets cwd in the child without changing the multi-threaded app's cwd.
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)) // Prevents interactive input or inherited terminal access.
        try check(posix_spawn_file_actions_adddup2(&actions, standardOutput.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)) // Grants only the output pipe descriptor.
        try check(posix_spawn_file_actions_adddup2(&actions, standardError.fileHandleForWriting.fileDescriptor, STDERR_FILENO)) // Grants only the diagnostics pipe descriptor.
        let argumentStorage = ([executableURL.path] + arguments).map { strdup($0) } // Preserves separate arguments in an owned C vector.
        let environmentStorage = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } // Builds an explicit deterministic environment without host inheritance.
        defer { (argumentStorage + environmentStorage).forEach { free($0) } } // Releases every allocated C string after spawn copies it.
        guard argumentStorage.allSatisfy({ $0 != nil }), environmentStorage.allSatisfy({ $0 != nil }) else { throw EngineeringRuntimeError.processLaunchFailed("Cannot allocate contained process arguments.") } // Refuses a truncated argument or environment vector.
        var argv = argumentStorage + [nil] // Terminates the POSIX argument vector.
        var envp = environmentStorage + [nil] // Terminates the POSIX environment vector.
        var child: pid_t = 0 // Receives only this spawn's leader PID.
        try check(posix_spawn(&child, executableURL.path, &actions, &attributes, &argv, &envp)) // Atomically launches the sandbox wrapper into its isolated process group.
        lock.withLock { identifier = child; running = true } // Publishes ownership before completion observation starts.
        try? standardOutput.fileHandleForWriting.close() // Drops the parent's duplicate output writer so EOF can be observed.
        try? standardError.fileHandleForWriting.close() // Drops the parent's duplicate diagnostics writer so EOF can be observed.
        DispatchQueue.global(qos: .utility).async { self.reapOwnedGroup() } // Waits off the actor/main thread while retaining exact process ownership.
    } // Ends atomic contained launch.

    func terminate() { signalOwnedGroup(SIGTERM) } // Requests graceful shutdown of the leader and all same-group descendants.
    func forceTerminate() { signalOwnedGroup(SIGKILL) } // Escalates only while the unreaped leader still reserves the group identity.

    private func signalOwnedGroup(_ signal: Int32) { // Serializes group signaling with final cleanup and leader reaping.
        lock.withLock { if running, identifier > 1 { Darwin.kill(-identifier, signal) } } // Never signals the application group, a process name, or an already released PID.
    } // Ends exact-group signaling.

    private func reapOwnedGroup() { // Keeps the leader unreaped until any lingering group members have been killed.
        let child = processIdentifier // Captures the immutable owned child identity.
        var information = siginfo_t() // Receives terminal child information without releasing its PID.
        var observed: Int32 // Records the wait operation's result.
        repeat { observed = waitid(P_PID, id_t(child), &information, WEXITED | WNOWAIT) } while observed == -1 && errno == EINTR // Retries interrupted waits without reaping or widening ownership.
        lock.lock() // Excludes timeout/cancellation signals while releasing ownership.
        if observed == 0 { Darwin.kill(-child, SIGKILL) } // Cleans up background/orphan same-group children even when the approved leader exited successfully.
        var rawStatus: Int32 = 0 // Receives the actual leader wait status.
        var reaped: pid_t // Records exact-child reaping rather than consuming unrelated children.
        repeat { reaped = waitpid(child, &rawStatus, 0) } while reaped == -1 && errno == EINTR // Reaps only this exact child after group cleanup.
        status = reaped == child ? ((rawStatus & 0x7f) == 0 ? (rawStatus >> 8) & 0xff : rawStatus & 0x7f) : 127 // Preserves normal exit or signal and reports failed ownership observation as failure.
        running = false // Releases signal authority permanently before another process could reuse the PID.
        lock.unlock() // Ends exclusive cleanup before invoking the runner's completion handler.
        terminationHandler?(self) // Resolves the command only after owned-group cleanup and exact leader reaping.
    } // Ends exact process-group ownership lifecycle.

    private func check(_ code: Int32) throws { // Normalizes POSIX spawn setup errors without falling back to unrestricted execution.
        guard code == 0 else { throw EngineeringRuntimeError.processLaunchFailed("Contained process setup failed (POSIX \(code)).") } // Fails before model-requested code runs when isolation setup fails.
    } // Ends fail-closed spawn validation.
} // Ends isolated process-group ownership.
