import AppKit // Supplies deterministic programmatic PNG drawing without user input.
import AVFoundation // Supplies real generated and synthesized WAV readability and duration validation.
import XCTest // Supplies skip-capable local hardware validation assertions.
@testable import AutoMLXStudio // Exposes the offline catalog and central runtime adapter registry.

final class VisionHardwareTests: XCTestCase { // Defines an honest hardware gate for the optional MLX VLM runtime.
    func testInstalledVisionBackendHardwarePreflight() async throws { // Validates real local installation and dependency evidence before any future inference call.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Inspects the actual Project 5 model root read-only.
        let vision = try XCTUnwrap(registry.model(id: Project5ModelCatalog.vision)) // Resolves the exact configured Qwen3 VL profile.
        guard vision.installationState == .installed else { throw XCTSkip("Vision hardware skipped: \(vision.statusDetail ?? vision.installationState.displayName)") } // Skips the incomplete or absent externally managed folder without starting it.
        let configuration = ModelRuntimeConfiguration(executableDirectory: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main/.venv/bin", repoPath: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main", requestedPort: 8082, autoSelectPort: true) // Uses the configured local MLX environment.
        let adapter = MLXVLMRuntimeAdapter() // Creates the production read-only Vision adapter.
        let dependency = adapter.dependencyStatus(configuration: configuration) // Discovers mlx-vlm without importing or installing it.
        guard dependency.isAvailable else { throw XCTSkip("Vision hardware skipped: \(dependency.detail)") } // Skips honestly when the optional runtime package is absent.
        try await adapter.validate(model: vision, configuration: configuration) // Verifies the actual complete folder and dependency when both are available.
    } // Ends Vision hardware preflight.

