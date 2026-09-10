import Darwin // Supplies exact-PID SIGKILL fallback after a bounded graceful termination window.
import Foundation // Supplies Process, Pipe, filesystem URLs, timing, and concurrency bridges.

struct ManagedPythonCommand: Sendable { // Describes one bounded app-owned Python-environment entrypoint execution.
    let executableURL: URL // Identifies the exact configured virtual-environment executable.
    let arguments: [String] // Stores inspected supported command arguments without shell interpolation.
    let workingDirectoryURL: URL // Stores the app-owned or explicitly configured working directory.
    let environment: [String: String] // Stores explicit environment additions such as offline mode.
    let timeoutMilliseconds: Int // Stores the bounded execution deadline.
} // Ends managed Python command metadata.

struct ManagedPythonResult: Equatable, Sendable { // Reports actual process identity, output, status, and end-to-end timing.
    let processID: Int32 // Stores the exact process identifier owned for this command.
    let terminationStatus: Int32 // Stores the real executable exit status.
    let standardOutput: String // Stores bounded UTF-8 standard output.
    let standardError: String // Stores bounded UTF-8 standard error.
    let durationMilliseconds: Int // Stores measured launch-to-exit wall-clock time.
} // Ends managed Python result metadata.

enum ManagedPythonProcessError: LocalizedError, Equatable, Sendable { // Defines bounded process ownership failures independently from model APIs.
    case busy // Reports a second command submitted to the same serialized runner.
    case executableMissing(String) // Reports an absent or non-executable configured entrypoint.
    case invalidWorkingDirectory(String) // Reports an absent working directory before launch.
    case launchFailed(String) // Reports Foundation process launch failure.
    case timedOut(Int) // Reports the configured execution deadline.
    case cancelled // Reports cooperative task cancellation after exact-process termination.

    var errorDescription: String? { // Produces concise trace-safe process diagnostics.
        switch self { // Selects the message for the concrete ownership failure.
        case .busy: return "Another managed Python command is already running." // Describes serialization refusal.
        case let .executableMissing(path): return "Runtime executable not found: \(path)" // Describes the exact missing entrypoint.
        case let .invalidWorkingDirectory(path): return "Runtime working directory is unavailable: \(path)" // Describes the exact invalid directory.
        case let .launchFailed(detail): return "Runtime process could not start: \(detail)" // Preserves bounded Foundation launch detail.
        case let .timedOut(milliseconds): return "Runtime process exceeded its \(milliseconds) ms timeout and was stopped." // Describes bounded timeout cleanup.
        case .cancelled: return "Runtime process was cancelled and stopped." // Describes cooperative cancellation cleanup.
        } // Ends process-error message selection.
    } // Ends localized process diagnostic access.
} // Ends managed process errors.

