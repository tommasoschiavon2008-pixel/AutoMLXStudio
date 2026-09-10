import Darwin // Supplies exact-PID SIGKILL escalation for only the child process owned by this runner.
import Foundation // Supplies direct Process execution, pipes, monotonic timing, locks, and Swift concurrency bridges.

actor EngineeringProcessRunner { // Serializes deterministic commands and owns at most one exact child process.
    private var activeProcess: Process? // Retains the exact Process instance launched by the current invocation.
    private var activeGate: EngineeringProcessCompletionGate? // Retains the single-resolution timeout and cancellation gate.

    func run(executableURL: URL, arguments: [String], workingDirectoryURL: URL, environment: [String: String], timeoutMilliseconds: Int, outputLimitBytes: Int) async throws -> EngineeringProcessResult { // Launches one direct executable without a shell and returns bounded evidence.
        guard activeProcess == nil else { throw EngineeringRuntimeError.processLaunchFailed("Another engineering command is already active.") } // Prevents ambiguous overlapping ownership in one runner.
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw EngineeringRuntimeError.executableMissing(executableURL.path) } // Requires the exact allowlisted host executable.
        var isDirectory: ObjCBool = false // Receives current-directory filesystem metadata.
        guard FileManager.default.fileExists(atPath: workingDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw EngineeringRuntimeError.workspaceUnavailable(workingDirectoryURL.path) } // Requires an existing contained cwd supplied by EngineeringWorkspace.
        let process = Process() // Creates the exact child object owned by this invocation.
        let outputPipe = Pipe() // Captures stdout without invoking a shell or writing external artifacts.
        let errorPipe = Pipe() // Captures stderr independently for structured results.
        let outputBuffer = EngineeringBoundedOutputBuffer(limit: max(1, outputLimitBytes)) // Keeps bounded beginning and end of stdout while draining all bytes.
        let errorBuffer = EngineeringBoundedOutputBuffer(limit: max(1, outputLimitBytes)) // Keeps bounded beginning and end of stderr while draining all bytes.
        outputPipe.fileHandleForReading.readabilityHandler = { handle in outputBuffer.append(handle.availableData) } // Continuously drains stdout to avoid pipe backpressure.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in errorBuffer.append(handle.availableData) } // Continuously drains stderr to avoid pipe backpressure.
        process.executableURL = executableURL // Launches the exact resolved binary directly.
        process.arguments = arguments // Preserves every argument boundary so shell metacharacters remain ordinary data.
        process.currentDirectoryURL = workingDirectoryURL // Constrains relative child paths to the authorized workspace cwd.
        process.environment = environment // Supplies only the caller's sanitized non-secret environment.
        process.standardOutput = outputPipe // Connects bounded stdout capture.
        process.standardError = errorPipe // Connects bounded stderr capture.
        let normalizedTimeout = max(1, timeoutMilliseconds) // Guarantees a finite positive deadline.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic wall-clock measurement.
        let gate = EngineeringProcessCompletionGate(process: process, timeoutMilliseconds: normalizedTimeout) // Couples exact process ownership to one terminal result.
        process.terminationHandler = { terminated in gate.processDidTerminate(status: terminated.terminationStatus) } // Resolves only after Foundation confirms this exact child exited.
        do { // Attempts direct Foundation launch.
            try process.run() // Starts the executable without `/bin/sh -c` or user-shell evaluation.
        } catch { // Normalizes launch failures before publishing actor ownership.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Stops stdout callbacks for an unlaunched process.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Stops stderr callbacks for an unlaunched process.
            throw EngineeringRuntimeError.processLaunchFailed(EngineeringSecretRedactor.redact(error.localizedDescription)) // Returns a bounded secret-safe diagnostic.
        } // Ends direct launch handling.
        activeProcess = process // Publishes exact ownership only after successful launch.
        activeGate = gate // Publishes the matching terminal gate.
        gate.beginTimeout() // Starts the finite command deadline after a real child PID exists.
        do { // Awaits exact process exit with cooperative Swift task cancellation.
            let status = try await withTaskCancellationHandler(operation: { try await gate.wait() }, onCancel: { gate.cancel() }) // Requests termination only for this owned child on cancellation.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Stops concurrent stdout callbacks after confirmed exit.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Stops concurrent stderr callbacks after confirmed exit.
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile()) // Drains any final bytes delivered between the last callback and exit.
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile()) // Drains any final diagnostic bytes after exit.
            activeProcess = nil // Releases exact process ownership after confirmed termination.
            activeGate = nil // Releases the completed gate.
            let duration = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Measures actual launch-to-exit duration.
            return EngineeringProcessResult(processID: process.processIdentifier, terminationStatus: status, standardOutput: EngineeringSecretRedactor.redact(outputBuffer.stringValue), standardError: EngineeringSecretRedactor.redact(errorBuffer.stringValue), outputWasTruncated: outputBuffer.wasTruncated || errorBuffer.wasTruncated, durationMilliseconds: duration) // Returns bounded malformed-UTF-8-safe and secret-redacted evidence.
        } catch { // Releases actor state only after the gate has confirmed owned-child exit.
            outputPipe.fileHandleForReading.readabilityHandler = nil // Stops stdout callbacks after terminal failure.
            errorPipe.fileHandleForReading.readabilityHandler = nil // Stops stderr callbacks after terminal failure.
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile()) // Drains residual stdout without exposing it through the thrown error.
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile()) // Drains residual stderr without exposing it through the thrown error.
            activeProcess = nil // Releases exact process ownership.
            activeGate = nil // Releases terminal gate ownership.
            throw error // Preserves timeout or cancellation identity.
        } // Ends awaited process cleanup.
    } // Ends one deterministic command execution.

    func cancel() { // Cancels only the exact command currently owned by this runtime instance.
        activeGate?.cancel() // Routes cancellation through bounded terminate-then-exact-PID escalation.
    } // Ends explicit command cancellation.

    func activeProcessID() -> Int32? { // Exposes process identity for trace and deterministic cancellation tests.
        activeProcess?.processIdentifier // Returns only the exact currently owned PID.
    } // Ends active-PID inspection.
} // Ends centralized Engineering process ownership.

