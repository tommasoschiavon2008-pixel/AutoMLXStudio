import Foundation

enum MLXServiceError: LocalizedError {
    case portInUse(Int, String)
    case executableMissing(String)
    case processRefusedToStop(Int32) // Reports a tracked Project 5 process that survived graceful and forced termination deadlines.

    var errorDescription: String? {
        switch self {
        case let .portInUse(port, owner):
            if owner.isEmpty {
                return "Port \(port) is already in use."
            }
            return "Port \(port) is already in use by: \(owner)"
        case let .executableMissing(path):
            return "MLX executable not found: \(path)"
        case let .processRefusedToStop(processID):
            return "Tracked MLX process \(processID) did not terminate within the configured timeout. A replacement model was not started." // Prevents unsafe overlapping large models.
        }
    }
}

struct ManagedProcessStopResult: Equatable, Sendable { // Reports verified shutdown facts for one process owned by this MLXService instance.
    let processID: Int32? // Identifies only the exact tracked process, never another Python process.
    let durationMilliseconds: Int // Records graceful plus optional forced-stop elapsed time.
    let forcedTermination: Bool // Records whether SIGKILL was required after the graceful deadline.
    let exitConfirmed: Bool // Records whether Process confirmed termination before replacement startup.
} // Ends managed-process stop metadata.

final class MLXService {
    private var serverProcess: Process?
    private var workerProcess: Process?

    func startServer(
        executableDirectory: String,
        repoPath: String,
        model: String,
        requestedPort: Int,
        autoSelectPort: Bool,
        onOutput: @escaping (String) -> Void,
        onStarted: @escaping (Int) -> Void,
        onFailure: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        if let existing = serverProcess, existing.isRunning { // Refuses an overlapping direct callback start instead of racing a fire-and-forget stop.
            onFailure("A tracked MLX server is already running. Stop it and wait for shutdown before starting another model.") // Gives direct V0.1 callers an actionable safe lifecycle requirement.
            return // Prevents two medium or large models from being started intentionally.
        } // Ends existing-process overlap protection.
        serverProcess = nil // Clears a stale non-running Process reference before creating a new server.

        let serverExecutable = "\(executableDirectory)/mlx_lm.server"
        guard FileManager.default.isExecutableFile(atPath: serverExecutable) else {
            onFailure(MLXServiceError.executableMissing(serverExecutable).localizedDescription)
            return
        }

        let selectedPort: Int
        if Self.portIsListening(requestedPort) {
            if autoSelectPort, let free = Self.firstFreePort(startingAt: requestedPort + 1, maxAttempts: 100) {
                selectedPort = free
                onOutput("Port \(requestedPort) is busy. Using free port \(selectedPort).")
            } else {
                let owner = Self.portOwner(requestedPort)
                onFailure(MLXServiceError.portInUse(requestedPort, owner).localizedDescription)
                return
            }
        } else {
            selectedPort = requestedPort
        }

        let process = makeExecutableProcess(
            executablePath: serverExecutable,
            repoPath: repoPath,
            arguments: [
                "--model", model,
                "--host", "127.0.0.1",
                "--port", String(selectedPort)
            ],
            onOutput: onOutput
        )

        process.terminationHandler = { [weak self] process in
            guard self?.serverProcess === process else { return }
            onExit(process.terminationStatus)
        }

        do {
            try process.run()
            serverProcess = process

            Task.detached { [weak process] in
                for _ in 0..<120 {
                    guard let process, process.isRunning else {
                        onFailure("MLX server exited before becoming ready.")
                        return
                    }

                    if await Self.isMLXServerReady(port: selectedPort) {
                        onStarted(selectedPort)
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(250))
                }

                if let process, process.isRunning { // Handles readiness timeout as an owned-process cleanup operation.
                    _ = await Self.stopOwnedProcess(process, gracefulTimeoutMilliseconds: 1_000, forcedTimeoutMilliseconds: 1_000) // Stops only the process created by this start attempt.
                    onFailure("MLX server started but did not become ready in time.") // Reports failure only after bounded cleanup was attempted.
                }
            }
        } catch {
            onFailure("Could not start mlx_lm.server: \(error.localizedDescription)")
        }
    }

