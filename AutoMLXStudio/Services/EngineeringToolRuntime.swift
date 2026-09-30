import Foundation // Supplies direct executable URLs, deterministic timing, temporary app-owned directories, and concurrency primitives.
import CryptoKit // Identifies exact proposed edit bytes in bounded approval metadata.

actor EngineeringToolRuntime { // Centralizes tool registration, validation, containment, approval, execution, cancellation, timing, and structured results.
    let workspace: EngineeringWorkspace // Owns the only filesystem authority exposed to engineering tools.
    private let approvalProvider: any EngineeringApprovalProviding // Supplies nonblocking allow-once or deny decisions for external effects.
    private let approvalTimeoutMilliseconds: Int // Bounds every pending approval without implicit authorization.
    private let requiresMutationApproval: Bool // Requires exact edit and build decisions in interactive sessions.
    private let processRunner: EngineeringProcessRunner // Owns only exact child processes launched by this runtime.
    private let runtimeDirectoryURL: URL // Provides a sanitized HOME and TMPDIR isolated from user credentials.
    private let fileManager: FileManager // Supplies deterministic app-owned runtime-directory setup.

    init(workspace: EngineeringWorkspace, approvalProvider: any EngineeringApprovalProviding = DenyEngineeringApprovalProvider(), approvalTimeoutMilliseconds: Int = 30_000, processRunner: EngineeringProcessRunner = EngineeringProcessRunner(), runtimeDirectoryURL: URL? = nil, fileManager: FileManager = .default, requiresMutationApproval: Bool = false) { // Preserves preauthorized runtime use while supporting per-operation interactive approval.
        self.workspace = workspace // Retains the sole filesystem authority.
        self.approvalProvider = approvalProvider // Retains an injected UI or deterministic test decision source.
        self.approvalTimeoutMilliseconds = max(1, approvalTimeoutMilliseconds) // Guarantees a finite approval deadline.
        self.requiresMutationApproval = requiresMutationApproval // Stores session policy outside model-controlled arguments.
        self.processRunner = processRunner // Retains exact process ownership state.
        self.fileManager = fileManager // Retains filesystem dependency for sanitized runtime storage.
        self.runtimeDirectoryURL = (runtimeDirectoryURL ?? fileManager.temporaryDirectory.appendingPathComponent("AutoMLXStudioEngineeringRuntime/\(UUID().uuidString)", isDirectory: true)).standardizedFileURL // Uses an app-owned per-runtime cache without exposing the user's HOME.
    } // Ends centralized tool-runtime construction.

    static let definitions: [EngineeringToolDefinition] = [ // Registers a compact non-overlapping V0.6 tool surface for model backends.
        EngineeringToolDefinition(name: .listDirectory, summary: "List bounded visible direct children of a workspace-relative directory.", requiredArguments: ["path"], defaultRisk: .safeReadOnly), // Registers direct directory inspection.
        EngineeringToolDefinition(name: .readFile, summary: "Read bounded UTF-8 text from a visible workspace-relative file.", requiredArguments: ["path"], defaultRisk: .safeReadOnly), // Registers safe text reading.
        EngineeringToolDefinition(name: .writeFile, summary: "Atomically overwrite an existing text file from an expected SHA-256 state.", requiredArguments: ["path", "content", "expectedSHA256"], defaultRisk: .workspaceMutation), // Registers conflict-aware complete replacement.
        EngineeringToolDefinition(name: .replaceInFile, summary: "Replace an exact expected number of text occurrences from an expected SHA-256 state.", requiredArguments: ["path", "oldText", "newText", "expectedOccurrences", "expectedSHA256"], defaultRisk: .workspaceMutation), // Registers scoped deterministic replacement.
        EngineeringToolDefinition(name: .createFile, summary: "Create a new contained UTF-8 file without overwriting an existing path.", requiredArguments: ["path", "content"], defaultRisk: .workspaceMutation), // Registers non-overwriting file creation.
        EngineeringToolDefinition(name: .searchFiles, summary: "Search bounded visible filenames using a literal query.", requiredArguments: ["query", "path"], defaultRisk: .safeReadOnly), // Registers filename discovery.
        EngineeringToolDefinition(name: .searchText, summary: "Search bounded visible UTF-8 content using a literal query.", requiredArguments: ["query", "path"], defaultRisk: .safeReadOnly), // Registers textual evidence search.
        EngineeringToolDefinition(name: .fileInfo, summary: "Inspect safe metadata and an optional bounded content hash.", requiredArguments: ["path"], defaultRisk: .safeReadOnly), // Registers metadata inspection.
        EngineeringToolDefinition(name: .runCommand, summary: "Run one allowlisted executable with separate arguments, contained cwd, timeout, and bounded output.", requiredArguments: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds", "reason"], defaultRisk: .safeReadOnly), // Registers direct process execution.
        EngineeringToolDefinition(name: .gitStatus, summary: "Run bounded read-only Git porcelain status in the workspace.", requiredArguments: [], defaultRisk: .safeReadOnly), // Registers Git status.
        EngineeringToolDefinition(name: .gitDiff, summary: "Run bounded read-only Git diff in the workspace.", requiredArguments: [], defaultRisk: .safeReadOnly), // Registers Git diff.
        EngineeringToolDefinition(name: .gitLog, summary: "Run bounded read-only Git oneline history in the workspace.", requiredArguments: ["limit"], defaultRisk: .safeReadOnly), // Registers Git history.
        EngineeringToolDefinition(name: .buildProject, summary: "Run an explicit allowlisted build command in the workspace.", requiredArguments: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds"], defaultRisk: .workspaceMutation), // Registers higher-level build execution.
        EngineeringToolDefinition(name: .runTests, summary: "Run an explicit allowlisted test command in the workspace.", requiredArguments: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds"], defaultRisk: .workspaceMutation), // Registers higher-level test execution.
        EngineeringToolDefinition(name: .unifiedDiff, summary: "Inspect the bounded unified diff for one app-owned change.", requiredArguments: ["changeID"], defaultRisk: .safeReadOnly), // Registers Git-independent change inspection.
        EngineeringToolDefinition(name: .rollbackChange, summary: "Revert one app-owned change only when its authored state is still current.", requiredArguments: ["changeID"], defaultRisk: .workspaceMutation) // Registers conflict-aware rollback.
    ] // Ends typed tool registration.

    func execute(_ invocation: EngineeringToolInvocation) async -> EngineeringToolResult { // Validates and executes one typed invocation without exposing Foundation APIs to agents.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic validation-and-execution timing.
        let risk: EngineeringToolRisk // Stores the final command-aware risk classification.
        do { // Classifies arguments before any external effect.
            risk = try await riskForInvocation(invocation) // Uses static tool semantics plus deterministic command policy.
        } catch { // Normalizes pre-execution policy refusal.
            return failure(tool: invocation.toolName, risk: .blocked, error: error, startNanoseconds: start) // Returns a structured blocked result without launching anything.
        } // Ends risk classification.
        if risk == .blocked { // Refuses blocked actions without presenting an approval bypass.
            return failure(tool: invocation.toolName, risk: risk, error: EngineeringRuntimeError.commandBlocked(displayText(for: invocation)), startNanoseconds: start) // Reports exact safe display context.
        } // Ends unconditional block handling.
        if risk == .externalSideEffect || (requiresMutationApproval && risk == .workspaceMutation) { // Requires exact approval for external effects and interactive mutations.
            let rootPath = workspace.rootURL.path // Reads the authorized root only for the user-visible approval prompt.
            let request = EngineeringApprovalRequest(id: UUID(), tool: invocation.toolName, risk: risk, exactCommand: displayText(for: invocation), workspacePath: rootPath, reason: reason(for: invocation)) // Creates a complete bounded approval request.
            let decision = await EngineeringApprovalRace.resolve(provider: approvalProvider, request: request, timeoutMilliseconds: approvalTimeoutMilliseconds) // Waits without blocking the main thread or auto-approving on timeout.
            switch decision { // Enforces the exact one-shot outcome.
            case .decision(.allowOnce): break // Continues only for this exact invocation.
            case .decision(.deny): return failure(tool: invocation.toolName, risk: risk, error: EngineeringRuntimeError.approvalDenied, startNanoseconds: start) // Returns denial as a structured tool result.
            case .timedOut: return failure(tool: invocation.toolName, risk: risk, error: EngineeringRuntimeError.approvalTimedOut(approvalTimeoutMilliseconds), startNanoseconds: start) // Returns safe timeout denial.
            } // Ends approval enforcement.
        } // Ends external-side-effect approval.
        do { // Executes only the now-authorized typed operation.
            try Task.checkCancellation() // Prevents a cancelled approval wait from authorizing a late mutation.
            switch invocation { // Routes all filesystem access through EngineeringWorkspace and all processes through the owned runner.
            case let .listDirectory(path): // Handles bounded direct directory inspection.
                let entries = try await workspace.listDirectory(relativePath: path) // Applies canonical containment and visibility policy.
                return success(tool: .listDirectory, risk: risk, summary: "Listed \(entries.count) visible item(s).", directoryEntries: entries, startNanoseconds: start) // Returns structured metadata only.
            case let .readFile(path, startLine, endLine): // Handles bounded UTF-8 source reading.
                let read = try await workspace.readFile(relativePath: path, startLine: startLine, endLine: endLine) // Applies binary refusal, redaction, line selection, and hashing.
                let suffix = read.wasTruncated ? "\n[read_file output truncated]" : "" // Makes omitted source explicit.
                return success(tool: .readFile, risk: risk, summary: "Read \(read.relativePath) (\(read.totalByteCount) bytes, SHA-256 \(read.sha256)).", text: read.text + suffix, startNanoseconds: start) // Returns bounded model-safe text and exact state evidence.
            case let .writeFile(path, content, expectedSHA256): // Handles optimistic atomic overwrite.
                let change = try await workspace.writeFile(relativePath: path, content: content, expectedSHA256: expectedSHA256) // Creates exact durable rollback state before mutation.
                let diff = try await workspace.unifiedDiff(changeID: change.id) // Produces immediate review evidence.
                return success(tool: .writeFile, risk: risk, summary: "Updated \(change.relativePath) atomically.", text: diff, change: change, startNanoseconds: start) // Returns transaction and diff.
            case let .replaceInFile(path, oldText, newText, expectedOccurrences, expectedSHA256): // Handles scoped deterministic replacement.
                let change = try await workspace.replaceInFile(relativePath: path, oldText: oldText, newText: newText, expectedOccurrences: expectedOccurrences, expectedSHA256: expectedSHA256) // Refuses ambiguous or stale input.
                let diff = try await workspace.unifiedDiff(changeID: change.id) // Produces reviewable app-owned change output.
                return success(tool: .replaceInFile, risk: risk, summary: "Replaced \(expectedOccurrences) occurrence(s) in \(change.relativePath).", text: diff, change: change, startNanoseconds: start) // Returns exact transaction evidence.
            case let .createFile(path, content, createParentDirectories): // Handles non-overwriting file creation.
                let change = try await workspace.createFile(relativePath: path, content: content, createParentDirectories: createParentDirectories) // Creates only a contained visible UTF-8 file.
                let diff = try await workspace.unifiedDiff(changeID: change.id) // Produces immediate creation diff.
                return success(tool: .createFile, risk: risk, summary: "Created \(change.relativePath).", text: diff, change: change, startNanoseconds: start) // Returns app-owned transaction evidence.
            case let .searchFiles(query, path): // Handles literal bounded filename search.
                let matches = try await workspace.searchFiles(query: query, relativePath: path) // Applies safe recursive exclusions and candidate bounds.
                return success(tool: .searchFiles, risk: risk, summary: "Found \(matches.count) filename match(es).", matches: matches, startNanoseconds: start) // Returns structured contained paths.
            case let .searchText(query, path): // Handles literal bounded source search.
                let matches = try await workspace.searchText(query: query, relativePath: path) // Skips binary, hidden, sensitive, generated, and symlink candidates.
                return success(tool: .searchText, risk: risk, summary: "Found \(matches.count) text match(es).", matches: matches, startNanoseconds: start) // Returns bounded redacted excerpts.
            case let .fileInfo(path): // Handles safe file metadata inspection.
                let info = try await workspace.fileInfo(relativePath: path) // Applies the same canonical containment policy.
                return success(tool: .fileInfo, risk: risk, summary: "Inspected \(info.relativePath).", fileInfo: info, startNanoseconds: start) // Returns no file contents.
            case let .runCommand(command): // Handles command-aware direct process execution.
                return try await executeCommand(command, tool: .runCommand, risk: risk, startNanoseconds: start) // Uses allowlist, sanitized environment, exact PID, timeout, and bounded streams.
            case .gitStatus: // Handles stable read-only Git status.
                let command = EngineeringCommand(executable: "git", arguments: ["status", "--short", "--branch", "--untracked-files=normal"], timeoutMilliseconds: 30_000, reason: "Inspect workspace Git status") // Uses porcelain-like bounded output without mutation flags.
                return try await executeCommand(command, tool: .gitStatus, risk: risk, startNanoseconds: start) // Runs through the same deterministic process boundary.
            case .gitDiff: // Handles stable read-only Git changes.
                let command = EngineeringCommand(executable: "git", arguments: ["diff", "--no-ext-diff", "--"], timeoutMilliseconds: 30_000, reason: "Inspect workspace Git diff") // Disables external diff executables and ends option parsing.
                return try await executeCommand(command, tool: .gitDiff, risk: risk, startNanoseconds: start) // Runs through owned bounded process execution.
            case let .gitLog(limit): // Handles bounded read-only Git history.
                let boundedLimit = min(100, max(1, limit)) // Prevents unbounded history output.
                let command = EngineeringCommand(executable: "git", arguments: ["log", "--oneline", "--decorate=no", "-n", String(boundedLimit)], timeoutMilliseconds: 30_000, reason: "Inspect bounded workspace Git history") // Uses a fixed non-executing output format.
                return try await executeCommand(command, tool: .gitLog, risk: risk, startNanoseconds: start) // Runs through the same exact child ownership.
            case let .buildProject(command): // Handles an explicit project-specific build request.
                return try await executeCommand(command, tool: .buildProject, risk: risk, startNanoseconds: start) // Preserves typed arguments and caller-selected finite build budget.
            case let .runTests(command): // Handles an explicit project-specific test request.
                return try await executeCommand(command, tool: .runTests, risk: risk, startNanoseconds: start) // Preserves typed arguments and caller-selected finite test budget.
            case let .unifiedDiff(changeID): // Handles Git-independent app-owned change inspection.
                let diff = try await workspace.unifiedDiff(changeID: changeID) // Loads only the matching transaction for this workspace.
                return success(tool: .unifiedDiff, risk: risk, summary: "Generated unified diff for change \(changeID.uuidString).", text: diff, startNanoseconds: start) // Returns bounded redacted diff output.
            case let .rollbackChange(changeID): // Handles conflict-aware reversal.
                let rollback = try await workspace.rollback(changeID: changeID) // Refuses rollback if any external change followed the agent edit.
                let diff = try await workspace.unifiedDiff(changeID: rollback.id) // Shows the exact reversal as another auditable transaction.
                return success(tool: .rollbackChange, risk: risk, summary: "Rolled back app-owned change \(changeID.uuidString).", text: diff, change: rollback, startNanoseconds: start) // Returns reversal evidence.
            } // Ends centralized invocation routing.
        } catch { // Normalizes every validation, filesystem, process, and cancellation failure.
            return failure(tool: invocation.toolName, risk: risk, error: error, startNanoseconds: start) // Returns a structured secret-safe error without crashing the agent loop.
        } // Ends tool execution recovery.
    } // Ends one centralized typed tool invocation.

    func cancel() async { // Stops only work currently owned by this runtime.
        await processRunner.cancel() // Terminates the exact app-launched child and never uses a generic process name.
    } // Ends runtime cancellation.

    func activeProcessID() async -> Int32? { // Exposes exact process identity for task status and deterministic cleanup tests.
        await processRunner.activeProcessID() // Returns only the runner's currently owned PID.
    } // Ends process-identity access.

    private func riskForInvocation(_ invocation: EngineeringToolInvocation) async throws -> EngineeringToolRisk { // Computes final risk from typed semantics and command structure.
        switch invocation { // Separates safe reads, contained mutations, and command-aware behavior.
        case .listDirectory, .readFile, .searchFiles, .searchText, .fileInfo, .gitStatus, .gitDiff, .gitLog, .unifiedDiff: return .safeReadOnly // Allows bounded non-mutating tools without approval.
        case .writeFile, .replaceInFile, .createFile, .rollbackChange: return .workspaceMutation // Allows normal contained app-tracked writes in autonomous mode.
        case let .runCommand(command), let .buildProject(command), let .runTests(command): // Applies executable and subcommand-aware risk classification.
            return try EngineeringCommandPolicy.assess(command).risk // Returns the deterministic policy outcome.
        } // Ends typed risk selection.
    } // Ends invocation risk classification.

    private func executeCommand(_ command: EngineeringCommand, tool: EngineeringToolName, risk: EngineeringToolRisk, startNanoseconds: UInt64) async throws -> EngineeringToolResult { // Launches one already-authorized direct command through exact process ownership.
        let assessment = try EngineeringCommandPolicy.assess(command) // Revalidates executable and argument policy immediately before launch.
        guard assessment.risk != .blocked else { throw EngineeringRuntimeError.commandBlocked(EngineeringCommandPolicy.display(command)) } // Prevents a stale classification from bypassing unconditional blocks.
        let cwd = try await workspace.resolveWorkingDirectory(command.workingDirectory) // Applies canonical path and symlink containment to Process cwd.
        try prepareSanitizedRuntimeDirectory() // Creates only per-runtime HOME and temporary storage.
        let environment = EngineeringSanitizedEnvironment.make(runtimeDirectoryURL: runtimeDirectoryURL) // Builds a small deterministic environment with no inherited keys or tokens.
        let outputLimit = workspace.limits.maximumProcessOutputBytes // Reads the configured per-stream bound.
        let process = try await processRunner.run(executableURL: assessment.executableURL, arguments: command.arguments, workingDirectoryURL: cwd, workspaceRootURL: workspace.rootURL, runtimeDirectoryURL: runtimeDirectoryURL, environment: environment, timeoutMilliseconds: command.timeoutMilliseconds, outputLimitBytes: outputLimit) // Constrains the approved command and descendants to the canonical workspace plus narrow platform exceptions.
        let combined = [process.standardOutput, process.standardError].filter { !$0.isEmpty }.joined(separator: process.standardOutput.isEmpty || process.standardError.isEmpty ? "" : "\n[stderr]\n") // Creates a bounded display form while retaining structured streams in process evidence.
        let summary = "Command exited \(process.terminationStatus) in \(process.durationMilliseconds) ms (PID \(process.processID))." // Reports exact process and duration evidence.
        return EngineeringToolResult(tool: tool, risk: risk, succeeded: process.terminationStatus == 0, summary: EngineeringSecretRedactor.redact(summary), text: EngineeringSecretRedactor.redact(combined), errorCode: process.terminationStatus == 0 ? nil : "nonzero_exit", directoryEntries: [], matches: [], fileInfo: nil, change: nil, process: process, durationMilliseconds: elapsedMilliseconds(since: startNanoseconds)) // Preserves structured evidence while accurately classifying nonzero command exits.
    } // Ends deterministic process execution.

    private func prepareSanitizedRuntimeDirectory() throws { // Creates an isolated HOME and TMPDIR without reading user configuration or credentials.
        try fileManager.createDirectory(at: runtimeDirectoryURL.appendingPathComponent("home", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) // Creates owner-only runtime HOME and new parent directories.
        try fileManager.createDirectory(at: runtimeDirectoryURL.appendingPathComponent("tmp", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) // Creates owner-only private temporary storage without granting access to host-global /tmp.
    } // Ends sanitized runtime-directory setup.

    private func reason(for invocation: EngineeringToolInvocation) -> String { // Produces the exact bounded rationale shown by approval UI.
        switch invocation { // Selects provider-independent reason metadata.
        case let .runCommand(command), let .buildProject(command), let .runTests(command): return String(command.reason.prefix(500)) // Uses the typed caller reason with a display bound.
        default: return "Engineering tool request" // Supplies a safe fallback for future externally classified tools.
        } // Ends approval-reason selection.
    } // Ends approval rationale construction.

    private func displayText(for invocation: EngineeringToolInvocation) -> String { // Produces trace-safe invocation text without exposing authored file contents.
        switch invocation { // Avoids serializing provider dictionaries or secret-bearing content.
        case let .runCommand(command), let .buildProject(command), let .runTests(command): return EngineeringCommandPolicy.display(command) // Shows executable and individually escaped arguments.
        case let .writeFile(path, content, expectedSHA256): return "write_file \(path)\nExpected SHA-256: \(expectedSHA256)\n\(Self.editPreview(content))" // Identifies the exact target, optimistic precondition, and bounded proposed content.
        case let .replaceInFile(path, oldText, newText, count, expectedSHA256): return "replace_in_file \(path)\nExpected SHA-256: \(expectedSHA256); occurrences: \(count)\nFROM: \(Self.editPreview(oldText))\nTO: \(Self.editPreview(newText))" // Makes the proposed replacement inspectable before granting authority.
        case let .createFile(path, content, parents): return "create_file \(path); create parents: \(parents)\n\(Self.editPreview(content))" // Identifies creation scope without silently replacing existing files.
        case let .rollbackChange(changeID): return "rollback_change \(changeID.uuidString)" // Identifies the exact app-owned transaction to reverse.
        default: return invocation.toolName.rawValue // Shows only the stable tool name for file operations.
        } // Ends invocation display selection.
    } // Ends safe display rendering.

    private static func editPreview(_ content: String) -> String { // Bounds approval content while retaining an exact fingerprint.
        let hash = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined() // Fingerprints all proposed bytes even when the preview is truncated.
        return "SHA-256: \(hash); \(content.utf8.count) bytes\n" + EngineeringSecretRedactor.redact(String(content.prefix(2_000))) + (content.count > 2_000 ? "\n[Preview truncated]" : "") // Marks truncation explicitly and removes credential-like text.
    } // Ends bounded edit approval rendering.

    private func success(tool: EngineeringToolName, risk: EngineeringToolRisk, summary: String, text: String? = nil, directoryEntries: [EngineeringDirectoryEntry] = [], matches: [EngineeringTextMatch] = [], fileInfo: EngineeringFileInfo? = nil, change: EngineeringChangeRecord? = nil, process: EngineeringProcessResult? = nil, startNanoseconds: UInt64) -> EngineeringToolResult { // Builds a normalized successful result.
        EngineeringToolResult(tool: tool, risk: risk, succeeded: true, summary: EngineeringSecretRedactor.redact(summary), text: text.map(EngineeringSecretRedactor.redact), errorCode: nil, directoryEntries: directoryEntries, matches: matches, fileInfo: fileInfo, change: change, process: process, durationMilliseconds: elapsedMilliseconds(since: startNanoseconds)) // Preserves structured evidence and redacts every free-text field.
    } // Ends success normalization.

    private func failure(tool: EngineeringToolName, risk: EngineeringToolRisk, error: Error, startNanoseconds: UInt64) -> EngineeringToolResult { // Builds a normalized structured failure result.
        let runtimeError = error as? EngineeringRuntimeError // Extracts a stable error identity when available.
        let code = runtimeError.map(Self.errorCode) ?? String(describing: type(of: error)) // Avoids provider-specific dictionaries while retaining machine-readable classification.
        let message = EngineeringSecretRedactor.redact((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) // Removes likely secrets from every diagnostic.
        return EngineeringToolResult(tool: tool, risk: risk, succeeded: false, summary: message, text: nil, errorCode: code, directoryEntries: [], matches: [], fileInfo: nil, change: nil, process: nil, durationMilliseconds: elapsedMilliseconds(since: startNanoseconds)) // Returns a complete failure shape without partial untrusted output.
    } // Ends failure normalization.

    private func elapsedMilliseconds(since start: UInt64) -> Int { // Measures total tool latency monotonically.
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Converts nanoseconds to integer milliseconds for trace stability.
    } // Ends duration measurement.

    private static func errorCode(_ error: EngineeringRuntimeError) -> String { // Maps associated-value errors to stable machine-readable categories.
        switch error { // Selects a compact code without leaking associated values.
        case .workspaceUnavailable: return "workspace_unavailable" // Maps unavailable root access.
        case .invalidRelativePath: return "invalid_relative_path" // Maps lexical traversal denial.
        case .pathEscapesWorkspace: return "path_escape" // Maps canonical or symlink escape denial.
        case .hiddenOrSensitivePath: return "sensitive_path" // Maps secret-path policy denial.
        case .unsupportedBinaryFile: return "unsupported_binary" // Maps text-channel refusal.
        case .fileNotFound: return "file_not_found" // Maps absent target.
        case .fileAlreadyExists: return "file_exists" // Maps create collision.
        case .notAFile: return "not_a_file" // Maps unsupported file target.
        case .notADirectory: return "not_a_directory" // Maps unsupported directory target.
        case .inputTooLarge: return "input_too_large" // Maps mutation size refusal.
        case .outputLimitExceeded: return "output_limit" // Maps inspection/history bound refusal.
        case .expectedHashConflict: return "hash_conflict" // Maps optimistic concurrency failure.
        case .replacementCountMismatch: return "replacement_count_mismatch" // Maps ambiguous replacement refusal.
        case .changeNotFound: return "change_not_found" // Maps missing transaction.
        case .changeBelongsToAnotherWorkspace: return "wrong_workspace" // Maps cross-workspace rollback refusal.
        case .rollbackConflict: return "rollback_conflict" // Maps external post-edit preservation.
        case .commandNotAllowed: return "command_not_allowed" // Maps deterministic allowlist refusal.
        case .commandBlocked: return "command_blocked" // Maps unconditional destructive-command denial.
        case .approvalDenied: return "approval_denied" // Maps user/default refusal.
        case .approvalTimedOut: return "approval_timeout" // Maps bounded UI expiry.
        case .executableMissing: return "executable_missing" // Maps unavailable allowed host tool.
        case .processLaunchFailed: return "process_launch_failed" // Maps direct Process launch failure.
        case .processTimedOut: return "process_timeout" // Maps exact-child deadline termination.
        case .processCancelled: return "process_cancelled" // Maps exact-child cooperative cancellation.
        case .sandboxUnavailable: return "sandbox_unavailable" // Maps a fail-closed process containment setup refusal.
        } // Ends stable error-code selection.
    } // Ends structured error mapping.
} // Ends centralized Engineering Tool Runtime.

enum EngineeringSanitizedEnvironment { // Builds command environments without inheriting host credentials or API keys.
    static func make(runtimeDirectoryURL: URL) -> [String: String] { // Returns an explicit allowlist rooted in app-owned runtime storage.
        [ // Returns only deterministic values needed by supported command-line tools.
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", // Allows fixed common tool locations without exposing environment secrets.
            "HOME": runtimeDirectoryURL.appendingPathComponent("home", isDirectory: true).path, // Prevents Git and package tools from reading the user's real HOME credentials.
            "TMPDIR": runtimeDirectoryURL.appendingPathComponent("tmp", isDirectory: true).path, // Constrains ordinary temporary output to app-owned storage.
            "LANG": "en_US.UTF-8", // Requests stable UTF-8 process output.
            "LC_ALL": "en_US.UTF-8", // Stabilizes locale-sensitive tool formatting.
            "GIT_TERMINAL_PROMPT": "0", // Prevents a child from hanging on credential prompts.
            "GIT_CONFIG_NOSYSTEM": "1", // Prevents system Git configuration from injecting external executables.
            "GIT_PAGER": "cat", // Prevents interactive pager child processes.
            "PAGER": "cat", // Prevents generic interactive pager behavior.
            "NO_COLOR": "1" // Reduces noisy escape sequences in bounded model-visible output.
        ] // Ends explicit sanitized environment values.
    } // Ends sanitized environment construction.
} // Ends command environment safety.

struct EngineeringCommandAssessment: Equatable, Sendable { // Carries deterministic executable resolution and risk classification.
    let executableURL: URL // Identifies the exact known executable launched directly.
    let risk: EngineeringToolRisk // Reports command/subcommand-aware risk.
} // Ends command policy output.

enum EngineeringCommandPolicy { // Validates direct command structure without interpreting natural language or invoking a shell.
    private static let blockedExecutables: Set<String> = ["sh", "bash", "zsh", "fish", "csh", "tcsh", "sudo", "doas", "su", "rm", "rmdir", "shred", "dd", "mkfs", "diskutil", "kill", "pkill", "killall", "shutdown", "reboot", "halt", "launchctl", "security"] // Blocks shell evaluation, destructive filesystem/process/system commands, and credential tooling.
    private static let allowedLocations: [String: [String]] = [ // Maps supported executable names to fixed host locations only.
        "echo": ["/bin/echo", "/usr/bin/echo"], // Supports injection-as-data verification and simple diagnostics.
        "printf": ["/usr/bin/printf"], // Supports deterministic bounded fixture output.
        "pwd": ["/bin/pwd", "/usr/bin/pwd"], // Supports safe contained cwd inspection.
        "sleep": ["/bin/sleep"], // Supports bounded timeout and cancellation behavior.
        "true": ["/usr/bin/true"], // Supports deterministic successful command fixtures.
        "false": ["/usr/bin/false"], // Supports deterministic nonzero-exit fixtures.
        "git": ["/usr/bin/git"], // Supports typed read-only Git tools and explicitly approved commit/push.
        "xcodebuild": ["/usr/bin/xcodebuild"], // Supports explicit Xcode build and test execution.
        "xcrun": ["/usr/bin/xcrun"], // Supports explicit Apple toolchain dispatch without a shell.
        "swift": ["/usr/bin/swift"], // Supports explicit SwiftPM build and tests.
        "make": ["/usr/bin/make"], // Supports bounded workspace builds.
        "curl": ["/usr/bin/curl"], // Supports explicitly approved response-only network access.
        "npm": ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], // Supports explicitly approved package commands or workspace test scripts.
        "pnpm": ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"], // Supports explicitly approved package commands or workspace test scripts.
        "yarn": ["/opt/homebrew/bin/yarn", "/usr/local/bin/yarn"], // Supports explicitly approved package commands or workspace test scripts.
        "brew": ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] // Supports only explicitly approved external package management.
    ] // Ends fixed executable allowlist.

    static func assess(_ command: EngineeringCommand) throws -> EngineeringCommandAssessment { // Resolves an exact executable and classifies arguments before any process launch.
        let suppliedName = URL(fileURLWithPath: command.executable).lastPathComponent.lowercased() // Extracts a stable basename without executing PATH lookup.
        if blockedExecutables.contains(suppliedName) { throw EngineeringRuntimeError.commandBlocked(display(command)) } // Refuses destructive and shell commands without approval bypass.
        guard let candidatePaths = allowedLocations[suppliedName] else { throw EngineeringRuntimeError.commandNotAllowed(command.executable) } // Refuses unknown binaries and interpreters.
        let resolvedCandidates = candidatePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() } // Canonicalizes fixed known host locations.
        let executableURL: URL // Stores the exact allowed executable selected for launch.
        if (command.executable as NSString).isAbsolutePath { // Validates an explicit path against canonical fixed locations.
            let suppliedURL = URL(fileURLWithPath: command.executable).standardizedFileURL.resolvingSymlinksInPath() // Canonicalizes the caller path.
            guard resolvedCandidates.contains(suppliedURL) else { throw EngineeringRuntimeError.commandNotAllowed(command.executable) } // Prevents same-basename execution from arbitrary workspace or external paths.
            executableURL = suppliedURL // Retains the exact validated explicit binary.
        } else { // Selects the first installed fixed location for a basename request.
            executableURL = resolvedCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) ?? resolvedCandidates[0] // Preserves a deterministic missing-executable diagnostic when none exist.
        } // Ends executable resolution.
        try validateArguments(command.arguments, executableName: suppliedName) // Rejects path escapes and command-specific policy bypasses.
        let risk = try classifyRisk(executableName: suppliedName, arguments: command.arguments) // Computes safe-read, workspace, external, or blocked semantics.
        return EngineeringCommandAssessment(executableURL: executableURL, risk: risk) // Returns the complete pre-execution policy decision.
    } // Ends command assessment.

    static func display(_ command: EngineeringCommand) -> String { // Produces an escaped display form that is never used for execution.
        ([command.executable] + command.arguments).map(displayArgument).joined(separator: " ") // Preserves argument boundaries visibly for approval and trace surfaces.
    } // Ends exact command display rendering.

    private static func validateArguments(_ arguments: [String], executableName: String) throws { // Applies generic and executable-specific containment and injection defenses.
        guard arguments.count <= 256 else { throw EngineeringRuntimeError.commandNotAllowed("Too many command arguments") } // Bounds provider-controlled argument cardinality.
        for argument in arguments { // Validates each direct Process argument independently.
            guard argument.utf8.count <= 8_192, !argument.contains("\0") else { throw EngineeringRuntimeError.commandNotAllowed("Malformed or oversized command argument") } // Refuses NUL and unusually large values.
            guard !(argument as NSString).isAbsolutePath, !argument.hasPrefix("~") else { throw EngineeringRuntimeError.commandNotAllowed("Absolute or home-relative command paths are forbidden") } // Prevents explicit path authority escapes.
            let components = argument.split(separator: "/", omittingEmptySubsequences: false) // Preserves path-like traversal components.
            guard !components.contains("..") else { throw EngineeringRuntimeError.commandNotAllowed("Parent traversal in command arguments is forbidden") } // Prevents relative cwd escape even without a shell.
        } // Ends generic argument validation.
        if executableName == "git" { // Removes Git options that can select external repositories or execute arbitrary helpers.
            let forbiddenPrefixes = ["-C", "--git-dir", "--work-tree", "--config-env", "--exec-path", "--upload-pack", "--receive-pack"] // Lists direct repository-boundary and helper override options.
            guard !arguments.contains("-c"), !arguments.contains(where: { argument in forbiddenPrefixes.contains(where: { argument == $0 || argument.hasPrefix($0 + "=") }) }) else { throw EngineeringRuntimeError.commandBlocked(display(EngineeringCommand(executable: executableName, arguments: arguments))) } // Blocks configuration and executable injection.
        } // Ends Git-specific boundary validation.
        if executableName == "curl" { // Keeps approved network requests response-only and bounded to captured output.
            let fileWritingOptions: Set<String> = ["-o", "--output", "-O", "--remote-name", "--output-dir", "-K", "--config"] // Lists options that could write or load configuration beyond tool-managed streams.
            guard arguments.allSatisfy({ argument in !fileWritingOptions.contains(argument) && !fileWritingOptions.contains(where: { option in argument.hasPrefix(option + "=") }) }) else { throw EngineeringRuntimeError.commandBlocked("curl file-writing and config options are blocked") } // Prevents network tools from bypassing transaction history or reading config files.
        } // Ends curl-specific safety.
    } // Ends command argument validation.

    private static func classifyRisk(executableName: String, arguments: [String]) throws -> EngineeringToolRisk { // Applies subcommand-aware risk without relying only on raw string prefixes.
        if executableName == "curl" || executableName == "brew" { return .externalSideEffect } // Requires approval for network and host package management.
        if ["npm", "pnpm", "yarn"].contains(executableName) { // Distinguishes local test scripts from dependency or publication changes.
            let subcommand = arguments.first(where: { !$0.hasPrefix("-") })?.lowercased() ?? "" // Extracts the first structural package-manager action.
            if ["test", "run", "exec"].contains(subcommand) { return .workspaceMutation } // Allows ordinary workspace scripts under deterministic process bounds.
            return .externalSideEffect // Requires approval for install, update, publish, login, and unknown package actions.
        } // Ends package-manager classification.
        if executableName == "git" { // Classifies Git by its first structural subcommand.
            let subcommand = arguments.first(where: { !$0.hasPrefix("-") })?.lowercased() ?? "" // Ignores global presentation flags after unsafe options were rejected.
            if ["status", "diff", "log", "show", "rev-parse", "ls-files"].contains(subcommand) { return .safeReadOnly } // Allows bounded repository inspection only.
            if subcommand == "commit" { // Allows explicit commit only without history rewriting.
                guard !arguments.contains("--amend"), !arguments.contains("--fixup"), !arguments.contains("--squash") else { throw EngineeringRuntimeError.commandBlocked("Git history rewriting is blocked") } // Enforces the no-history-rewrite requirement.
                return .externalSideEffect // Requires an explicit allow-once decision for commit.
            } // Ends commit classification.
            if subcommand == "push" { // Allows explicit push only without force or deletion semantics.
                guard !arguments.contains(where: { $0 == "--force" || $0 == "-f" || $0.hasPrefix("--force-with-lease") || $0 == "--delete" || $0.hasPrefix("+") }) else { throw EngineeringRuntimeError.commandBlocked("Force or deleting Git push is blocked") } // Prevents remote history destruction.
                return .externalSideEffect // Always requires explicit user approval for push.
            } // Ends push classification.
            if ["fetch", "pull", "clone", "remote", "submodule"].contains(subcommand) { return .externalSideEffect } // Requires approval for network or remote configuration effects.
            if ["reset", "clean", "rebase", "checkout", "switch", "restore", "merge", "cherry-pick", "revert", "gc", "reflog"].contains(subcommand) { throw EngineeringRuntimeError.commandBlocked("Potentially destructive Git mutation is blocked") } // Prevents untracked deletion and history/worktree rewrites outside file transactions.
            if ["add", "mv"].contains(subcommand) { return .workspaceMutation } // Allows bounded repository-index or contained move work without external effect.
            throw EngineeringRuntimeError.commandNotAllowed("Unsupported Git subcommand: \(subcommand)") // Defaults unknown Git behavior to denial.
        } // Ends Git classification.
        if executableName == "swift" { // Distinguishes package network/update commands from ordinary builds and tests.
            let lowerArguments = arguments.map { $0.lowercased() } // Normalizes structural SwiftPM tokens.
            if lowerArguments.contains("resolve") || lowerArguments.contains("update") || lowerArguments.contains("package-registry") { return .externalSideEffect } // Requires approval for dependency resolution or registry access.
            return lowerArguments.contains("build") || lowerArguments.contains("test") || lowerArguments.contains("package") ? .workspaceMutation : .safeReadOnly // Classifies known build artifacts accurately.
        } // Ends Swift classification.
        if ["xcodebuild", "xcrun", "make"].contains(executableName) { return .workspaceMutation } // Treats compiler and build-system output as contained mutation.
        return .safeReadOnly // Allows fixed diagnostic primitives such as echo, printf, pwd, sleep, true, and false.
    } // Ends command risk classification.

    private static func displayArgument(_ argument: String) -> String { // Renders one argument for human review without creating an executable shell string.
        guard !argument.isEmpty else { return "''" } // Makes an empty argument visible.
        let safeScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./:=+-,@%")) // Defines characters that need no visual quoting.
        if argument.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) { return argument } // Leaves simple arguments readable.
        return "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'" // Quotes special characters only for display; Process still receives the original argument directly.
    } // Ends approval-display escaping.
} // Ends deterministic command safety policy.

private enum EngineeringApprovalRaceResult: Sendable { // Represents the first bounded approval or timeout event.
    case decision(EngineeringApprovalDecision) // Carries an explicit provider answer.
    case timedOut // Carries deadline expiry with no implicit authorization.
} // Ends approval race outcomes.

private enum EngineeringApprovalRace { // Resolves approval without waiting indefinitely for a dismissed UI continuation.
    static func resolve(provider: any EngineeringApprovalProviding, request: EngineeringApprovalRequest, timeoutMilliseconds: Int) async -> EngineeringApprovalRaceResult { // Races an unstructured provider task against a finite deadline.
        let gate = EngineeringApprovalResolutionGate() // Creates a single-resolution concurrency bridge.
        let decisionTask = Task { // Starts the injected async approval request without blocking the runtime actor.
            let decision = await provider.decision(for: request) // Awaits UI or deterministic provider behavior.
            gate.resolve(.decision(decision)) // Publishes only if timeout has not already won.
        } // Ends provider task.
        let timeoutTask = Task { // Starts an independent finite deadline.
            try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMilliseconds)) * 1_000_000) // Waits without blocking a thread.
            gate.resolve(.timedOut) // Safely denies when no decision arrived.
        } // Ends timeout task.
        let result = await withTaskCancellationHandler(operation: { await gate.wait() }, onCancel: { // Links Stop to the unstructured approval race without waiting for its timeout.
            gate.resolve(.decision(.deny)) // Closes the authorization gate immediately on cancellation.
            decisionTask.cancel() // Cancels only this request's provider continuation.
            timeoutTask.cancel() // Releases only this request's deadline task.
        }) // Ends prompt cancellation of an exact pending approval.
        decisionTask.cancel() // Requests cooperative cleanup of a still-pending provider task.
        timeoutTask.cancel() // Cancels an unused deadline after an explicit decision.
        return result // Returns the exact first event.
    } // Ends bounded approval resolution.
} // Ends approval timeout orchestration.

