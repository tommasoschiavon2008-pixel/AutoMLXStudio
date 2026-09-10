import Foundation // Supplies durable identifiers, dates, URLs, byte buffers, and localized errors.

struct EngineeringWorkspaceDescriptor: Codable, Equatable, Identifiable, Sendable { // Describes one explicitly user-authorized live engineering directory.
    let id: UUID // Stores a stable workspace identity independent of its display name.
    var displayName: String // Stores the human-readable name shown by workspace selectors.
    let rootPath: String // Stores a restart-safe fallback path for the current unsandboxed build.
    var securityScopedBookmark: Data? // Stores macOS security-scoped authorization when bookmark creation succeeds.
    var associatedProjectID: UUID? // Optionally links knowledge retrieval without merging the two storage concepts.
    let createdAt: Date // Records when the user first authorized this workspace.
    var lastOpenedAt: Date // Records the latest successful access for deterministic recency sorting.
} // Ends the persisted Engineering Workspace descriptor.

struct EngineeringWorkspaceLimits: Equatable, Sendable { // Centralizes conservative bounds applied before data reaches a model.
    var maximumReadBytes: Int = 262_144 // Limits one text-file response to 256 KiB by default.
    var maximumWriteBytes: Int = 1_048_576 // Limits one app-authored file state to one MiB by default.
    var maximumDirectoryEntries: Int = 500 // Prevents a directory tool from dumping an unbounded tree.
    var maximumSearchFiles: Int = 2_000 // Bounds the number of candidate files inspected by one search.
    var maximumSearchMatches: Int = 200 // Bounds filenames or text matches returned to the agent.
    var maximumProcessOutputBytes: Int = 262_144 // Bounds each captured process stream to 256 KiB.
    var maximumDiffBytes: Int = 262_144 // Bounds an emitted unified diff to 256 KiB.

    static let standard = EngineeringWorkspaceLimits() // Provides one production default shared across the runtime.
} // Ends workspace and output limits.

enum EngineeringToolRisk: String, Codable, CaseIterable, Sendable { // Classifies every tool action before it is executed.
    case safeReadOnly = "SafeReadOnly" // Identifies bounded operations that cannot intentionally mutate workspace state.
    case workspaceMutation = "WorkspaceMutation" // Identifies contained writes that autonomous mode may perform normally.
    case externalSideEffect = "ExternalSideEffect" // Identifies network, package, commit, or push work requiring approval.
    case blocked = "Blocked" // Identifies unsafe operations that the runtime will never execute.
} // Ends tool-risk categories.

enum EngineeringToolName: String, Codable, CaseIterable, Sendable { // Gives every centralized tool a stable provider-facing function name.
    case listDirectory = "list_directory" // Names bounded direct directory inspection.
    case readFile = "read_file" // Names bounded UTF-8 text reading.
    case writeFile = "write_file" // Names atomic replacement with expected-hash conflict detection.
    case replaceInFile = "replace_in_file" // Names deterministic exact-text replacement.
    case createFile = "create_file" // Names non-overwriting file creation.
    case searchFiles = "search_files" // Names bounded filename-oriented search.
    case searchText = "search_text" // Names bounded textual-content search.
    case fileInfo = "file_info" // Names metadata and content-hash inspection.
    case runCommand = "run_command" // Names direct executable-plus-arguments process execution.
    case gitStatus = "git_status" // Names read-only Git worktree status.
    case gitDiff = "git_diff" // Names read-only Git unified diff output.
    case gitLog = "git_log" // Names bounded read-only Git history output.
    case buildProject = "build_project" // Names an explicit higher-level build command.
    case runTests = "run_tests" // Names an explicit higher-level test command.
    case unifiedDiff = "unified_diff" // Names session-local change inspection without requiring Git.
    case rollbackChange = "rollback_change" // Names conflict-aware reversal of one app-owned change.
} // Ends stable tool names.

