import Foundation // Supplies strict JSON decoding, UUID validation, bounded Unicode output, and cancellation handling.

actor EngineeringAgentToolRuntimeAdapter: EngineeringAgentToolExecuting { // Bridges provider-neutral agent calls to the concrete centralized Mac tool runtime.
    static let maximumArgumentsBytes = EngineeringAgentFallbackParser.maximumByteCount // Matches the engine's fixed 64 KiB structured-argument ceiling.
    static let maximumOutputBytes = 65_536 // Bounds one tool response before it re-enters model context.
    private let runtime: EngineeringToolRuntime // Retains the sole concrete Mac filesystem and process authority.
    private var activeOperationID: UUID? // Identifies the exact adapter invocation currently awaiting the runtime.
    private var activeSessionID: UUID? // Associates cancellation with the exact owning engineering session.

    init(runtime: EngineeringToolRuntime) { // Creates one bridge over one authorized Engineering Workspace runtime.
        self.runtime = runtime // Retains the concrete actor without duplicating filesystem access.
    } // Ends adapter construction.

    func toolDefinitions() async -> [EngineeringAgentToolDefinition] { // Converts the concrete registry into exact closed JSON schemas for model backends.
        EngineeringToolRuntime.definitions.map { definition in // Preserves the runtime's stable non-overlapping registration order.
            EngineeringAgentToolDefinition(name: definition.name.rawValue, summary: definition.summary, inputSchemaJSON: Self.schema(for: definition.name)) // Exposes only provider-neutral names, summaries, and bounded schemas.
        } // Ends registry adaptation.
    } // Ends provider-neutral tool definition access.

    func execute(_ call: EngineeringAgentToolCall, sessionID: UUID) async -> EngineeringAgentToolResult { // Strictly decodes and dispatches one exact engine-approved proposal.
        let safeCallID = Self.safeCallID(call.id) // Preserves bounded correlation without reflecting malformed identifiers.
        guard !Task.isCancelled else { return Self.cancelledResult(callID: safeCallID, summary: "Tool execution was cancelled before argument decoding.") } // Refuses to start work for an already-cancelled owner.
        let invocation: EngineeringToolInvocation // Stores only a fully schema-validated concrete invocation.
        do { // Parses exact tool identity and closed JSON schema before acquiring the active slot.
            invocation = try Self.decode(call) // Rejects prose, unknown fields, wrong types, oversized values, and unsupported tool names.
        } catch { // Returns a bounded repairable failure without echoing untrusted arguments.
            return Self.failureResult(callID: safeCallID, code: "invalid_tool_arguments", summary: Self.errorSummary(error)) // Prevents malformed model output from reaching filesystem or Process APIs.
        } // Ends strict decoding recovery.
        guard activeOperationID == nil else { // Serializes the adapter even when a caller bypasses the engine's single-session guard.
            return Self.failureResult(callID: safeCallID, code: "tool_runtime_busy", summary: "Another engineering tool operation is already active.") // Refuses ambiguous concurrent ownership.
        } // Ends adapter ownership guard.
        let operationID = UUID() // Creates an unguessable cancellation token for this exact dispatch.
        activeOperationID = operationID // Publishes adapter ownership before the concrete runtime is awaited.
        activeSessionID = sessionID // Records which engineering session may cancel this operation.
        defer { // Releases ownership only if it still belongs to this exact invocation.
            if activeOperationID == operationID { activeOperationID = nil; activeSessionID = nil } // Prevents late cleanup from erasing a future operation token.
        } // Ends exact adapter ownership cleanup.
        let concreteResult = await withTaskCancellationHandler(operation: { // Propagates parent task cancellation into the concrete runtime.
            await runtime.execute(invocation) // Performs containment, permission, approval, process, and transaction enforcement on the Mac.
        }, onCancel: { // Handles cancellation synchronously by scheduling actor-safe exact-token validation.
            Task { await self.cancelIfActive(operationID: operationID, sessionID: sessionID) } // Cancels only if this invocation still owns the adapter slot.
        }) // Ends cancellation-aware concrete dispatch.
        let ownerWasCancelled = Task.isCancelled || concreteResult.errorCode == "process_cancelled" // Preserves cancellation identity even when a completed edit returns evidence.
        return Self.adapt(concreteResult, invocation: invocation, callID: safeCallID, forceCancelled: ownerWasCancelled) // Returns bounded untrusted output plus concrete operational evidence.
    } // Ends one provider-neutral tool execution.

    func cancel(sessionID: UUID) async { // Allows an owning session controller to stop only its exact active tool operation.
        guard activeSessionID == sessionID, activeOperationID != nil else { return } // Ignores stale or cross-session cancellation requests.
        await runtime.cancel() // Delegates exact child cleanup to the centralized runtime.
    } // Ends explicit session-scoped cancellation.

    private func cancelIfActive(operationID: UUID, sessionID: UUID) async { // Rejects late task-cancellation races against a subsequent invocation.
        guard activeOperationID == operationID, activeSessionID == sessionID else { return } // Requires both exact operation and session ownership.
        await runtime.cancel() // Stops only the concrete runtime work still owned by this invocation.
    } // Ends exact-token cancellation propagation.

    private static func decode(_ call: EngineeringAgentToolCall) throws -> EngineeringToolInvocation { // Converts one closed JSON object into a typed concrete invocation.
        guard call.id == safeCallID(call.id), !call.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngineeringAgentToolAdapterError.invalidCallIdentity } // Requires a bounded exact correlation identity.
        guard let tool = EngineeringToolName(rawValue: call.name), call.name == tool.rawValue else { throw EngineeringAgentToolAdapterError.unknownTool } // Requires an exact registered name without normalization or natural-language guessing.
        let object = try EngineeringAdapterJSONObject(source: call.argumentsJSON, maximumBytes: maximumArgumentsBytes) // Parses one standalone bounded JSON object with retained scalar types.
        switch tool { // Applies one exact key and type schema per concrete tool.
        case .listDirectory: // Decodes a bounded direct directory listing.
            try object.require(required: ["path"]) // Rejects missing and additional fields.
            return .listDirectory(path: try object.string("path", maximumBytes: 4_096, mayBeEmpty: true)) // Preserves a root request only as the explicit empty relative path.
        case .readFile: // Decodes bounded UTF-8 file reading and optional line range.
            try object.require(required: ["path"], optional: ["startLine", "endLine"]) // Accepts only the two documented optional fields.
            let startLine = try object.optionalInteger("startLine", range: 1...10_000_000) // Requires a positive one-based start line when supplied.
            let endLine = try object.optionalInteger("endLine", range: 1...10_000_000) // Requires a positive one-based end line when supplied.
            if let startLine, let endLine, endLine < startLine { throw EngineeringAgentToolAdapterError.invalidValue("endLine") } // Rejects inverted ranges instead of silently broadening access.
            return .readFile(path: try object.path("path"), startLine: startLine, endLine: endLine) // Creates only the typed read invocation.
        case .writeFile: // Decodes conflict-aware complete overwrite.
            try object.require(required: ["path", "content", "expectedSHA256"]) // Requires all state and optimistic-concurrency evidence.
            return .writeFile(path: try object.path("path"), content: try object.string("content", maximumBytes: 60_000, mayBeEmpty: true), expectedSHA256: try object.sha256("expectedSHA256")) // Bounds authored text within the engine JSON ceiling.
        case .replaceInFile: // Decodes deterministic exact-text replacement.
            try object.require(required: ["path", "oldText", "newText", "expectedOccurrences", "expectedSHA256"]) // Requires a closed deterministic replacement contract.
            return .replaceInFile(path: try object.path("path"), oldText: try object.string("oldText", maximumBytes: 30_000, mayBeEmpty: false), newText: try object.string("newText", maximumBytes: 30_000, mayBeEmpty: true), expectedOccurrences: try object.integer("expectedOccurrences", range: 1...100_000), expectedSHA256: try object.sha256("expectedSHA256")) // Creates only the bounded typed replacement.
        case .createFile: // Decodes non-overwriting file creation.
            try object.require(required: ["path", "content"], optional: ["createParentDirectories"]) // Rejects overwrite flags and undocumented authority.
            return .createFile(path: try object.path("path"), content: try object.string("content", maximumBytes: 60_000, mayBeEmpty: true), createParentDirectories: try object.optionalBoolean("createParentDirectories") ?? false) // Defaults only the documented parent-creation choice.
        case .searchFiles: // Decodes literal filename search.
            try object.require(required: ["query", "path"]) // Requires one literal and one explicit relative subtree.
            return .searchFiles(query: try object.string("query", maximumBytes: 4_096, mayBeEmpty: false), path: try object.string("path", maximumBytes: 4_096, mayBeEmpty: true)) // Never interprets the query as a glob, regex, shell, or instruction.
        case .searchText: // Decodes literal content search.
            try object.require(required: ["query", "path"]) // Requires one literal and one explicit relative subtree.
            return .searchText(query: try object.string("query", maximumBytes: 4_096, mayBeEmpty: false), path: try object.string("path", maximumBytes: 4_096, mayBeEmpty: true)) // Never promotes source text into policy or command authority.
        case .fileInfo: // Decodes bounded metadata inspection.
            try object.require(required: ["path"]) // Rejects unrecognized recursive or content flags.
            return .fileInfo(path: try object.path("path")) // Creates only the contained metadata request.
        case .runCommand: // Decodes one direct executable-plus-arguments request.
            try object.require(required: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds", "reason"]) // Forbids raw command strings, shells, environment dictionaries, and extra flags.
            return .runCommand(try object.command(reasonRequired: true)) // Preserves arguments as an array and leaves structural safety policy to the runtime.
        case .gitStatus: // Decodes the fixed read-only Git status tool.
            try object.require(required: []) // Requires an exactly empty object.
            return .gitStatus // Supplies no model-controlled Git arguments.
        case .gitDiff: // Decodes the fixed read-only Git diff tool.
            try object.require(required: []) // Requires an exactly empty object.
            return .gitDiff // Supplies no model-controlled Git arguments.
        case .gitLog: // Decodes bounded fixed-format Git history.
            try object.require(required: ["limit"]) // Accepts only the requested history count.
            return .gitLog(limit: try object.integer("limit", range: 1...100)) // Enforces the same maximum as the concrete runtime.
        case .buildProject: // Decodes an explicit higher-level build command.
            try object.require(required: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds"], optional: ["reason"]) // Allows only one optional user-visible rationale.
            return .buildProject(try object.command(reasonRequired: false, defaultReason: "Build the authorized engineering workspace")) // Creates a bounded direct build request.
        case .runTests: // Decodes an explicit higher-level test command.
            try object.require(required: ["executable", "arguments", "workingDirectory", "timeoutMilliseconds"], optional: ["reason"]) // Allows only one optional user-visible rationale.
            return .runTests(try object.command(reasonRequired: false, defaultReason: "Test the authorized engineering workspace")) // Creates a bounded direct test request.
        case .unifiedDiff: // Decodes app-owned transaction inspection.
            try object.require(required: ["changeID"]) // Accepts only one stable transaction identity.
            return .unifiedDiff(changeID: try object.uuid("changeID")) // Rejects malformed or noncanonical UUID values.
        case .rollbackChange: // Decodes conflict-aware transaction reversal.
            try object.require(required: ["changeID"]) // Accepts only one stable app-owned transaction identity.
            return .rollbackChange(changeID: try object.uuid("changeID")) // Leaves workspace ownership and external-change checks to the runtime.
        } // Ends exact per-tool schema decoding.
    } // Ends tool-call decoding.

    private static func adapt(_ result: EngineeringToolResult, invocation: EngineeringToolInvocation, callID: String, forceCancelled: Bool) -> EngineeringAgentToolResult { // Maps concrete evidence into the engine's bounded provider-neutral result.
        let status: EngineeringAgentToolStatus // Stores the normalized operational outcome.
        if forceCancelled { // Gives cancellation precedence after preserving any completed mutation evidence.
            status = .cancelled // Stops the owning engine loop deterministically.
        } else if result.succeeded { // Maps concrete success directly.
            status = .succeeded // Records a completed contained operation.
        } else if result.errorCode == "process_cancelled" { // Handles runtime cancellation even if parent state raced.
            status = .cancelled // Preserves exact-child cancellation identity.
        } else if Self.denialErrorCodes.contains(result.errorCode ?? "") { // Separates policy or permission refusal from operational failure.
            status = .denied // Allows the engine to terminate with permissionDenied honestly.
        } else { // Handles filesystem conflicts, missing files, process exits, and other repairable failures.
            status = .failed // Returns a bounded operational failure for model repair.
        } // Ends status normalization.
        let output = Self.renderOutput(result) // Converts structured result evidence into bounded untrusted model data.
        let summary = Self.oneLine(EngineeringSecretRedactor.redact(result.summary), maximumBytes: 1_000) // Bounds public trace metadata independently from model output.
        let changedPaths = result.change.map { [$0.relativePath] } ?? [] // Reports only the exact app-owned transaction target.
        let exitCode = result.process.map { Int($0.terminationStatus) } // Preserves real process status only when a child ran.
        let verification = Self.verificationEvidence(invocation: invocation, result: result, summary: summary) // Creates evidence only for explicit build or test tools.
        return EngineeringAgentToolResult(callID: callID, status: status, output: output, operationalSummary: summary, durationMilliseconds: max(0, result.durationMilliseconds), exitCode: exitCode, changedPaths: changedPaths, verification: verification) // Returns complete bounded engine evidence.
    } // Ends concrete-result adaptation.

    private static func renderOutput(_ result: EngineeringToolResult) -> String { // Renders structured evidence without exposing application object representations.
        var sections: [String] = [] // Accumulates bounded human-readable data sections.
        sections.append("risk: \(result.risk.rawValue)") // Makes concrete permission classification visible as data.
        sections.append("summary: \(EngineeringSecretRedactor.redact(result.summary))") // Includes the runtime's secret-safe operational summary.
        if let errorCode = result.errorCode { sections.append("error_code: \(errorCode)") } // Includes only a stable machine-readable error code.
        if let text = result.text, !text.isEmpty { sections.append("output:\n\(EngineeringSecretRedactor.redact(text))") } // Includes bounded runtime-produced text as untrusted data.
        if !result.directoryEntries.isEmpty { // Renders safe directory metadata without Foundation descriptions.
            let lines = result.directoryEntries.map { entry in "\(entry.isDirectory ? "directory" : "file")\(entry.isSymbolicLink ? ",symlink" : "") \(entry.relativePath)\(entry.byteCount.map { " \($0) bytes" } ?? "")" } // Converts each bounded entry deterministically.
            sections.append("entries:\n" + lines.joined(separator: "\n")) // Adds the complete runtime-bounded listing.
        } // Ends directory evidence rendering.
        if !result.matches.isEmpty { // Renders safe search evidence without serializing internal objects.
            let lines = result.matches.map { match in "\(match.relativePath)\(match.line.map { ":\($0)" } ?? ""): \(EngineeringSecretRedactor.redact(match.excerpt))" } // Converts each runtime-bounded match deterministically.
            sections.append("matches:\n" + lines.joined(separator: "\n")) // Adds literal search evidence.
        } // Ends search evidence rendering.
        if let info = result.fileInfo { // Renders file metadata without source content.
            sections.append("file_info: \(info.relativePath); directory=\(info.isDirectory); symlink=\(info.isSymbolicLink); bytes=\(info.byteCount.map(String.init) ?? "unknown"); sha256=\(info.sha256 ?? "unavailable")") // Includes only typed safe metadata.
        } // Ends file metadata rendering.
        if let change = result.change { // Renders app-owned transaction identity and hashes.
            sections.append("change: \(change.id.uuidString); kind=\(change.kind.rawValue); path=\(change.relativePath); before=\(change.beforeSHA256 ?? "absent"); after=\(change.afterSHA256 ?? "absent")") // Omits stored before/after bytes because diff text is already bounded separately.
        } // Ends mutation evidence rendering.
        if let process = result.process { // Renders exact process lifecycle evidence.
            sections.append("process: pid=\(process.processID); exit=\(process.terminationStatus); duration_ms=\(process.durationMilliseconds); truncated=\(process.outputWasTruncated)") // Includes no inherited environment or provider secrets.
        } // Ends process evidence rendering.
        return Self.bounded(EngineeringSecretRedactor.redact(sections.joined(separator: "\n")), maximumBytes: maximumOutputBytes, marker: "\n[adapter output truncated]") // Enforces the final independent model-context byte ceiling.
    } // Ends bounded output rendering.

    private static func verificationEvidence(invocation: EngineeringToolInvocation, result: EngineeringToolResult, summary: String) -> EngineeringAgentVerificationEvidence? { // Produces real verification metadata only for semantically explicit tools.
        switch invocation { // Avoids interpreting arbitrary command prose as proof.
        case .buildProject: return EngineeringAgentVerificationEvidence(kind: .build, succeeded: result.succeeded, summary: summary) // Records actual build process outcome.
        case .runTests: return EngineeringAgentVerificationEvidence(kind: .tests, succeeded: result.succeeded, summary: summary) // Records actual test process outcome.
        default: return nil // Leaves reads, writes, Git inspection, and generic commands out of verification claims.
        } // Ends verification evidence selection.
    } // Ends concrete verification adaptation.

    private static func failureResult(callID: String, code: String, summary: String) -> EngineeringAgentToolResult { // Builds a bounded pre-runtime validation failure.
        let safeSummary = oneLine(EngineeringSecretRedactor.redact(summary), maximumBytes: 1_000) // Removes likely secrets and line breaks from public metadata.
        let output = bounded("error_code: \(code)\nsummary: \(safeSummary)", maximumBytes: maximumOutputBytes, marker: "\n[adapter output truncated]") // Supplies repairable untrusted data without echoing arguments.
        return EngineeringAgentToolResult(callID: callID, status: .failed, output: output, operationalSummary: safeSummary, durationMilliseconds: 0) // Reports that no concrete tool operation ran.
    } // Ends validation-failure normalization.

    private static func cancelledResult(callID: String, summary: String) -> EngineeringAgentToolResult { // Builds a cancellation result before concrete dispatch.
        let safeSummary = oneLine(summary, maximumBytes: 1_000) // Bounds trace metadata.
        return EngineeringAgentToolResult(callID: callID, status: .cancelled, output: "error_code: process_cancelled\nsummary: \(safeSummary)", operationalSummary: safeSummary, durationMilliseconds: 0) // Stops the engine without inventing process evidence.
    } // Ends pre-dispatch cancellation normalization.

    private static func errorSummary(_ error: Error) -> String { // Converts strict decoder errors into bounded non-reflective diagnostics.
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return oneLine(description, maximumBytes: 1_000) } // Uses the adapter's stable field-only descriptions.
        return "Tool arguments did not match the exact registered schema." // Avoids reflecting decoder internals or source JSON.
    } // Ends decoder error normalization.

    private static func safeCallID(_ source: String) -> String { // Preserves valid correlation while refusing oversized or empty identifiers.
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines) // Checks usefulness without silently normalizing valid IDs.
        guard !trimmed.isEmpty, source.utf8.count <= 256 else { return "invalid-call" } // Uses a fixed safe correlation for malformed IDs.
        return source // Preserves the provider identity exactly.
    } // Ends call-ID validation.

    private static func oneLine(_ source: String, maximumBytes: Int) -> String { // Produces compact trace-safe text independent of model output.
        let collapsed = source.split(whereSeparator: { $0.isWhitespace }).map(String.init).joined(separator: " ") // Removes multiline content and repeated whitespace.
        return bounded(collapsed, maximumBytes: maximumBytes, marker: "…") // Applies the exact UTF-8 budget.
    } // Ends one-line bounding.

    private static func bounded(_ source: String, maximumBytes: Int, marker: String) -> String { // Truncates on Unicode-scalar boundaries while reserving space for an explicit marker.
        let limit = max(0, maximumBytes) // Normalizes a defensive non-positive caller value.
        guard source.utf8.count > limit else { return source } // Returns already-bounded text unchanged.
        let markerBytes = min(limit, marker.utf8.count) // Reserves no more than the total available budget.
        let contentBudget = max(0, limit - markerBytes) // Computes the exact remaining payload bytes.
        var output = "" // Accumulates complete Unicode scalars only.
        var usedBytes = 0 // Tracks encoded UTF-8 size exactly.
        for scalar in source.unicodeScalars { // Visits stable scalar boundaries without splitting encoded bytes.
            let scalarText = String(scalar) // Converts one complete scalar to its UTF-8 representation.
            let scalarBytes = scalarText.utf8.count // Measures its exact byte cost.
            guard usedBytes + scalarBytes <= contentBudget else { break } // Stops before exceeding the reserved payload budget.
            output.unicodeScalars.append(scalar) // Appends the complete safe scalar.
            usedBytes += scalarBytes // Advances exact retained byte count.
        } // Ends scalar-safe truncation.
        return output + boundedMarker(marker, maximumBytes: limit - usedBytes) // Appends as much explicit truncation evidence as fits.
    } // Ends UTF-8-safe output bounding.

    private static func boundedMarker(_ marker: String, maximumBytes: Int) -> String { // Fits a short marker on Unicode-scalar boundaries.
        var output = "" // Accumulates complete marker scalars.
        var usedBytes = 0 // Tracks exact marker bytes.
        for scalar in marker.unicodeScalars { // Visits complete marker scalars.
            let scalarText = String(scalar) // Converts the scalar for byte measurement.
            guard usedBytes + scalarText.utf8.count <= maximumBytes else { break } // Stops at the remaining result budget.
            output.unicodeScalars.append(scalar) // Appends the complete marker scalar.
            usedBytes += scalarText.utf8.count // Advances exact marker usage.
        } // Ends bounded marker construction.
        return output // Returns an always-valid UTF-8 suffix.
    } // Ends marker fitting.

    private static let denialErrorCodes: Set<String> = ["approval_denied", "approval_timeout", "command_blocked", "command_not_allowed", "sensitive_path", "invalid_relative_path", "path_escape", "wrong_workspace"] // Maps only concrete permission and authority failures to denied.

    private static func schema(for tool: EngineeringToolName) -> String { // Returns one closed provider-compatible JSON Schema matching the strict decoder.
        switch tool { // Selects exact properties and required fields per concrete tool.
        case .listDirectory: return objectSchema(properties: #""path":{"type":"string","maxLength":4096}"#, required: #""path""#) // Describes bounded root-relative listing.
        case .readFile: return objectSchema(properties: #""path":{"type":"string","minLength":1,"maxLength":4096},"startLine":{"type":"integer","minimum":1,"maximum":10000000},"endLine":{"type":"integer","minimum":1,"maximum":10000000}"#, required: #""path""#) // Describes bounded text reading and line range.
        case .writeFile: return objectSchema(properties: #""path":{"type":"string","minLength":1,"maxLength":4096},"content":{"type":"string","maxLength":60000},"expectedSHA256":{"type":"string","pattern":"^[A-Fa-f0-9]{64}$"}"#, required: #""path","content","expectedSHA256""#) // Describes conflict-aware complete overwrite.
        case .replaceInFile: return objectSchema(properties: #""path":{"type":"string","minLength":1,"maxLength":4096},"oldText":{"type":"string","minLength":1,"maxLength":30000},"newText":{"type":"string","maxLength":30000},"expectedOccurrences":{"type":"integer","minimum":1,"maximum":100000},"expectedSHA256":{"type":"string","pattern":"^[A-Fa-f0-9]{64}$"}"#, required: #""path","oldText","newText","expectedOccurrences","expectedSHA256""#) // Describes deterministic exact replacement.
        case .createFile: return objectSchema(properties: #""path":{"type":"string","minLength":1,"maxLength":4096},"content":{"type":"string","maxLength":60000},"createParentDirectories":{"type":"boolean"}"#, required: #""path","content""#) // Describes non-overwriting creation.
        case .searchFiles, .searchText: return objectSchema(properties: #""query":{"type":"string","minLength":1,"maxLength":4096},"path":{"type":"string","maxLength":4096}"#, required: #""query","path""#) // Describes bounded literal discovery.
        case .fileInfo: return objectSchema(properties: #""path":{"type":"string","minLength":1,"maxLength":4096}"#, required: #""path""#) // Describes contained metadata inspection.
        case .runCommand: return objectSchema(properties: commandProperties(reasonRequired: true), required: #""executable","arguments","workingDirectory","timeoutMilliseconds","reason""#) // Describes direct executable and separate arguments only.
        case .gitStatus, .gitDiff: return objectSchema(properties: "", required: "") // Describes fixed read-only commands with no model-controlled fields.
        case .gitLog: return objectSchema(properties: #""limit":{"type":"integer","minimum":1,"maximum":100}"#, required: #""limit""#) // Describes bounded fixed-format Git history.
        case .buildProject, .runTests: return objectSchema(properties: commandProperties(reasonRequired: false), required: #""executable","arguments","workingDirectory","timeoutMilliseconds""#) // Describes explicit deterministic build or test execution.
        case .unifiedDiff, .rollbackChange: return objectSchema(properties: #""changeID":{"type":"string","format":"uuid"}"#, required: #""changeID""#) // Describes exact app-owned transaction identity.
        } // Ends schema selection.
    } // Ends exact JSON Schema generation.

    private static func commandProperties(reasonRequired: Bool) -> String { // Returns the shared direct-command property schema without a raw shell string.
        let reasonMinimum = reasonRequired ? #", "minLength":1"# : "" // Keeps required run-command rationale useful while allowing build/test defaults.
        return #""executable":{"type":"string","minLength":1,"maxLength":1024},"arguments":{"type":"array","maxItems":256,"items":{"type":"string","maxLength":8192}},"workingDirectory":{"type":"string","maxLength":4096},"timeoutMilliseconds":{"type":"integer","minimum":1,"maximum":1800000},"reason":{"type":"string","maxLength":500\#(reasonMinimum)}"# // Declares separate bounded fields and no environment authority.
    } // Ends shared command schema properties.

    private static func objectSchema(properties: String, required: String) -> String { // Wraps property fragments in a closed exact object schema.
        #"{"type":"object","properties":{\#(properties)},"required":[\#(required)],"additionalProperties":false}"# // Rejects every undocumented field at the provider and adapter boundaries.
    } // Ends closed schema construction.
} // Ends the Engineering Agent to Mac Tool Runtime bridge.

enum EngineeringAgentToolAdapterError: LocalizedError, Equatable, Sendable { // Defines bounded schema diagnostics that never echo untrusted values.
    case invalidCallIdentity // Indicates an empty or oversized tool-call correlation identity.
    case unknownTool // Indicates a name outside the concrete registered tool enum.
    case invalidJSON // Indicates malformed JSON, Markdown, fragments, or natural language.
    case argumentsTooLarge // Indicates the fixed structured input byte ceiling was exceeded.
    case missingFields([String]) // Indicates required schema keys were absent.
    case unexpectedFields([String]) // Indicates undocumented schema keys attempted to add authority.
    case invalidType(String) // Indicates a field did not have the exact registered JSON type.
    case invalidValue(String) // Indicates a typed field violated its bounded semantic range.

    var errorDescription: String? { // Produces repairable field-only diagnostics without source values.
        switch self { // Selects one stable bounded description.
        case .invalidCallIdentity: return "Tool call identity must be non-empty and at most 256 UTF-8 bytes." // Describes invalid correlation metadata.
        case .unknownTool: return "Tool name is not registered by the Mac Engineering Tool Runtime." // Describes exact-name refusal.
        case .invalidJSON: return "Tool arguments must be one standalone JSON object with no prose or Markdown." // Describes strict structured input.
        case .argumentsTooLarge: return "Tool arguments exceed the 65,536-byte safety limit." // Describes fixed engine-aligned size refusal.
        case let .missingFields(fields): return "Tool arguments are missing required field(s): \(fields.joined(separator: ", "))." // Names only schema fields, never values.
        case let .unexpectedFields(fields): return "Tool arguments contain unsupported field(s): \(fields.joined(separator: ", "))." // Names only attempted extra fields.
        case let .invalidType(field): return "Tool argument \(field) has the wrong JSON type." // Identifies the repairable field.
        case let .invalidValue(field): return "Tool argument \(field) violates its registered bounds or format." // Identifies the bounded semantic failure.
        } // Ends adapter diagnostic selection.
    } // Ends localized adapter diagnostics.
} // Ends strict adapter error types.

private enum EngineeringAdapterJSONValue: Decodable, Sendable { // Retains exact JSON scalar categories for strict per-field type checks.
    case object([String: EngineeringAdapterJSONValue]) // Represents a keyed JSON object.
    case array([EngineeringAdapterJSONValue]) // Represents an ordered JSON array.
    case string(String) // Represents a JSON string.
    case integer(Int) // Represents an exactly integral in-range JSON number.
    case number(Double) // Represents a non-integral JSON number rejected by integer fields.
    case boolean(Bool) // Represents a JSON boolean distinct from numeric zero or one.
    case null // Represents JSON null, rejected unless a future schema explicitly permits it.

    init(from decoder: Decoder) throws { // Decodes one recursive value while preserving exact scalar intent.
        let container = try decoder.singleValueContainer() // Reads one complete JSON value.
        if container.decodeNil() { self = .null; return } // Preserves explicit null instead of treating it as a missing optional field.
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return } // Decodes boolean before numeric types.
        if let value = try? container.decode(Int.self) { self = .integer(value); return } // Retains exact supported integers.
        if let value = try? container.decode(Double.self) { self = .number(value); return } // Retains other finite JSON numbers for later type rejection.
        if let value = try? container.decode(String.self) { self = .string(value); return } // Retains exact Unicode text.
        if let value = try? container.decode([String: EngineeringAdapterJSONValue].self) { self = .object(value); return } // Recursively decodes keyed objects.
        if let value = try? container.decode([EngineeringAdapterJSONValue].self) { self = .array(value); return } // Recursively decodes arrays.
        throw EngineeringAgentToolAdapterError.invalidJSON // Rejects any representation outside standard JSON values.
    } // Ends exact JSON value decoding.
} // Ends strict JSON value representation.

private struct EngineeringAdapterJSONObject: Sendable { // Provides closed-schema field access over one standalone bounded object.
    private let values: [String: EngineeringAdapterJSONValue] // Stores exact decoded keys and value categories.

    init(source: String, maximumBytes: Int) throws { // Parses one complete object without accepting Markdown fences or surrounding prose.
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines) // Removes only harmless outer whitespace.
        guard trimmed.utf8.count <= maximumBytes else { throw EngineeringAgentToolAdapterError.argumentsTooLarge } // Applies the engine-aligned hard byte ceiling first.
        guard trimmed.first == "{", trimmed.last == "}", let data = trimmed.data(using: .utf8) else { throw EngineeringAgentToolAdapterError.invalidJSON } // Requires one standalone UTF-8 object shape.
        let decoded: EngineeringAdapterJSONValue // Stores the recursively typed root.
        do { // Attempts complete strict JSON decoding.
            decoded = try JSONDecoder().decode(EngineeringAdapterJSONValue.self, from: data) // Rejects trailing non-whitespace and malformed syntax.
        } catch let error as EngineeringAgentToolAdapterError { // Preserves stable adapter errors from recursive decoding.
            throw error // Returns the exact safe category.
        } catch { // Hides parser internals and source values.
            throw EngineeringAgentToolAdapterError.invalidJSON // Reports one repairable structured error.
        } // Ends JSON decoding recovery.
        guard case let .object(values) = decoded else { throw EngineeringAgentToolAdapterError.invalidJSON } // Rejects array, scalar, and null roots.
        self.values = values // Retains only the exact keyed object.
    } // Ends strict object construction.

    func require(required: Set<String>, optional: Set<String> = []) throws { // Enforces exact keys before any field is read.
        let actual = Set(values.keys) // Captures decoded field names.
        let missing = required.subtracting(actual).sorted() // Computes absent required schema keys deterministically.
        guard missing.isEmpty else { throw EngineeringAgentToolAdapterError.missingFields(missing) } // Refuses default guessing for required authority.
        let unexpected = actual.subtracting(required.union(optional)).sorted() // Computes every undocumented field deterministically.
        guard unexpected.isEmpty else { throw EngineeringAgentToolAdapterError.unexpectedFields(unexpected) } // Rejects added shell, environment, overwrite, or policy fields.
    } // Ends closed-key validation.

    func path(_ key: String) throws -> String { // Reads one non-empty bounded workspace-relative path candidate.
        try string(key, maximumBytes: 4_096, mayBeEmpty: false) // Leaves canonical containment and sensitive-path enforcement to EngineeringWorkspace.
    } // Ends path field access.

    func string(_ key: String, maximumBytes: Int, mayBeEmpty: Bool) throws -> String { // Reads one exact bounded JSON string.
        guard let value = values[key] else { throw EngineeringAgentToolAdapterError.missingFields([key]) } // Requires prior-declared fields even if a caller omitted require.
        guard case let .string(string) = value else { throw EngineeringAgentToolAdapterError.invalidType(key) } // Rejects arrays, booleans, numbers, objects, and null.
        guard string.utf8.count <= maximumBytes, mayBeEmpty || !string.isEmpty else { throw EngineeringAgentToolAdapterError.invalidValue(key) } // Enforces exact encoded size and emptiness policy.
        return string // Returns unmodified data without natural-language interpretation.
    } // Ends strict string access.

    func integer(_ key: String, range: ClosedRange<Int>) throws -> Int { // Reads one exact in-range JSON integer.
        guard let value = values[key] else { throw EngineeringAgentToolAdapterError.missingFields([key]) } // Requires the schema field.
        guard case let .integer(integer) = value else { throw EngineeringAgentToolAdapterError.invalidType(key) } // Rejects strings, floats, booleans, and null.
        guard range.contains(integer) else { throw EngineeringAgentToolAdapterError.invalidValue(key) } // Enforces the registered semantic bound.
        return integer // Returns the exact integer.
    } // Ends strict integer access.

    func optionalInteger(_ key: String, range: ClosedRange<Int>) throws -> Int? { // Reads an absent-or-exact-integer optional field.
        guard values[key] != nil else { return nil } // Treats only absence as optional and rejects explicit null later.
        return try integer(key, range: range) // Reuses exact type and range enforcement.
    } // Ends optional integer access.

    func optionalBoolean(_ key: String) throws -> Bool? { // Reads an absent-or-exact-boolean optional field.
        guard let value = values[key] else { return nil } // Treats only field absence as the default case.
        guard case let .boolean(boolean) = value else { throw EngineeringAgentToolAdapterError.invalidType(key) } // Rejects numeric or string truthiness.
        return boolean // Returns the exact JSON boolean.
    } // Ends optional boolean access.

    func stringArray(_ key: String, maximumItems: Int, maximumItemBytes: Int) throws -> [String] { // Reads bounded direct Process arguments without joining them.
        guard let value = values[key] else { throw EngineeringAgentToolAdapterError.missingFields([key]) } // Requires the explicit argument array.
        guard case let .array(items) = value else { throw EngineeringAgentToolAdapterError.invalidType(key) } // Rejects a raw command string or object.
        guard items.count <= maximumItems else { throw EngineeringAgentToolAdapterError.invalidValue(key) } // Bounds argument cardinality.
        return try items.enumerated().map { index, item in // Validates each argument independently.
            guard case let .string(string) = item else { throw EngineeringAgentToolAdapterError.invalidType("\(key)[\(index)]") } // Rejects nested values and type coercion.
            guard string.utf8.count <= maximumItemBytes, !string.contains("\0") else { throw EngineeringAgentToolAdapterError.invalidValue("\(key)[\(index)]") } // Bounds bytes and refuses embedded NUL.
            return string // Preserves exact punctuation as inert Process argument data.
        } // Ends per-argument validation.
    } // Ends argument-array access.

    func sha256(_ key: String) throws -> String { // Reads a canonical optimistic-concurrency fingerprint.
        let hash = try string(key, maximumBytes: 64, mayBeEmpty: false) // Requires exactly bounded text before format validation.
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF") // Declares the only accepted fingerprint alphabet.
        guard hash.utf8.count == 64, hash.unicodeScalars.allSatisfy({ hexadecimal.contains($0) }) else { throw EngineeringAgentToolAdapterError.invalidValue(key) } // Rejects truncated, extended, or non-hexadecimal hashes.
        return hash // Preserves caller casing because the runtime compares case-insensitively.
    } // Ends SHA-256 field access.

    func uuid(_ key: String) throws -> UUID { // Reads one exact canonical transaction identifier.
        let source = try string(key, maximumBytes: 36, mayBeEmpty: false) // Bounds the standard hyphenated UUID form.
        guard source.utf8.count == 36, let uuid = UUID(uuidString: source), uuid.uuidString.caseInsensitiveCompare(source) == .orderedSame else { throw EngineeringAgentToolAdapterError.invalidValue(key) } // Rejects partial or alternate textual shapes.
        return uuid // Returns the typed transaction identity.
    } // Ends UUID field access.

    func command(reasonRequired: Bool, defaultReason: String = "Engineering command") throws -> EngineeringCommand { // Reads one direct executable request without shell or environment fields.
        let executable = try string("executable", maximumBytes: 1_024, mayBeEmpty: false) // Reads one allowlist candidate only.
        let arguments = try stringArray("arguments", maximumItems: 256, maximumItemBytes: 8_192) // Preserves every Process argument boundary.
        let workingDirectory = try string("workingDirectory", maximumBytes: 4_096, mayBeEmpty: true) // Reads only a workspace-relative cwd candidate.
        let timeout = try integer("timeoutMilliseconds", range: 1...1_800_000) // Guarantees a finite command deadline of at most thirty minutes.
        let reason: String // Stores the user-visible approval rationale.
        if values["reason"] != nil { // Validates a supplied optional or required reason identically.
            reason = try string("reason", maximumBytes: 500, mayBeEmpty: !reasonRequired) // Requires useful text only for raw run_command.
        } else if reasonRequired { // Refuses missing authority rationale.
            throw EngineeringAgentToolAdapterError.missingFields(["reason"]) // Reports only the missing schema key.
        } else { // Applies the documented higher-level build/test default.
            reason = defaultReason // Uses application-owned rationale rather than model-invented content.
        } // Ends command reason selection.
        return EngineeringCommand(executable: executable, arguments: arguments, workingDirectory: workingDirectory, timeoutMilliseconds: timeout, reason: reason) // Creates the exact typed request for runtime policy.
    } // Ends direct-command decoding.
} // Ends strict closed JSON object access.