actor ManagedPythonProcessRunner { // Serializes one-shot Python work and owns only the exact Process it launches.
    private var activeProcess: Process? // Retains the one process whose lifecycle belongs to this runner.
    private var activeGate: ManagedProcessCompletionGate? // Retains the completion gate used for timeout and cancellation.

    func run(_ command: ManagedPythonCommand) async throws -> ManagedPythonResult { // Launches, captures, bounds, and awaits one inspected executable command.
        guard activeProcess == nil else { throw ManagedPythonProcessError.busy } // Prevents overlapping ownership within this runner.
        guard FileManager.default.isExecutableFile(atPath: command.executableURL.path) else { throw ManagedPythonProcessError.executableMissing(command.executableURL.path) } // Requires the exact entrypoint to be executable.
        var isDirectory: ObjCBool = false // Receives the working-directory metadata flag.
        guard FileManager.default.fileExists(atPath: command.workingDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw ManagedPythonProcessError.invalidWorkingDirectory(command.workingDirectoryURL.path) } // Requires a stable existing working directory.
        let process = Process() // Creates the exact Foundation process owned by this invocation.
        let outputPipe = Pipe() // Captures bounded standard output without shell redirection.
        let errorPipe = Pipe() // Captures bounded standard error without shell redirection.
        let outputBuffer = ManagedOutputBuffer(limit: 1_048_576) // Bounds captured standard output to one mebibyte.
        let errorBuffer = ManagedOutputBuffer(limit: 1_048_576) // Bounds captured standard error to one mebibyte.
        outputPipe.fileHandleForReading.readabilityHandler = { handle in outputBuffer.append(handle.availableData) } // Drains output while the process runs to avoid pipe backpressure.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in errorBuffer.append(handle.availableData) } // Drains diagnostics while the process runs to avoid pipe backpressure.
        process.executableURL = command.executableURL // Uses a direct executable URL without invoking a shell.
        process.arguments = command.arguments // Passes each inspected argument as a separate value without interpolation.
        process.currentDirectoryURL = command.workingDirectoryURL // Restricts relative outputs to the selected working directory.
        process.standardOutput = outputPipe // Connects bounded standard-output capture.
        process.standardError = errorPipe // Connects bounded standard-error capture.
        var environment = ProcessInfo.processInfo.environment // Starts with the configured app environment needed by Python and Metal.
        command.environment.forEach { environment[$0.key] = $0.value } // Overlays only explicit runtime values.
        process.environment = environment // Supplies the final deterministic environment to the child.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic launch-to-exit timing.
        let gate = ManagedProcessCompletionGate(process: process, timeoutMilliseconds: max(1, command.timeoutMilliseconds)) // Creates a single-resolution timeout and cancellation gate.
        process.terminationHandler = { terminated in gate.processDidTerminate(status: terminated.terminationStatus) } // Resolves only when the exact owned process reports exit.
        do { // Attempts direct Foundation launch.
            try process.run() // Starts the configured executable without a shell.
        } catch { // Converts launch failure into the stable process domain.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Stops capture callbacks for a process that never launched.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Stops diagnostic callbacks for a process that never launched.
            throw ManagedPythonProcessError.launchFailed(error.localizedDescription) // Returns the actual launch diagnostic.
        } // Ends direct process launch recovery.
        activeProcess = process // Publishes exact process ownership only after successful launch.
        activeGate = gate // Publishes its exact terminal gate for cooperative cancellation.
        gate.beginTimeout() // Starts the bounded deadline after the child exists.
        do { // Awaits termination while supporting cooperative parent-task cancellation.
            let status = try await withTaskCancellationHandler(operation: { try await gate.wait() }, onCancel: { gate.cancel() }) // Stops only this process when its owning Swift task is cancelled.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Releases output capture after confirmed process exit.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Releases diagnostic capture after confirmed process exit.
            activeProcess = nil // Releases actor ownership after confirmed termination.
            activeGate = nil // Releases the completed terminal gate.
            let duration = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Measures actual end-to-end child lifetime.
            return ManagedPythonResult(processID: process.processIdentifier, terminationStatus: status, standardOutput: outputBuffer.stringValue, standardError: errorBuffer.stringValue, durationMilliseconds: duration) // Returns bounded real process evidence.
        } catch { // Releases actor state after timeout or cancellation has terminated the exact process.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Stops output callbacks after terminal failure.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Stops diagnostic callbacks after terminal failure.
            activeProcess = nil // Releases exact process ownership after the gate confirms exit.
            activeGate = nil // Releases terminal gate ownership.
            throw error // Preserves timeout or cancellation identity.
        } // Ends awaited process recovery.
    } // Ends one managed Python execution.

    func cancel() { // Cancels only the command currently owned by this runner.
        activeGate?.cancel() // Requests bounded termination through the single-resolution gate.
    } // Ends explicit runner cancellation.
} // Ends serialized managed Python process runner.

private final class ManagedOutputBuffer: @unchecked Sendable { // Provides lock-protected bounded pipe accumulation across Foundation callbacks.
    private let lock = NSLock() // Serializes mutable Data access from readability callbacks and result collection.
    private let limit: Int // Stores the maximum captured bytes.
    private var data = Data() // Stores the bounded raw UTF-8-compatible bytes.

    init(limit: Int) { // Creates one buffer with a normalized positive byte limit.
        self.limit = max(1, limit) // Prevents a non-positive configuration from disabling safe draining logic.
    } // Ends output-buffer construction.

    func append(_ incoming: Data) { // Appends as many bytes as remain within the configured bound.
        guard !incoming.isEmpty else { return } // Ignores the EOF callback.
        lock.lock() // Begins exclusive buffer mutation.
        let remaining = max(0, limit - data.count) // Calculates safe remaining capacity.
        if remaining > 0 { data.append(incoming.prefix(remaining)) } // Retains only bounded leading output while still draining the full pipe callback.
        lock.unlock() // Ends exclusive buffer mutation.
    } // Ends bounded output append.