struct EngineeringToolDefinition: Equatable, Sendable { // Exposes a compact typed function declaration to model backends.
    let name: EngineeringToolName // Supplies the stable function identifier.
    let summary: String // Explains the bounded capability without exposing application internals.
    let requiredArguments: [String] // Lists fields that a provider decoder must validate before invocation.
    let defaultRisk: EngineeringToolRisk // Supplies the baseline risk before command-specific classification.
} // Ends one provider-independent tool definition.

struct EngineeringCommand: Equatable, Sendable { // Represents deterministic process execution without shell interpolation.
    let executable: String // Stores an allowlisted executable name or canonical executable path.
    let arguments: [String] // Stores each argument as an independent byte-safe Process value.
    let workingDirectory: String // Stores a workspace-relative current directory.
    let timeoutMilliseconds: Int // Stores a finite command deadline.
    let reason: String // Stores a user-visible explanation for approval and trace surfaces.

    init(executable: String, arguments: [String] = [], workingDirectory: String = "", timeoutMilliseconds: Int = 120_000, reason: String = "Engineering command") { // Builds a normalized direct-process request.
        self.executable = executable // Preserves the exact executable requested for later allowlist resolution.
        self.arguments = arguments // Preserves argument boundaries so punctuation cannot become shell syntax.
        self.workingDirectory = workingDirectory // Preserves the contained relative working directory request.
        self.timeoutMilliseconds = max(1, timeoutMilliseconds) // Guarantees every command has a positive deadline.
        self.reason = reason // Preserves the concise approval rationale.
    } // Ends deterministic command construction.
} // Ends direct process metadata.

enum EngineeringToolInvocation: Sendable { // Carries validated typed arguments rather than provider-specific dictionaries.
    case listDirectory(path: String) // Requests one non-recursive bounded directory listing.
    case readFile(path: String, startLine: Int?, endLine: Int?) // Requests bounded text and an optional inclusive one-based line range.
    case writeFile(path: String, content: String, expectedSHA256: String) // Requests atomic overwrite only from the expected state.
    case replaceInFile(path: String, oldText: String, newText: String, expectedOccurrences: Int, expectedSHA256: String) // Requests deterministic replacement from an expected state.
    case createFile(path: String, content: String, createParentDirectories: Bool) // Requests creation that never silently overwrites.
    case searchFiles(query: String, path: String) // Requests bounded case-insensitive filename matching.
    case searchText(query: String, path: String) // Requests bounded literal text matching.
    case fileInfo(path: String) // Requests bounded metadata without exposing file contents.
    case runCommand(EngineeringCommand) // Requests one directly launched allowlisted executable.
    case gitStatus // Requests porcelain Git status from the workspace root.
    case gitDiff // Requests bounded Git diff output from the workspace root.
    case gitLog(limit: Int) // Requests a bounded oneline Git history.
    case buildProject(EngineeringCommand) // Requests an explicit deterministic build command.
    case runTests(EngineeringCommand) // Requests an explicit deterministic test command.
    case unifiedDiff(changeID: UUID) // Requests the stored before/after diff for one app-owned transaction.
    case rollbackChange(changeID: UUID) // Requests conflict-aware rollback of one app-owned transaction.

    var toolName: EngineeringToolName { // Maps each typed invocation to its stable provider-facing identifier.
        switch self { // Selects the identifier without inspecting untrusted string arguments.
        case .listDirectory: return .listDirectory // Maps directory inspection.
        case .readFile: return .readFile // Maps text-file reading.
        case .writeFile: return .writeFile // Maps atomic overwrite.
        case .replaceInFile: return .replaceInFile // Maps scoped replacement.
        case .createFile: return .createFile // Maps non-overwriting creation.
        case .searchFiles: return .searchFiles // Maps filename search.
        case .searchText: return .searchText // Maps content search.
        case .fileInfo: return .fileInfo // Maps file metadata.
        case .runCommand: return .runCommand // Maps direct command execution.
        case .gitStatus: return .gitStatus // Maps Git status.
        case .gitDiff: return .gitDiff // Maps Git diff.
        case .gitLog: return .gitLog // Maps Git history.
        case .buildProject: return .buildProject // Maps higher-level build.
        case .runTests: return .runTests // Maps higher-level tests.
        case .unifiedDiff: return .unifiedDiff // Maps session diff inspection.
        case .rollbackChange: return .rollbackChange // Maps app-owned rollback.
        } // Ends stable tool-name selection.
    } // Ends invocation-name mapping.
} // Ends typed tool invocations.