    func testRealVisionInferenceWithGeneratedProjectFiveImage() async throws { // Runs the actual local VLM only under the explicit hardware-test flag.
        guard ProcessInfo.processInfo.environment["RUN_MLX_VISION_HARDWARE_TESTS"] == "1" else { throw XCTSkip("Set RUN_MLX_VISION_HARDWARE_TESTS=1 to run real local Vision inference.") } // Keeps the permanent suite inexpensive and missing-model tolerant.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Inspects the actual Project 5 catalog read-only.
        let vision = try XCTUnwrap(registry.model(id: Project5ModelCatalog.vision)) // Resolves the exact configured Qwen3 VL profile.
        let report = ModelInstallationAuditor.report(for: vision, runtimeAvailable: true) // Audits shard, processor, tokenizer, and lock evidence before any process starts.
        guard report.status == .complete else { throw XCTSkip("Vision hardware skipped: \(report.status.displayName); missing \(report.missingFiles.joined(separator: ", ")).") } // Skips the externally managed incomplete download without mutation.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VisionHardware-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned artifact root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the deterministic test artifact root.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the isolated artifact directory.
        let imageURL = root.appendingPathComponent("project-five.png", isDirectory: false) // Resolves the generated PNG path outside every model directory.
        try Self.drawFixture(at: imageURL) // Draws the required white background, rectangle, circle, text, and arrow.
        let size = try imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 // Reads actual encoded image size.
        let attachment = ImageAttachment(url: imageURL, originalFilename: imageURL.lastPathComponent, contentTypeIdentifier: "public.png", byteCount: UInt64(max(0, size)), pixelWidth: 640, pixelHeight: 320) // Creates complete typed metadata for the actual generated PNG.
        let manager = ModelResourceManager(service: MLXService()) // Creates a fresh central resource authority that owns only processes started by this test.
        let result = try await MLXVLMVisionService(resourceManager: manager).analyze(images: [attachment], userPrompt: "Describe the visible objects and text in the image.", model: vision, configuration: Self.configuration) // Runs the actual offline mlx-vlm entrypoint and exact physical path.
        XCTAssertFalse(result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Confirms actual model output is usable.
        XCTAssertEqual(result.modelID, Project5ModelCatalog.vision) // Confirms the configured Vision model actually ran.
        XCTAssertEqual(result.modelPath, vision.localPath) // Confirms inference used the exact offline physical model path.
        XCTAssertGreaterThan(result.inferenceDurationMilliseconds, 0) // Confirms real one-shot process timing was measured.
        XCTAssertNil(result.loadDurationMilliseconds) // Confirms the one-shot CLI does not fabricate a separate unavailable load duration.
        let snapshot = await manager.snapshot() // Reads central residency state after one-shot release.
        XCTAssertNil(snapshot.activeModelID) // Confirms no text-only model was substituted or left running.
    } // Ends actual Vision hardware inference test.

    private static let configuration = ModelRuntimeConfiguration(executableDirectory: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main/.venv/bin", repoPath: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main", requestedPort: 8082, autoSelectPort: true) // Uses the configured existing offline MLX environment.

    private static func drawFixture(at url: URL) throws { // Draws one deterministic image entirely in the temporary test location.
        let image = NSImage(size: NSSize(width: 640, height: 320)) // Creates a fixed-size bitmap drawing surface.
        image.lockFocus() // Begins AppKit drawing into the isolated image.
        NSColor.white.setFill() // Selects the required white background.
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 320)).fill() // Fills every pixel with the background color.
        NSColor.systemBlue.setStroke() // Selects a high-contrast rectangle stroke.
        let rectangle = NSBezierPath(rect: NSRect(x: 48, y: 72, width: 220, height: 150)) // Creates the visible rectangle geometry.
        rectangle.lineWidth = 8 // Makes the rectangle easy for a Vision model to identify.
        rectangle.stroke() // Draws the rectangle outline.
        NSColor.systemOrange.setFill() // Selects a distinct circle fill.
        NSBezierPath(ovalIn: NSRect(x: 360, y: 92, width: 130, height: 130)).fill() // Draws the visible circle.
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.black] // Defines deterministic high-contrast visible text styling.
        NSString(string: "PROJECT 5").draw(at: NSPoint(x: 200, y: 252), withAttributes: attributes) // Draws the required text above the shapes.
        NSColor.black.setStroke() // Selects the arrow stroke color.
        let arrow = NSBezierPath() // Creates the simple directional arrow path.
        arrow.move(to: NSPoint(x: 275, y: 145)) // Starts the arrow between the shapes.
        arrow.line(to: NSPoint(x: 340, y: 145)) // Draws the arrow shaft toward the circle.
        arrow.line(to: NSPoint(x: 322, y: 163)) // Draws the upper arrowhead segment.
        arrow.move(to: NSPoint(x: 340, y: 145)) // Returns to the arrow tip.
        arrow.line(to: NSPoint(x: 322, y: 127)) // Draws the lower arrowhead segment.
        arrow.lineWidth = 7 // Makes the arrow geometry easy to identify.
        arrow.stroke() // Draws the complete arrow.
        image.unlockFocus() // Ends AppKit drawing.
        guard let tiff = image.tiffRepresentation, let representation = NSBitmapImageRep(data: tiff), let png = representation.representation(using: .png, properties: [:]) else { throw VisionHardwareFixtureError.encodingFailed } // Encodes actual PNG bytes or fails explicitly.
        try png.write(to: url, options: .atomic) // Writes only the exact test-owned image artifact.
    } // Ends deterministic Vision fixture drawing.
} // Ends Vision hardware tests.