    func stopServer() {
        guard let process = serverProcess else { return }
        serverProcess = nil

        if process.isRunning {
            process.terminate()

            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    func startServer( // Provides an async bridge for serialized V0.2 model transitions without duplicating process logic.
        executableDirectory: String, // Accepts the existing MLX virtual-environment binary folder.
        repoPath: String, // Accepts the existing mlx-lm repository working directory.
        model: String, // Accepts the selected repository identifier or validated local model path.
        requestedPort: Int, // Accepts the current persisted preferred port.
        autoSelectPort: Bool, // Preserves the existing automatic free-port behavior.
        onOutput: @escaping (String) -> Void // Forwards server diagnostics to the existing application log.
    ) async throws -> Int { // Returns only after the existing readiness probe succeeds or reports failure.
        try await withCheckedThrowingContinuation { continuation in // Bridges the proven callback lifecycle into Swift concurrency.
            let gate = MLXStartContinuationGate(continuation: continuation) // Guarantees that overlapping failure and exit callbacks resume only once.
            startServer( // Reuses the existing executable, port, process, and readiness implementation.
                executableDirectory: executableDirectory, // Preserves the configured executable directory.
                repoPath: repoPath, // Preserves the configured repository working directory.
                model: model, // Supplies the model selected by ModelRouter.
                requestedPort: requestedPort, // Supplies the preferred local port.
                autoSelectPort: autoSelectPort, // Preserves deterministic next-free-port selection.
                onOutput: onOutput, // Preserves existing process logging.
                onStarted: { port in gate.succeed(port) }, // Completes the async call with the actual ready port.
                onFailure: { message in gate.fail(message) }, // Completes the async call with the existing actionable diagnostic.
                onExit: { code in gate.fail("MLX server stopped before the model transition completed (\(code)).") } // Covers an early process exit not already reported by readiness.
            ) // Ends reuse of callback server startup.
        } // Ends callback-to-async bridging.
    } // Ends async server startup.

    func stopServerAndWait() async { // Preserves the source-compatible awaited stop entry point.
        _ = try? await stopServerAndWait(gracefulTimeoutMilliseconds: 3_000, forcedTimeoutMilliseconds: 1_000) // Uses the prior effective deadlines while discarding metrics for legacy callers.
    } // Ends compatibility awaited server stop.

    func stopServerAndWait(gracefulTimeoutMilliseconds: Int, forcedTimeoutMilliseconds: Int = 1_000) async throws -> ManagedProcessStopResult { // Stops and verifies the exact tracked process using configurable deadlines.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic shutdown timing.
        guard let process = serverProcess else { return ManagedProcessStopResult(processID: nil, durationMilliseconds: 0, forcedTermination: false, exitConfirmed: true) } // Reports a verified no-process state immediately.
        let processID = process.processIdentifier // Captures the exact owned PID before any termination signal.
        guard process.isRunning else { // Handles a process that exited before the stop request.
            if serverProcess === process { serverProcess = nil } // Clears only the matching stale reference.
            return ManagedProcessStopResult(processID: processID, durationMilliseconds: Self.elapsedMilliseconds(since: start), forcedTermination: false, exitConfirmed: true) // Reports confirmed prior exit.
        } // Ends already-exited handling.
        let result = await Self.stopOwnedProcess(process, gracefulTimeoutMilliseconds: max(0, gracefulTimeoutMilliseconds), forcedTimeoutMilliseconds: max(0, forcedTimeoutMilliseconds)) // Signals only the exact Process instance owned by this service.
        if result.exitConfirmed, serverProcess === process { serverProcess = nil } // Releases ownership only after exit confirmation.
        guard result.exitConfirmed else { throw MLXServiceError.processRefusedToStop(processID) } // Blocks replacement startup when even forced termination was not confirmed.
        return ManagedProcessStopResult(processID: processID, durationMilliseconds: Self.elapsedMilliseconds(since: start), forcedTermination: result.forcedTermination, exitConfirmed: true) // Returns verified stop timing and forced-stop status.
    } // Ends configurable verified server stop.

    func managedServerProcessID() -> Int32? { // Exposes only the process identifier created and retained by this service.
        guard let serverProcess, serverProcess.isRunning else { return nil } // Omits absent or terminated process references.
        return serverProcess.processIdentifier // Returns the exact managed PID for operational memory sampling.
    } // Ends managed process identity access.

    private static func stopOwnedProcess(_ process: Process, gracefulTimeoutMilliseconds: Int, forcedTimeoutMilliseconds: Int) async -> (forcedTermination: Bool, exitConfirmed: Bool) { // Terminates only a Process already proven to be owned by this service.
        guard process.isRunning else { return (false, true) } // Reports immediate success for an already-exited owned process.
        process.terminate() // Requests graceful termination first.
        if await waitForExit(process, timeoutMilliseconds: gracefulTimeoutMilliseconds) { return (false, true) } // Completes without force when the process exits on time.
        guard process.isRunning else { return (false, true) } // Handles an exit at the graceful deadline boundary.
        kill(process.processIdentifier, SIGKILL) // Force-terminates only the exact tracked PID after graceful timeout.
        return (true, await waitForExit(process, timeoutMilliseconds: forcedTimeoutMilliseconds)) // Reports whether forced termination produced a confirmed exit.
    } // Ends owned-process shutdown.

    private static func waitForExit(_ process: Process, timeoutMilliseconds: Int) async -> Bool { // Polls Process state without blocking an actor or thread.
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, timeoutMilliseconds)) * 1_000_000 // Creates a monotonic bounded deadline.
        while process.isRunning, DispatchTime.now().uptimeNanoseconds < deadline { // Waits only while the exact process remains alive and time remains.
            try? await Task.sleep(for: .milliseconds(50)) // Yields cooperatively between state checks.
        } // Ends bounded exit wait.
        return !process.isRunning // Returns authoritative Process termination state.
    } // Ends bounded process-exit wait.