struct EngineeringDirectoryEntry: Equatable, Sendable { // Reports one safe visible child from a bounded listing.
    let relativePath: String // Stores a root-relative path suitable for a later contained tool call.
    let isDirectory: Bool // Distinguishes folders from files without reading either.
    let isSymbolicLink: Bool // Makes non-followed links explicit to the model and UI.
    let byteCount: Int? // Reports inexpensive regular-file size when available.
    let modificationDate: Date? // Reports inexpensive last-modification evidence when available.
} // Ends bounded directory entry metadata.

struct EngineeringTextMatch: Equatable, Sendable { // Reports one bounded literal search result.
    let relativePath: String // Identifies the matching visible file.
    let line: Int? // Identifies a one-based text line when content search supplied one.
    let excerpt: String // Provides a short secret-redacted contextual excerpt.
} // Ends one filename or text match.

struct EngineeringFileRead: Equatable, Sendable { // Reports one bounded text read with exact source-state evidence.
    let relativePath: String // Identifies the validated file inside the authorized root.
    let text: String // Carries decoded and conservatively secret-redacted text.
    let sha256: String // Carries the exact full-file hash used by later optimistic writes.
    let totalByteCount: Int // Reports the complete filesystem size without returning all bytes.
    let wasTruncated: Bool // Reports whether the configured byte or line selection omitted content.
} // Ends bounded file-read output.

struct EngineeringFileInfo: Equatable, Sendable { // Reports safe metadata for one contained visible path.
    let relativePath: String // Identifies the path relative to the authorized root.
    let isDirectory: Bool // Reports whether the target is a directory.
    let isSymbolicLink: Bool // Reports whether the lexical target itself is a link.
    let byteCount: Int? // Reports regular-file bytes when available.
    let modificationDate: Date? // Reports filesystem modification time when available.
    let sha256: String? // Reports a bounded regular text-file content fingerprint when available.
} // Ends file metadata.

enum EngineeringChangeKind: String, Codable, Sendable { // Identifies the mutation that produced one reversible transaction.
    case create // Identifies creation of a previously absent file.
    case write // Identifies complete atomic replacement of an existing file.
    case replace // Identifies deterministic exact-text replacement.
    case rollback // Identifies reversal of a prior app-owned transaction.
} // Ends change-operation identities.

struct EngineeringChangeRecord: Codable, Equatable, Identifiable, Sendable { // Persists exact before/after state for a bounded app-owned change.
    let id: UUID // Gives this transaction a stable rollback and diff identity.
    let workspaceID: UUID // Prevents a record from being applied to another authorized root.
    let relativePath: String // Stores only the validated root-relative target path.
    let kind: EngineeringChangeKind // Records how the new state was produced.
    let createdAt: Date // Records transaction ordering without relying on filesystem timestamps.
    let beforeData: Data? // Stores the exact bounded original bytes, with nil representing nonexistence.
    let afterData: Data? // Stores the exact bounded authored bytes, with nil reserved for future deletion support.
    let beforeSHA256: String? // Records the original state fingerprint for trace and diff surfaces.
    let afterSHA256: String? // Records the authored state fingerprint used to detect external edits before rollback.
    let parentChangeID: UUID? // Links a rollback transaction to the exact change it reverses.
} // Ends durable change history.

struct EngineeringProcessResult: Equatable, Sendable { // Reports one exact app-owned child process execution.
    let processID: Int32 // Stores the exact child PID owned by this invocation.
    let terminationStatus: Int32 // Stores the executable's actual exit status.
    let standardOutput: String // Stores bounded, malformed-UTF-8-safe, secret-redacted stdout.
    let standardError: String // Stores bounded, malformed-UTF-8-safe, secret-redacted stderr.
    let outputWasTruncated: Bool // Tells the model that not all output was retained.
    let durationMilliseconds: Int // Stores measured launch-to-exit time.
} // Ends process result evidence.