final class AudioHardwareTests: XCTestCase { // Defines honest hardware gates for optional ASR and TTS resources.
    func testInstalledASRAndTTSBackendHardwarePreflight() async throws { // Validates real local audio resources before any future model invocation.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Inspects actual Project 5 audio folders read-only.
        let asr = try XCTUnwrap(registry.model(id: Project5ModelCatalog.speechToText)) // Resolves the configured Qwen3 ASR profile.
        let tts = try XCTUnwrap(registry.model(id: Project5ModelCatalog.textToSpeech)) // Resolves the configured Qwen3 TTS profile.
        guard asr.installationState == .installed, tts.installationState == .installed else { throw XCTSkip("Audio hardware skipped: ASR=\(asr.installationState.displayName), TTS=\(tts.installationState.displayName).") } // Skips when either externally managed model is incomplete.
        let configuration = ModelRuntimeConfiguration(executableDirectory: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main/.venv/bin", repoPath: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main", requestedPort: 8082, autoSelectPort: true) // Uses the configured local MLX environment.
        let adapter = MLXAudioRuntimeAdapter() // Creates the production read-only audio adapter.
        let dependency = adapter.dependencyStatus(configuration: configuration) // Discovers mlx-audio without importing or installing it.
        guard dependency.isAvailable else { throw XCTSkip("Audio hardware skipped: \(dependency.detail)") } // Skips honestly when the optional runtime package is absent.
        try await adapter.validate(model: asr, configuration: configuration) // Validates the actual ASR installation and dependency.
        try await adapter.validate(model: tts, configuration: configuration) // Validates the actual TTS installation and dependency.
    } // Ends audio hardware preflight.