    private static func elapsedMilliseconds(since start: UInt64) -> Int { // Converts monotonic elapsed nanoseconds into trace metrics.
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Returns whole elapsed milliseconds.
    } // Ends MLX lifecycle timing conversion.

    func chat(port: Int, model: String, messages: [ChatMessage]) async throws -> String {
        let requestMessages = messages.map { OpenAIChatRequest.Message(role: $0.role, content: $0.content) } // Preserves the legacy direct-chat API for compatibility checks.
        return try await requestChatCompletion(port: port, model: model, messages: requestMessages, maxTokens: 512) // Routes legacy calls through the one shared HTTP implementation.
    }

    func complete( // Exposes a system-prompt-aware call used by the multi-agent client adapter.
        port: Int, // Accepts the currently active local server port.
        model: String, // Accepts the configured MLX model identifier.
        systemPrompt: String, // Accepts the selected agent's centralized instructions.
        history: [LLMConversationMessage], // Accepts only the bounded conversation context selected by the workflow.
        userPrompt: String, // Accepts the current stage payload.
        maxTokens: Int // Accepts the generation limit appropriate to the workflow stage.
    ) async throws -> String { // Begins the shared agent completion method.
        var messages = [OpenAIChatRequest.Message(role: "system", content: systemPrompt)] // Starts the request with the selected agent instructions.
        messages.append(contentsOf: history.map { OpenAIChatRequest.Message(role: $0.role, content: $0.content) }) // Adds bounded recent conversation context.
        messages.append(OpenAIChatRequest.Message(role: "user", content: userPrompt)) // Adds the current request after its relevant context.
        return try await requestChatCompletion(port: port, model: model, messages: messages, maxTokens: maxTokens) // Reuses the single OpenAI-compatible HTTP implementation.
    } // Ends the system-prompt-aware completion method.