struct EngineeringToolResult: Equatable, Sendable { // Normalizes every tool outcome into one transport-independent representation.
    let tool: EngineeringToolName // Identifies the tool whose invocation completed or failed.
    let risk: EngineeringToolRisk // Reports the pre-execution risk decision.
    let succeeded: Bool // Reports whether the requested operation completed successfully.
    let summary: String // Provides one concise trace-safe outcome.
    let text: String? // Carries bounded file, diff, or command output when applicable.
    let errorCode: String? // Carries a stable structured failure category without provider dictionaries.
    let directoryEntries: [EngineeringDirectoryEntry] // Carries bounded listing results.
    let matches: [EngineeringTextMatch] // Carries bounded filename or content matches.
    let fileInfo: EngineeringFileInfo? // Carries metadata from file_info.
    let change: EngineeringChangeRecord? // Carries the exact app-owned mutation transaction.
    let process: EngineeringProcessResult? // Carries exact process evidence for terminal tools.
    let durationMilliseconds: Int // Carries total validation-and-execution duration.
} // Ends normalized tool results.

struct EngineeringApprovalRequest: Equatable, Identifiable, Sendable { // Describes one bounded external-side-effect decision for the UI.
    let id: UUID // Gives the pending prompt a stable identity.
    let tool: EngineeringToolName // Identifies the requesting tool.
    let risk: EngineeringToolRisk // Shows the classified risk explicitly.
    let exactCommand: String // Shows an escaped display form while execution retains separate arguments.
    let workspacePath: String // Shows the authorized root affected by the command.
    let reason: String // Explains why the agent requested the operation.
} // Ends user-visible approval metadata.

enum EngineeringApprovalDecision: String, Equatable, Sendable { // Limits V0.6 approval scope to one explicit choice.
    case allowOnce // Authorizes only the exact pending command invocation.
    case deny // Refuses the command without changing future policy.
} // Ends bounded approval decisions.

protocol EngineeringApprovalProviding: Sendable { // Abstracts a nonblocking UI or deterministic test approval source.
    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision // Awaits one exact decision without blocking the main thread.
} // Ends approval-provider requirements.

struct DenyEngineeringApprovalProvider: EngineeringApprovalProviding { // Provides the safe behavior when no approval UI is connected.
    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { .deny } // Never promotes an unavailable prompt into authorization.
} // Ends default-deny approval behavior.

enum EngineeringRuntimeError: LocalizedError, Equatable, Sendable { // Defines stable workspace, mutation, approval, and process failures.
    case workspaceUnavailable(String) // Reports an unavailable authorized root.
    case invalidRelativePath(String) // Reports absolute, parent-traversal, or malformed relative input.
    case pathEscapesWorkspace(String) // Reports canonical or symlink resolution outside the authorized root.
    case hiddenOrSensitivePath(String) // Reports policy denial for hidden or likely-secret paths.
    case unsupportedBinaryFile(String) // Reports a file that cannot safely enter the text-tool channel.
    case fileNotFound(String) // Reports a missing target for an operation that requires existence.
    case fileAlreadyExists(String) // Reports create_file collision without overwriting.
    case notAFile(String) // Reports a directory or unsupported filesystem object where text was required.
    case notADirectory(String) // Reports a file where a directory was required.
    case inputTooLarge(Int) // Reports authored content beyond the configured transaction bound.
    case outputLimitExceeded(Int) // Reports metadata work that cannot safely hash or inspect a large file.
    case expectedHashConflict(expected: String, actual: String?) // Reports an external edit before a write or replacement.
    case replacementCountMismatch(expected: Int, actual: Int) // Reports ambiguous or missing scoped replacement text.
    case changeNotFound(UUID) // Reports a missing app-owned transaction.
    case changeBelongsToAnotherWorkspace(UUID) // Prevents cross-workspace rollback.
    case rollbackConflict(expected: String?, actual: String?) // Preserves unrelated external edits made after the agent change.
    case commandNotAllowed(String) // Reports an executable or argument shape outside the deterministic policy.
    case commandBlocked(String) // Reports a recognized destructive command denied without prompting.
    case approvalDenied // Reports an explicit or default-deny decision.
    case approvalTimedOut(Int) // Reports bounded approval expiry without implicit authorization.
    case executableMissing(String) // Reports an allowlisted executable absent from the host.
    case processLaunchFailed(String) // Reports a bounded Foundation launch diagnostic.
    case processTimedOut(Int) // Reports termination of the exact owned child at its deadline.
    case processCancelled // Reports cooperative cancellation after exact child cleanup.