    var stringValue: String { // Converts captured bytes into a display-safe string.
        lock.lock() // Begins exclusive buffer read.
        let snapshot = data // Copies the bounded immutable result.
        lock.unlock() // Ends exclusive buffer read.
        return String(decoding: snapshot, as: UTF8.self) // Replaces malformed byte sequences safely.
    } // Ends output string access.
} // Ends bounded output buffer.

private final class ManagedProcessCompletionGate: @unchecked Sendable { // Guarantees one continuation resolution across exit, timeout, and cancellation races.
    private let lock = NSLock() // Serializes terminal state and continuation access.
    private let process: Process // Retains only the exact child owned by the runner.
    private let timeoutMilliseconds: Int // Stores the normalized terminal deadline.
    private var continuation: CheckedContinuation<Int32, Error>? // Stores the single awaiting Swift continuation.
    private var terminalStatus: Int32? // Stores an exit that occurs before wait registration.
    private var terminalError: ManagedPythonProcessError? // Stores timeout or cancellation identity until actual exit.
    private var resolved = false // Prevents duplicate continuation resume.

    init(process: Process, timeoutMilliseconds: Int) { // Captures exact process ownership and timeout policy.
        self.process = process // Stores the direct Foundation child reference.
        self.timeoutMilliseconds = timeoutMilliseconds // Stores the positive deadline.
    } // Ends completion-gate construction.

    func beginTimeout() { // Starts a detached deadline that does not retain actor isolation.
        Task { // Creates a cancellable lightweight timeout observer.
            try? await Task.sleep(nanoseconds: UInt64(timeoutMilliseconds) * 1_000_000) // Waits for the configured millisecond deadline.
            requestTermination(error: .timedOut(timeoutMilliseconds)) // Requests exact-process termination only if the gate is still active.
        } // Ends timeout observer.
    } // Ends timeout startup.

    func wait() async throws -> Int32 { // Awaits the exact process's terminal state once.
        try await withCheckedThrowingContinuation { continuation in // Bridges Foundation termination into Swift concurrency.
            lock.lock() // Begins exclusive terminal-state inspection.
            if let status = terminalStatus { // Handles a very fast process that exited before wait registration.
                let error = terminalError // Captures any timeout or cancellation identity associated with that exit.
                resolved = true // Marks the gate terminal before resuming.
                lock.unlock() // Releases the lock before continuation machinery.
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: status) } // Preserves terminal cause.
                return // Ends immediate terminal handling.
            } // Ends early-exit handling.
            self.continuation = continuation // Stores the only waiter for the later termination callback.
            lock.unlock() // Ends exclusive wait registration.
        } // Ends Foundation termination bridge.
    } // Ends exact process wait.

    func processDidTerminate(status: Int32) { // Receives Foundation confirmation that the exact child exited.
        lock.lock() // Begins exclusive terminal resolution.
        guard !resolved else { lock.unlock(); return } // Ignores duplicate framework callbacks safely.
        terminalStatus = status // Stores the actual child exit status.
        guard let continuation else { lock.unlock(); return } // Allows wait registration to consume an early exit later.
        self.continuation = nil // Clears the waiter before resuming.
        let error = terminalError // Captures timeout or cancellation identity.
        resolved = true // Marks the gate terminal.
        lock.unlock() // Releases the lock before continuation machinery.
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: status) } // Returns exit or the reason termination was requested.
    } // Ends exact process termination callback.

    func cancel() { // Requests cooperative cancellation of the exact child.
        requestTermination(error: .cancelled) // Uses the same bounded termination path as timeout.
    } // Ends cancellation request.

    private func requestTermination(error: ManagedPythonProcessError) { // Marks terminal cause and stops only the exact retained child.
        lock.lock() // Begins exclusive cause mutation.
        guard !resolved, terminalStatus == nil, terminalError == nil else { lock.unlock(); return } // Ignores late or duplicate timeout and cancellation requests.
        terminalError = error // Preserves the first terminal cause.
        let shouldTerminate = process.isRunning // Reads child liveness while the gate still owns it.
        lock.unlock() // Releases the lock before calling Process APIs.
        if shouldTerminate { process.terminate() } // Sends graceful termination only to the exact retained child.
        Task { // Starts a bounded force fallback if graceful termination is ignored.
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Allows one second for exact-process graceful exit.
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) } // Forces only the exact retained PID after the grace period.
        } // Ends bounded force fallback.
    } // Ends exact-process termination request.
} // Ends single-resolution process completion gate.