private final class EngineeringBoundedOutputBuffer: @unchecked Sendable { // Drains arbitrary child output while retaining only bounded beginning and end bytes.
    private let lock = NSLock() // Serializes Foundation readability callbacks and final result collection.
    private let limit: Int // Stores the maximum retained stream byte count excluding the truncation marker.
    private let headLimit: Int // Reserves the first half for initial diagnostics.
    private let tailLimit: Int // Reserves the remaining half for terminal summaries and errors.
    private var head = Data() // Stores all bytes until overflow, then only the fixed beginning.
    private var tail = Data() // Stores the rolling end after overflow.
    private var truncated = false // Records whether any stream bytes were omitted.

    init(limit: Int) { // Creates one positive bounded stream accumulator.
        self.limit = max(1, limit) // Normalizes unusable non-positive input.
        self.headLimit = max(1, limit / 2) // Guarantees at least one retained leading byte.
        self.tailLimit = max(0, limit - max(1, limit / 2)) // Uses the remaining budget for terminal output.
    } // Ends output-buffer construction.

    func append(_ incoming: Data) { // Drains one callback payload and retains it according to head/tail policy.
        guard !incoming.isEmpty else { return } // Ignores EOF callbacks.
        lock.lock() // Begins exclusive bounded-state mutation.
        if !truncated { // Accumulates normally until this payload crosses the configured budget.
            var combined = head // Copies the previously retained complete stream prefix.
            combined.append(incoming) // Adds the new payload while it remains locally bounded by callback flow.
            if combined.count <= limit { // Retains complete content while under budget.
                head = combined // Publishes the complete stream bytes.
            } else { // Transitions permanently into head-plus-tail mode.
                head = Data(combined.prefix(headLimit)) // Freezes the initial diagnostic bytes.
                tail = tailLimit > 0 ? Data(combined.suffix(tailLimit)) : Data() // Retains the latest terminal bytes within remaining budget.
                truncated = true // Records omitted middle output.
            } // Ends first-overflow handling.
        } else if tailLimit > 0 { // Advances the rolling tail after overflow.
            tail.append(incoming) // Adds the fully drained payload temporarily.
            if tail.count > tailLimit { tail = Data(tail.suffix(tailLimit)) } // Drops only old middle bytes while retaining the newest terminal output.
        } // Ends bounded stream accumulation.
        lock.unlock() // Ends exclusive mutation.
    } // Ends one pipe payload drain.

    var wasTruncated: Bool { // Reports whether the retained view omits any stream bytes.
        lock.lock() // Begins exclusive state read.
        let value = truncated // Captures the immutable answer.
        lock.unlock() // Ends exclusive state read.
        return value // Returns truncation evidence.
    } // Ends truncation inspection.

    var stringValue: String { // Converts retained bytes into a display-safe string without assuming valid UTF-8.
        lock.lock() // Begins exclusive snapshot creation.
        let first = head // Copies leading retained bytes.
        let last = tail // Copies trailing retained bytes.
        let didTruncate = truncated // Copies truncation state.
        lock.unlock() // Ends exclusive snapshot creation.
        if !didTruncate { return String(decoding: first, as: UTF8.self) } // Replaces malformed scalar sequences safely in complete bounded output.
        let marker = Data("\n… [output truncated] …\n".utf8) // Makes omitted middle bytes explicit to model and UI.
        var combined = first // Starts the final bounded display payload with initial output.
        combined.append(marker) // Inserts a deterministic truncation notice.
        combined.append(last) // Appends terminal output often containing the useful failure summary.
        return String(decoding: combined, as: UTF8.self) // Represents malformed bytes with Unicode replacement scalars instead of crashing.
    } // Ends bounded output rendering.
} // Ends bounded process output storage.