    var errorDescription: String? { // Produces concise diagnostics safe for tool traces and UI display.
        switch self { // Selects a stable human-readable description for each structured category.
        case let .workspaceUnavailable(path): return "Engineering workspace is unavailable: \(path)" // Describes missing authorization root access.
        case let .invalidRelativePath(path): return "Path must be a normalized workspace-relative path: \(path)" // Describes lexical traversal denial.
        case let .pathEscapesWorkspace(path): return "Resolved path escapes the authorized workspace: \(path)" // Describes canonical containment denial.
        case let .hiddenOrSensitivePath(path): return "Hidden or sensitive path is not available to engineering text tools: \(path)" // Describes secret-path policy.
        case let .unsupportedBinaryFile(path): return "Binary or unsupported text encoding cannot be returned by read_file: \(path)" // Describes text-channel incompatibility.
        case let .fileNotFound(path): return "Workspace path does not exist: \(path)" // Describes missing targets.
        case let .fileAlreadyExists(path): return "Workspace file already exists: \(path)" // Describes safe create collision.
        case let .notAFile(path): return "Workspace path is not a regular file: \(path)" // Describes invalid file target.
        case let .notADirectory(path): return "Workspace path is not a directory: \(path)" // Describes invalid directory target.
        case let .inputTooLarge(limit): return "Requested file content exceeds the \(limit)-byte mutation limit." // Describes bounded write refusal.
        case let .outputLimitExceeded(limit): return "Requested file exceeds the \(limit)-byte safe inspection limit." // Describes bounded metadata refusal.
        case let .expectedHashConflict(expected, actual): return "File changed before mutation; expected \(expected), found \(actual ?? "missing")." // Describes optimistic-concurrency failure.
        case let .replacementCountMismatch(expected, actual): return "Replacement expected \(expected) occurrence(s) but found \(actual)." // Describes deterministic replacement refusal.
        case let .changeNotFound(id): return "Engineering change was not found: \(id.uuidString)" // Describes missing rollback history.
        case let .changeBelongsToAnotherWorkspace(id): return "Engineering change belongs to another workspace: \(id.uuidString)" // Describes workspace identity mismatch.
        case let .rollbackConflict(expected, actual): return "File changed after the agent edit; rollback expected \(expected ?? "missing"), found \(actual ?? "missing")." // Describes external-change preservation.
        case let .commandNotAllowed(command): return "Command is outside the deterministic allowlist: \(command)" // Describes unsupported process requests.
        case let .commandBlocked(command): return "Command is blocked by engineering safety policy: \(command)" // Describes destructive-command refusal.
        case .approvalDenied: return "External-side-effect command was denied." // Describes user or default refusal.
        case let .approvalTimedOut(milliseconds): return "Command approval expired after \(milliseconds) ms and was denied." // Describes bounded prompt timeout.
        case let .executableMissing(path): return "Allowed executable is unavailable: \(path)" // Describes missing host tooling.
        case let .processLaunchFailed(detail): return "Command could not start: \(detail)" // Describes direct launch failure.
        case let .processTimedOut(milliseconds): return "Owned command exceeded \(milliseconds) ms and was stopped." // Describes exact-child timeout cleanup.
        case .processCancelled: return "Owned command was cancelled and stopped." // Describes exact-child cooperative cancellation.
        } // Ends error-description selection.
    } // Ends localized diagnostics.
} // Ends structured Engineering Runtime errors.
