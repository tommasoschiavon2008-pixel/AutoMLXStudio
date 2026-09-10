import Foundation // Supplies URLs, timing, filesystem validation, and Sendable value types for Vision inference.

struct VisualAnalysis: Codable, Equatable, Sendable { // Carries concise visual evidence into a technical specialist without recursive agent loops.
    let summary: String // Stores the model's concise description of visible evidence.
    let visibleText: [String] // Stores only text segments explicitly returned by the Vision model.
    let likelyContext: String? // Stores a bounded inferred context only when the model supplies one.

    var specialistContext: String { // Formats structured visual evidence for one downstream Coding, Swift, or Research specialist.
        let text = visibleText.isEmpty ? "None reported" : visibleText.joined(separator: " | ") // Preserves model-returned visible text without running separate OCR.
        let context = likelyContext ?? "Not reported" // Distinguishes absent context from an invented value.
        return "Visual summary: \(summary)\nVisible text: \(text)\nLikely context: \(context)" // Returns a compact deterministic handoff payload.
    } // Ends downstream specialist-context formatting.
} // Ends structured visual analysis metadata.

struct VisionResult: Equatable, Sendable { // Reports actual VLM output and only timing metadata supported by the one-shot command.
    let output: String // Stores the non-empty actual mlx-vlm response.
    let analysis: VisualAnalysis // Stores the minimally parsed downstream handoff representation.
    let modelID: String // Stores the actual physical Vision model ID.
    let modelPath: String // Stores the exact validated local model path used by the command.
    let loadDurationMilliseconds: Int? // Remains nil because the installed one-shot CLI does not separate load timing.
    let inferenceDurationMilliseconds: Int // Stores measured end-to-end one-shot Vision process duration.
    let residencyDecision: ResidencyDecision // Stores the actual central reuse, load, or text-release decision applied before launch.
} // Ends real Vision result metadata.

enum VisionRuntimeError: LocalizedError, Equatable, Sendable { // Defines Vision-specific input, process, and output failures.
    case missingImage // Reports a Vision invocation without a validated local image.
    case invalidImagePath(String) // Reports a missing attachment file before model work.
    case processFailed(String) // Reports bounded mlx-vlm process diagnostics.
    case emptyOutput // Reports a successful process with no usable Vision response.

    var errorDescription: String? { // Produces concise Chat and trace diagnostics.
        switch self { // Selects the concrete Vision failure message.
        case .missingImage: return "Vision inference requires at least one validated image attachment." // Explains missing visual input.
        case let .invalidImagePath(path): return "Vision image is unavailable: \(path)" // Describes the exact unavailable reference.
        case let .processFailed(detail): return "MLX Vision runtime failed: \(detail)" // Preserves bounded backend diagnostics.
        case .emptyOutput: return "Vision model returned an empty response." // Rejects fabricated success.
        } // Ends Vision error message selection.
    } // Ends localized Vision error access.
} // Ends Vision runtime errors.

protocol VisionInferencing: Sendable { // Isolates actual image inference from routing, text-model networking, and UI code.
    func analyze(images: [ImageAttachment], userPrompt: String, model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws -> VisionResult // Runs one real VLM request with an explicitly selected physical model.
} // Ends Vision inference boundary.

struct MLXVLMVisionService: VisionInferencing { // Executes Qwen3-VL through the inspected installed mlx-vlm entrypoint.
    private let resourceManager: ModelResourceManager // Coordinates exclusive large Vision ownership and text-server release.
    private let runner: ManagedPythonProcessRunner // Owns and serializes the exact one-shot VLM process.

    init(resourceManager: ModelResourceManager, runner: ManagedPythonProcessRunner = ManagedPythonProcessRunner()) { // Injects central memory authority and exact subprocess ownership.
        self.resourceManager = resourceManager // Stores unified-memory reservation authority.
        self.runner = runner // Stores the shell-free one-shot process runner.
    } // Ends Vision service construction.