private final class EngineeringProcessCompletionGate: @unchecked Sendable { // Guarantees one continuation resolution across exit, timeout, and cancellation races.
    private let lock = NSLock() // Serializes terminal state, error cause, and continuation access.
    private let process: Process // Retains only the exact child owned by the invocation.
    private let timeoutMilliseconds: Int // Stores the finite normalized deadline.
    private var continuation: CheckedContinuation<Int32, Error>? // Stores the sole awaiting Swift continuation.
    private var terminalStatus: Int32? // Stores very fast exit status until wait registration.
    private var terminalError: EngineeringRuntimeError? // Stores timeout or cancellation identity until actual child exit.
    private var resolved = false // Prevents duplicate continuation resume.

    init(process: Process, timeoutMilliseconds: Int) { // Captures exact child ownership and timeout policy.
        self.process = process // Retains the direct Foundation child object.
        self.timeoutMilliseconds = max(1, timeoutMilliseconds) // Guarantees a positive timeout.
    } // Ends completion-gate construction.

    func beginTimeout() { // Starts a lightweight bounded deadline observer.
        Task { // Creates independent timeout work that cannot block the runner actor.
            try? await Task.sleep(nanoseconds: UInt64(timeoutMilliseconds) * 1_000_000) // Waits for the configured finite deadline.
            requestTermination(error: .processTimedOut(timeoutMilliseconds)) // Requests cleanup only if the exact child is still unresolved.
        } // Ends timeout observer.
    } // Ends timeout startup.

    func wait() async throws -> Int32 { // Awaits exact child termination once.
        try await withCheckedThrowingContinuation { continuation in // Bridges Foundation termination callbacks into Swift concurrency.
            lock.lock() // Begins exclusive terminal-state inspection.
            if let status = terminalStatus { // Handles exit before wait registration.
                let error = terminalError // Captures any timeout or cancellation cause tied to that exit.
                resolved = true // Marks the gate terminal before resuming.
                lock.unlock() // Releases the lock before continuation machinery.
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: status) } // Preserves the terminal cause.
                return // Ends early-exit handling.
            } // Ends stored-status path.
            self.continuation = continuation // Registers the single waiter.
            lock.unlock() // Ends exclusive registration.
        } // Ends Foundation-to-concurrency bridge.
    } // Ends exact child wait.

    func processDidTerminate(status: Int32) { // Receives Foundation confirmation that this exact child exited.
        lock.lock() // Begins exclusive terminal resolution.
        guard !resolved else { lock.unlock(); return } // Ignores duplicate or late callbacks.
        terminalStatus = status // Stores the actual exit status.
        guard let continuation else { lock.unlock(); return } // Lets a later wait consume a very fast exit.
        self.continuation = nil // Clears the sole waiter before resume.
        let error = terminalError // Captures timeout or cancellation identity.
        resolved = true // Marks the gate terminal exactly once.
        lock.unlock() // Releases the lock before resuming Swift work.
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: status) } // Reports real exit or requested termination cause.
    } // Ends process termination callback.

    func cancel() { // Requests cooperative cancellation of only the exact child.
        requestTermination(error: .processCancelled) // Uses the shared terminate-and-escalate lifecycle.
    } // Ends cancellation request.

    private func requestTermination(error: EngineeringRuntimeError) { // Records one terminal cause and terminates only this gate's child.
        lock.lock() // Begins exclusive terminal-cause arbitration.
        guard !resolved, terminalStatus == nil, terminalError == nil else { lock.unlock(); return } // Lets the first timeout/cancellation/exit event win.
        terminalError = error // Preserves the exact requested termination reason until child exit.
        let processID = process.processIdentifier // Captures only this owned child PID.
        let shouldTerminate = process.isRunning // Determines whether graceful termination is still meaningful.
        lock.unlock() // Ends cause arbitration before interacting with Process.
        if shouldTerminate { process.terminate() } // Sends graceful SIGTERM only to the exact Foundation child.
        Task { // Starts bounded escalation without blocking a caller or the main thread.
            try? await Task.sleep(nanoseconds: 500_000_000) // Allows the owned child half a second to exit cleanly.
            if self.process.isRunning, self.process.processIdentifier == processID { Darwin.kill(processID, SIGKILL) } // Escalates only against the same still-running owned PID.
        } // Ends exact-PID escalation observer.
    } // Ends exact child termination request.
} // Ends process completion arbitration.