    private func requestChatCompletion( // Centralizes all HTTP networking for direct and orchestrated chat completions.
        port: Int, // Accepts the local endpoint port.
        model: String, // Accepts the model identifier sent in the request body.
        messages: [OpenAIChatRequest.Message], // Accepts the complete ordered message list.
        maxTokens: Int // Accepts the response token limit.
    ) async throws -> String { // Begins the one shared network implementation.
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { // Validates the endpoint instead of force-unwrapping it.
            throw NSError(domain: "AutoMLXStudio", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid local MLX server URL."]) // Returns a deterministic configuration error.
        } // Ends endpoint validation.
        var request = URLRequest(url: url) // Creates the local HTTP request.
        request.httpMethod = "POST" // Uses the OpenAI-compatible POST method.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // Declares the encoded JSON request body.
        request.timeoutInterval = 180 // Allows the bounded 2,048-token local Reviewer request to finish while retaining a finite transport deadline.

        let body = OpenAIChatRequest( // Creates the existing typed OpenAI-compatible payload.
            model: model, // Sends the configured model identifier.
            messages: messages, // Sends system, bounded history, and stage prompt in order.
            stream: false, // Preserves the existing non-streaming response behavior.
            max_tokens: maxTokens // Applies the stage-specific token limit.
        ) // Ends request payload construction.

        request.httpBody = try JSONEncoder().encode(body) // Encodes the typed payload as JSON.
        let (data, response) = try await URLSession.shared.data(for: request) // Executes the request through the existing system URL session.

        guard let http = response as? HTTPURLResponse else { // Validates that the local endpoint returned HTTP metadata.
            throw NSError( // Creates the same user-visible invalid-response error used previously.
                domain: "AutoMLXStudio", // Uses the existing application error domain.
                code: 1, // Preserves the existing invalid-response error code.
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from local server."] // Supplies a concise diagnostic.
            ) // Ends invalid-response error construction.
        } // Ends HTTP response validation.

        guard (200..<300).contains(http.statusCode) else { // Rejects non-success responses before decoding model output.
            let serverText = String(data: data, encoding: .utf8) ?? "Unknown server error" // Preserves diagnostic response text for graceful error mapping.
            throw NSError( // Creates a typed status-code failure.
                domain: "AutoMLXStudio", // Uses the existing application error domain.
                code: http.statusCode, // Preserves the local server's HTTP status code.
                userInfo: [ // Starts the localized diagnostic payload.
                    NSLocalizedDescriptionKey: // Selects the standard localized error key.
                        "Local server returned HTTP \(http.statusCode).\n\(serverText)" // Includes the server response for logging and compact recovery messaging.
                ] // Ends the localized diagnostic payload.
            ) // Ends HTTP failure construction.
        } // Ends successful-status validation.

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data) // Decodes the existing OpenAI-compatible response model.
        guard let first = decoded.choices.first else { // Verifies that the server returned at least one candidate.
            throw NSError( // Creates the same empty-response error used previously.
                domain: "AutoMLXStudio", // Uses the existing application error domain.
                code: 2, // Preserves the existing no-choice error code.
                userInfo: [NSLocalizedDescriptionKey: "No response returned by MLX server."] // Supplies a concise diagnostic.
            ) // Ends empty-response error construction.
        } // Ends response-choice validation.
        guard let content = first.message.userFacingContent else { // Requires a user-facing answer even when the server returned separate reasoning metadata.
            let detail = first.message.reasoning == nil ? "The local server returned no assistant content." : "The model exhausted its response before producing user-facing content; private reasoning was not exposed." // Distinguishes an empty response from a bounded reasoning-only response safely.
            throw NSError(domain: "AutoMLXStudio", code: 3, userInfo: [NSLocalizedDescriptionKey: detail]) // Enables deterministic fallback without leaking reasoning into logs, traces, or later prompts.
        } // Ends safe assistant-content validation.
        return content // Returns only normalized user-facing assistant content to the caller.
    }

    func runDynamicQuantization(
        executableDirectory: String,
        repoPath: String,
        model: String,
        outputPath: String,
        targetBPW: Double,
        lowBits: Int,
        highBits: Int,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        workerProcess?.terminate()

        let executable = "\(executableDirectory)/mlx_lm.dynamic_quant"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            onOutput("MLX dynamic quant executable not found: \(executable)")
            onExit(-1)
            return
        }

        let process = makeExecutableProcess(
            executablePath: executable,
            repoPath: repoPath,
            arguments: [
                "--model", model,
                "--mlx-path", outputPath,
                "--target-bpw", String(format: "%.2f", targetBPW),
                "--low-bits", String(lowBits),
                "--high-bits", String(highBits)
            ],
            onOutput: onOutput
        )