    func analyze(images: [ImageAttachment], userPrompt: String, model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws -> VisionResult { // Runs one real local image analysis without text fallback.
        guard !images.isEmpty else { throw VisionRuntimeError.missingImage } // Requires actual validated attachment metadata.
        for image in images { // Revalidates filesystem presence immediately before the external process reads each image.
            guard FileManager.default.fileExists(atPath: image.url.path) else { throw VisionRuntimeError.invalidImagePath(image.url.path) } // Rejects a removed or unavailable attachment.
        } // Ends image-path revalidation.
        let reservation = try await resourceManager.reserveOneShot(model: model, configuration: configuration) // Stops a resident text model and reserves exclusive large Vision ownership.
        do { // Runs and parses the inspected mlx_vlm.generate contract.
            let executable = URL(fileURLWithPath: configuration.executableDirectory, isDirectory: true).appendingPathComponent("mlx_vlm.generate", isDirectory: false) // Resolves the configured installed VLM entrypoint.
            let prompt = Self.structuredPrompt(userPrompt) // Requests a minimal stable handoff shape without exposing reasoning.
            var arguments = ["--model", model.launchReference, "--image"] // Starts the documented model and variadic image arguments.
            arguments.append(contentsOf: images.map { $0.url.path }) // Supplies every validated local image in request order.
            arguments.append(contentsOf: ["--prompt", prompt, "--max-tokens", "384", "--temperature", "0", "--no-verbose"]) // Uses documented bounded deterministic text-generation flags and never requests download.
            let command = ManagedPythonCommand( // Builds one shell-free offline VLM command.
                executableURL: executable, // Uses only the configured virtual-environment entrypoint.
                arguments: arguments, // Supplies inspected CLI arguments as separate values.
                workingDirectoryURL: URL(fileURLWithPath: configuration.repoPath, isDirectory: true), // Uses the configured existing MLX repository as a stable read-only working location.
                environment: ["HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_DATASETS_OFFLINE": "1"], // Prevents repository or weight downloads at runtime.
                timeoutMilliseconds: 240_000 // Bounds cold large-Vision loading and inference conservatively.
            ) // Ends VLM command construction.
            let result = try await runner.run(command) // Launches and awaits only the exact app-owned Vision process.
            guard result.terminationStatus == 0 else { throw VisionRuntimeError.processFailed(Self.failureDetail(result)) } // Rejects actual non-zero process exits.
            let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes actual generated stdout.
            guard !output.isEmpty else { throw VisionRuntimeError.emptyOutput } // Never fabricates a visual answer.
            let analysis = Self.parse(output) // Minimally parses only the requested labels and preserves the complete output as fallback summary.
            await resourceManager.releaseOneShot(reservation) // Releases exclusive large Vision ownership after confirmed process exit.
            return VisionResult(output: output, analysis: analysis, modelID: model.id, modelPath: model.launchReference, loadDurationMilliseconds: nil, inferenceDurationMilliseconds: result.durationMilliseconds, residencyDecision: reservation.decision) // Returns only actual supported physical, residency, and timing metadata.
        } catch { // Releases central ownership on process, timeout, cancellation, or output failure.
            await resourceManager.releaseOneShot(reservation) // Releases only this Vision service's exact reservation.
            throw error // Preserves typed runtime or resource diagnostics.
        } // Ends Vision process recovery.
    } // Ends real local Vision inference.

    private static func structuredPrompt(_ userPrompt: String) -> String { // Creates a concise evidence-first response contract for direct and assisted workflows.
        let request = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only surrounding whitespace.
        let visibleRequest = request.isEmpty ? "Describe the attached image accurately." : request // Supplies a useful image-only request without inventing user details.
        return "Analyze only the attached image evidence for this request: \(visibleRequest)\nReturn exactly three short lines: SUMMARY: observable objects and state; VISIBLE_TEXT: text you can actually read, separated by |, or NONE; LIKELY_CONTEXT: a cautious context label or NONE. Do not provide hidden reasoning." // Requests a minimal parseable handoff rather than autonomous loops or OCR machinery.
    } // Ends structured Vision prompt construction.

    private static func parse(_ output: String) -> VisualAnalysis { // Parses only explicit labels and otherwise preserves the complete response as summary.
        let lines = output.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } // Produces normalized non-empty response lines.
        let summary = labeledValue("SUMMARY:", lines: lines) ?? output // Uses the model's explicit summary or preserves the actual full response.
        let visibleValue = labeledValue("VISIBLE_TEXT:", lines: lines) // Reads only the requested explicit visible-text field.
        let visibleText = visibleValue.flatMap { value -> [String]? in // Converts a real non-NONE field into bounded segments.
            guard value.caseInsensitiveCompare("NONE") != .orderedSame else { return [] } // Preserves explicit absence.
            return value.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } // Splits only the delimiter requested from the model.
        } ?? [] // Avoids inventing visible text when the label is absent.
        let contextValue = labeledValue("LIKELY_CONTEXT:", lines: lines) // Reads only the requested cautious context field.
        let context = contextValue?.caseInsensitiveCompare("NONE") == .orderedSame ? nil : contextValue // Converts explicit NONE into absence.
        return VisualAnalysis(summary: summary, visibleText: visibleText, likelyContext: context) // Returns minimally parsed actual model output.
    } // Ends minimal Vision output parsing.

    private static func labeledValue(_ label: String, lines: [String]) -> String? { // Finds one case-insensitive response label without fuzzy parsing.
        guard let line = lines.first(where: { $0.uppercased().hasPrefix(label) }) else { return nil } // Requires the exact requested label prefix.
        let value = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines) // Removes only the label and surrounding whitespace.
        return value.isEmpty ? nil : value // Rejects an empty labeled value.
    } // Ends exact Vision label extraction.

    private static func failureDetail(_ result: ManagedPythonResult) -> String { // Selects bounded useful VLM process diagnostics.
        let diagnostic = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines) // Prefers the backend diagnostic stream.
        let fallback = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) // Falls back to standard output.
        let value = diagnostic.isEmpty ? (fallback.isEmpty ? "Vision exited with status \(result.terminationStatus)." : fallback) : diagnostic // Selects one honest source.
        return String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds trace detail.
    } // Ends VLM process failure formatting.
} // Ends real MLX VLM Vision service.