    func testRealASRWithDeterministicSynthesizedWAV() async throws { // Runs actual local ASR against a known non-microphone speech fixture when explicitly enabled.
        guard ProcessInfo.processInfo.environment["RUN_MLX_AUDIO_HARDWARE_TESTS"] == "1" else { throw XCTSkip("Set RUN_MLX_AUDIO_HARDWARE_TESTS=1 to run real local ASR inference.") } // Keeps permanent tests deterministic and inexpensive.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Inspects the actual Project 5 catalog read-only.
        let asr = try XCTUnwrap(registry.model(id: Project5ModelCatalog.speechToText)) // Resolves the exact Qwen3 ASR profile.
        try Self.requireComplete(asr, label: "ASR") // Skips incomplete externally managed model files safely.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ASRHardware-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned audio root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only deterministic ASR fixture artifacts.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the isolated artifact directory.
        let aiffURL = root.appendingPathComponent("project-five.aiff", isDirectory: false) // Resolves the initial macOS synthesized speech container.
        let wavURL = root.appendingPathComponent("project-five.wav", isDirectory: false) // Resolves the final 16 kHz mono WAV fixture.
        let runner = ManagedPythonProcessRunner() // Reuses exact owned-process timeout and output bounding for fixture tools.
        let say = ManagedPythonCommand(executableURL: URL(fileURLWithPath: "/usr/bin/say"), arguments: ["-v", "Samantha", "-o", aiffURL.path, "Project five voice test."], workingDirectoryURL: root, environment: [:], timeoutMilliseconds: 30_000) // Creates deterministic local synthesized speech without playback.
        let sayResult = try await runner.run(say) // Runs and awaits only the exact test-owned speech process.
        XCTAssertEqual(sayResult.terminationStatus, 0) // Confirms fixture synthesis succeeded.
        let convert = ManagedPythonCommand(executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"), arguments: ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiffURL.path, wavURL.path], workingDirectoryURL: root, environment: [:], timeoutMilliseconds: 30_000) // Converts to the production recorder's mono 16 kHz Int16 WAV shape.
        let convertResult = try await runner.run(convert) // Runs and awaits only the exact test-owned conversion process.
        XCTAssertEqual(convertResult.terminationStatus, 0) // Confirms audio conversion succeeded.
        let input = try AVAudioFile(forReading: wavURL) // Validates actual fixture readability before ASR.
        XCTAssertGreaterThan(input.length, 0) // Confirms the source contains decoded audio frames.
        let manager = ModelResourceManager(service: MLXService()) // Creates a fresh resource authority that cannot own unrelated text processes.
        let adapter = MLXASRRuntimeAdapter(modelProvider: { asr }, configurationProvider: { Self.configuration }, resourceManager: manager) // Connects the production actual ASR runtime to the exact model and environment.
        let result = try await adapter.transcribe(audioURL: wavURL) // Runs actual offline mlx-audio speech recognition.
        XCTAssertFalse(result.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Confirms actual ASR output is usable.
        XCTAssertEqual(result.modelID, Project5ModelCatalog.speechToText) // Confirms the physical ASR model identity.
        XCTAssertGreaterThan(result.processingDurationMilliseconds, 0) // Confirms actual processing time was measured.
        XCTAssertGreaterThan(result.audioDurationSeconds, 0) // Confirms input duration came from readable audio frames.
        XCTAssertTrue(result.transcript.lowercased().contains("project")) // Confirms the deterministic phrase is materially recognized without requiring punctuation.
        let snapshot = await manager.snapshot() // Reads actor-isolated residency evidence before the XCTest autoclosure.
        XCTAssertNil(snapshot.activeModelID) // Confirms no unrelated text model was used or left active.
    } // Ends actual ASR hardware test.

    func testRealTTSGeneratesReadableAudioWithoutPlayback() async throws { // Runs actual local TTS and validates the generated file without ever starting playback.
        guard ProcessInfo.processInfo.environment["RUN_MLX_AUDIO_HARDWARE_TESTS"] == "1" else { throw XCTSkip("Set RUN_MLX_AUDIO_HARDWARE_TESTS=1 to run real local TTS inference.") } // Keeps permanent tests inexpensive and silent.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Inspects the actual Project 5 catalog read-only.
        let tts = try XCTUnwrap(registry.model(id: Project5ModelCatalog.textToSpeech)) // Resolves the exact Qwen3 TTS profile.
        try Self.requireComplete(tts, label: "TTS") // Skips incomplete externally managed model files safely.
        let manager = ModelResourceManager(service: MLXService()) // Creates a fresh resource authority that owns only this one-shot inference.
        let adapter = MLXTTSRuntimeAdapter(modelProvider: { tts }, configurationProvider: { Self.configuration }, resourceManager: manager) // Connects the production actual TTS runtime without a playback service.
        let result = try await adapter.synthesize(text: "Project 5 voice test.") // Generates actual local WAV output through the inspected mlx-audio API.
        defer { VoiceTemporaryArtifacts.removeGeneratedAudio(at: result.audioURL) } // Removes only the exact app-owned generated output scope after validation.
        let file = try AVAudioFile(forReading: result.audioURL) // Requires AVFoundation-readable output.
        let size = try result.audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 // Reads actual generated file size.
        XCTAssertGreaterThan(file.length, 0) // Confirms decoded audio frames exist.
        XCTAssertGreaterThan(size, 44) // Confirms output exceeds a trivial WAV header.
        XCTAssertGreaterThan(result.durationSeconds, 0) // Confirms duration was derived from actual decoded frames.
        XCTAssertGreaterThan(result.synthesisDurationMilliseconds, 0) // Confirms real synthesis timing was recorded.
        XCTAssertEqual(result.modelID, Project5ModelCatalog.textToSpeech) // Confirms the physical TTS model identity.
        let snapshot = await manager.snapshot() // Reads actor-isolated residency evidence before the XCTest autoclosure.
        XCTAssertNil(snapshot.activeModelID) // Confirms no text model was substituted or left resident.
    } // Ends actual silent TTS hardware test.

    private static let configuration = ModelRuntimeConfiguration(executableDirectory: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main/.venv/bin", repoPath: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main", requestedPort: 8082, autoSelectPort: true) // Uses the configured existing offline MLX environment.

    private static func requireComplete(_ model: ModelProfile, label: String) throws { // Applies reusable file and dependency eligibility before expensive Audio work.
        let report = ModelInstallationAuditor.report(for: model, runtimeAvailable: true) // Audits actual local model files without mutation.
        guard report.status == .complete else { throw XCTSkip("\(label) hardware skipped: \(report.status.displayName); missing \(report.missingFiles.joined(separator: ", ")).") } // Skips honestly when optional hardware resources are incomplete.
    } // Ends Audio hardware eligibility gate.
} // Ends audio hardware tests.

private enum VisionHardwareFixtureError: LocalizedError { // Defines deterministic test-image encoding failure.
    case encodingFailed // Indicates AppKit could not produce PNG bytes.
    var errorDescription: String? { "Could not encode the deterministic Vision PNG fixture." } // Supplies a concise test failure.
} // Ends Vision fixture errors.