private final class EngineeringApprovalResolutionGate: @unchecked Sendable { // Bridges two racing tasks into one continuation without structured-concurrency tail blocking.
    private let lock = NSLock() // Serializes result and continuation state.
    private var result: EngineeringApprovalRaceResult? // Stores a result that arrives before wait registration.
    private var continuation: CheckedContinuation<EngineeringApprovalRaceResult, Never>? // Stores the sole runtime waiter.

    func wait() async -> EngineeringApprovalRaceResult { // Awaits the first explicit decision or timeout.
        await withCheckedContinuation { continuation in // Registers a nonthrowing Swift continuation.
            lock.lock() // Begins exclusive gate inspection.
            if let result { // Handles a very fast provider or timeout.
                lock.unlock() // Releases the lock before continuation resume.
                continuation.resume(returning: result) // Returns the stored first event.
                return // Ends immediate resolution.
            } // Ends early-result handling.
            self.continuation = continuation // Stores the sole waiter.
            lock.unlock() // Ends exclusive registration.
        } // Ends approval bridge.
    } // Ends approval wait.

    func resolve(_ proposed: EngineeringApprovalRaceResult) { // Publishes only the first racing result.
        lock.lock() // Begins exclusive winner selection.
        guard result == nil else { lock.unlock(); return } // Ignores late allow decisions after safe timeout denial.
        result = proposed // Stores the winning event.
        let continuation = self.continuation // Captures a registered waiter if present.
        self.continuation = nil // Clears the waiter before resume.
        lock.unlock() // Ends exclusive winner selection.
        continuation?.resume(returning: proposed) // Resumes outside the lock exactly once.
    } // Ends approval-race resolution.
} // Ends approval single-resolution gate.