        process.terminationHandler = { process in
            onExit(process.terminationStatus)
        }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: (outputPath as NSString).deletingLastPathComponent),
                withIntermediateDirectories: true
            )
            try process.run()
            workerProcess = process
        } catch {
            onOutput("Could not start dynamic quantization: \(error.localizedDescription)")
            onExit(-1)
        }
    }

    func runBenchmark(
        executableDirectory: String,
        repoPath: String,
        model: String,
        onOutput: @escaping (String) -> Void,
        onResult: @escaping (BenchmarkResult) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        workerProcess?.terminate()

        let executable = "\(executableDirectory)/mlx_lm.generate"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            onFailure("MLX generate executable not found: \(executable)")
            return
        }

        let prompt = "Write a concise explanation of why unified memory matters for local LLM inference on Apple Silicon."
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.arguments = [
            "--model", model,
            "--prompt", prompt,
            "--max-tokens", "128"
        ]

        process.environment = Self.offlineRuntimeEnvironment( // Applies the one deterministic offline environment shared by every app-launched MLX text process.
            inheriting: ProcessInfo.processInfo.environment, // Preserves every unrelated variable inherited from the host application.
            executableDirectory: executableDirectory // Preserves the benchmark executable-directory PATH prefix used by the existing direct Process launch.
        ) // Finishes benchmark environment configuration without starting a shell or changing its arguments.

        var allOutput = ""
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let lock = NSLock()
        func consume(_ handle: FileHandle) {
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                lock.lock()
                allOutput += text
                lock.unlock()
                onOutput(text)
            }
        }

        consume(stdout.fileHandleForReading)
        consume(stderr.fileHandleForReading)

        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            guard process.terminationStatus == 0 else {
                onFailure("mlx_lm.generate exited with \(process.terminationStatus)")
                return
            }

            lock.lock()
            let output = allOutput
            lock.unlock()

            let promptTPS = Self.extractNumber(
                pattern: #"Prompt:.*?([0-9]+(?:\.[0-9]+)?) tokens-per-sec"#,
                text: output
            )
            let generationTPS = Self.extractNumber(
                pattern: #"Generation:.*?([0-9]+(?:\.[0-9]+)?) tokens-per-sec"#,
                text: output
            )
            let peakGB = Self.extractNumber(
                pattern: #"Peak memory:\s*([0-9]+(?:\.[0-9]+)?) GB"#,
                text: output
            )

            guard let promptTPS, let generationTPS, let peakGB else {
                onFailure("Could not parse benchmark metrics from MLX output.")
                return
            }

            onResult(
                BenchmarkResult(
                    model: model,
                    promptTokensPerSecond: promptTPS,
                    generationTokensPerSecond: generationTPS,
                    peakMemoryGB: peakGB,
                    profile: "Current model"
                )
            )
        }

        do {
            try process.run()
            workerProcess = process
        } catch {
            onFailure(error.localizedDescription)
        }
    }

    private func makeExecutableProcess(
        executablePath: String,
        repoPath: String,
        arguments: [String],
        onOutput: @escaping (String) -> Void
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.arguments = arguments

        let binDirectory = (executablePath as NSString).deletingLastPathComponent // Derives the same direct executable directory previously prepended to PATH.
        process.environment = Self.offlineRuntimeEnvironment( // Applies offline mode to both the text server and legacy quantization worker created by this factory.
            inheriting: ProcessInfo.processInfo.environment, // Preserves the complete environment inherited by the application process.
            executableDirectory: binDirectory // Preserves the existing venv-bin PATH precedence for direct executable launches.
        ) // Finishes shared server and worker environment configuration without changing Process ownership or arguments.

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        for handle in [stdout.fileHandleForReading, stderr.fileHandleForReading] {
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                onOutput(text)
            }
        }

        return process
    }

    static func offlineRuntimeEnvironment( // Produces a deterministic environment for every MLX text runtime without launching a process.
        inheriting inheritedEnvironment: [String: String], // Accepts an explicit base dictionary so unit tests never need to execute MLX.
        executableDirectory: String // Accepts the existing executable directory that must retain PATH precedence.
    ) -> [String: String] { // Returns a complete copy of the inherited environment with only required runtime overrides.
        var environment = inheritedEnvironment // Copies every inherited variable before applying narrowly scoped MLX settings.
        environment["PATH"] = "\(executableDirectory):\(inheritedEnvironment["PATH"] ?? "")" // Preserves the prior direct-process PATH behavior, including an empty inherited PATH.
        environment["PYTHONUNBUFFERED"] = "1" // Preserves immediate Python output delivery for logs and benchmark parsing.
        environment["HF_HUB_OFFLINE"] = "1" // Prevents Hugging Face Hub network access during local model resolution.
        environment["TRANSFORMERS_OFFLINE"] = "1" // Forces Transformers to resolve configuration and weights from local storage only.
        environment["HF_DATASETS_OFFLINE"] = "1" // Prevents an MLX dependency from reaching Hugging Face Datasets during app-owned execution.
        return environment // Returns the fully inherited, offline-hardened environment to the direct Process caller.
    } // Ends deterministic offline environment construction.

    private static func portIsListening(_ port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func portOwner(_ port: Int) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text.split(separator: "\n")
            guard lines.count > 1 else { return "" }
            return lines.dropFirst().prefix(3).joined(separator: " | ")
        } catch {
            return ""
        }
    }

    private static func isMLXServerReady(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["data"] != nil
            else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private static func extractNumber(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges >= 2,
            let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }

        return Double(text[valueRange])
    }
    
    private static func firstFreePort(startingAt startPort: Int, maxAttempts: Int) -> Int? {
        for port in startPort..<(startPort + maxAttempts) {
            if !portIsListening(port) {
                return port
            }
        }

        return nil
    }
}
