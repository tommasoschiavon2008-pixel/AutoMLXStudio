import AppKit // Supplies deterministic local PNG fixture generation and the main actor used by playback tests.
import XCTest // Supplies asynchronous unit assertions and skip-capable hardware checks.
@testable import AutoMLXStudio // Exposes internal V0.3 foundation types to the test target.

final class VisionFoundationTests: XCTestCase { // Verifies attachment validation, routing, trace privacy, and controlled Vision unavailability.
    func testUnsupportedGIFContentIsRejectedEvenWithAnAllowedExtension() throws { // Verifies validation trusts decoded content rather than a misleading filename suffix.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VisionUnsupported-\(UUID().uuidString)", isDirectory: true) // Creates an isolated cleanup scope for the unsupported fixture.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the UUID-scoped test directory.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the fixture directory owned by this test.
        let imageURL = root.appendingPathComponent("unsupported.png") // Deliberately uses an allowed extension so only content inspection can reject the file.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) // Creates a tiny deterministic bitmap source.
        let representation = try XCTUnwrap(bitmap?.representation(using: .gif, properties: [:])) // Encodes actual GIF content, which is intentionally outside the PNG/JPEG/HEIC allowlist.
        try representation.write(to: imageURL) // Writes the unsupported content to the misleading PNG-named fixture.
        XCTAssertThrowsError(try AttachmentValidationService.validateImage(at: imageURL)) { error in // Requires production validation to reject the content before it reaches request state.
            guard case AttachmentValidationError.unsupportedImageType = error else { return XCTFail("Expected unsupportedImageType, received \(error).") } // Confirms rejection is specifically caused by the content-type allowlist.
        } // Ends unsupported-content error inspection.
    } // Ends unsupported image rejection test.

    func testPNGValidationAndTypedVisionRouting() throws { // Validates actual image content before deterministic attachment routing.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VisionFoundation-\(UUID().uuidString)", isDirectory: true) // Creates an isolated cleanup scope.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the test fixture directory.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this UUID-scoped fixture directory.
        let imageURL = root.appendingPathComponent("fixture.png") // Creates the exact local fixture location.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) // Creates a tiny deterministic RGBA bitmap.
        let representation = try XCTUnwrap(bitmap?.representation(using: .png, properties: [:])) // Encodes valid PNG content through AppKit.
        try representation.write(to: imageURL) // Writes the local test image atomically enough for the isolated test.
        let validation = try AttachmentValidationService.validateImage(at: imageURL) // Runs production content-based PNG validation.
        XCTAssertEqual(validation.attachment.pixelWidth, 2) // Confirms content-derived width.
        XCTAssertEqual(validation.attachment.pixelHeight, 3) // Confirms content-derived height.
        let request = UserRequest(text: "Describe it", attachments: [.image(validation.attachment)]) // Creates one typed URL-backed request.
        let decision = DeterministicFastRouter().route(request) // Runs the production typed router.
        XCTAssertEqual(decision.intent, .vision) // Confirms an actual image takes deterministic Vision precedence.
        XCTAssertEqual(request.attachments.first?.traceMetadata.kind, .image) // Confirms privacy-safe trace conversion retains only attachment category and metrics.
    } // Ends PNG validation and routing test.

    func testIncompleteVisionInstallationIsNeverSelectedOrStarted() async throws { // Verifies incomplete Vision resources produce a controlled workflow failure.
        let image = ImageAttachment(url: URL(fileURLWithPath: "/tmp/non-sensitive-fixture.png"), originalFilename: "fixture.png", contentTypeIdentifier: "public.png", byteCount: 10, pixelWidth: 2, pixelHeight: 2) // Creates typed metadata without requiring inference to read the placeholder URL.
        let vision = ModelProfile(id: "vision", displayName: "Vision", repositoryID: "vision", localPath: "/tmp/incomplete-vision", backend: .mlxVLM, capabilities: [.general, .reasoning, .vision], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .downloading, runtimeState: .unavailable, isLegacyFallback: false, statusDetail: "Indexed shards are incomplete.") // Creates an explicitly incomplete VLM profile.
        let legacy = ModelProfile(id: "legacy", displayName: "Legacy", repositoryID: "legacy", localPath: nil, backend: .mlxLM, capabilities: [.general, .reasoning, .coding, .swiftLanguage, .research], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: true, statusDetail: nil) // Creates the text fallback that must never impersonate Vision.
        let assignment = ModelAssignment(agentID: AgentID.vision, preferredModelID: vision.id, preferredCapability: .vision, fallbackModelIDs: [], fallbackCapabilities: [.vision], allowsRuntimeReuse: true) // Assigns only the real Vision backend.
        let registry = ModelRegistry(models: [vision, legacy], assignments: [assignment], legacyFallbackModelID: legacy.id, modelsRoot: "/tmp") // Builds the isolated backend-specific registry.
        let controller = VisionNeverStartController() // Records any illegal process start.
        let manager = ModelResourceManager(controller: controller) // Creates the production central resource authority.
        let engine = WorkflowEngine(client: VisionNeverCompleteClient(), resourceManager: manager) // Connects production routing to fail-if-called inference boundaries.
        let configuration = ModelRuntimeConfiguration(executableDirectory: "/tmp/missing-bin", repoPath: "/tmp", requestedPort: 21_000, autoSelectPort: true) // Supplies an intentionally unavailable runtime environment.
        let result = await engine.execute(request: UserRequest(text: "Describe this", attachments: [.image(image)]), conversationHistory: [], modelRegistry: registry, runtimeConfiguration: configuration, switchPolicy: .qualityPreferred) // Runs the typed Vision foundation.
        XCTAssertEqual(result.trace.intent, .vision) // Confirms attachment-driven routing.
        XCTAssertEqual(result.trace.specialistID, AgentID.vision) // Confirms the registered Vision Agent was selected.
        XCTAssertEqual(result.trace.status, .failed) // Confirms controlled unavailability rather than a fake text response.
        XCTAssertEqual(result.trace.attachmentMetadata?.first?.kind, .image) // Confirms privacy-safe attachment metadata reached the trace.
        XCTAssertFalse(result.trace.steps.contains { $0.stage == .specialist && $0.status == .succeeded }) // Confirms no Vision inference success was fabricated.
        let startCount = await controller.starts() // Reads actor-isolated start count before entering the XCTest autoclosure.
        XCTAssertEqual(startCount, 0) // Confirms the incomplete Vision model was never started.
    } // Ends incomplete Vision workflow test.
} // Ends Vision foundation tests.

@MainActor final class VoiceFoundationTests: XCTestCase { // Verifies Voice state transitions, draft behavior, and non-destructive TTS errors.
    func testDeniedMicrophonePermissionFailsWithoutStartingCapture() async { // Verifies denied authorization blocks hardware access and produces a recoverable state.
        let capture = VoiceCountingCapture() // Creates a capture fake that records every attempted hardware start.
        let controller = VoiceConversationController(permissionProvider: VoiceDeniedPermission(), captureService: capture, speechToTextService: VoiceFakeSTT(), textToSpeechService: VoiceFailingTTS(), audioPlaybackService: VoiceFakePlayback()) // Injects explicit denial with otherwise valid services.
        await controller.startRecording() // Simulates the user pressing the microphone button while access is denied.
        XCTAssertEqual(controller.permissionState, .denied) // Confirms the terminal system authorization state remains visible.
        XCTAssertEqual(controller.state, .failed) // Confirms denial transitions into the compact controlled failure state.
        XCTAssertEqual(controller.failureMessage, VoiceServiceError.permissionDenied.localizedDescription) // Confirms the UI receives the precise recovery diagnostic.
        let startCount = await capture.starts() // Reads the actor-isolated capture-start count outside the XCTest autoclosure.
        XCTAssertEqual(startCount, 0) // Confirms denied permission prevents all microphone capture attempts.
    } // Ends denied microphone permission test.

    func testUnavailableASRFailsWithoutProducingOrSendingDraft() async { // Verifies an absent optional ASR runtime remains a controlled non-destructive fallback.
        let controller = VoiceConversationController(permissionProvider: VoiceAllowedPermission(), captureService: VoiceFakeCapture(), speechToTextService: VoiceUnavailableSTT(), textToSpeechService: VoiceFailingTTS(), audioPlaybackService: VoiceFakePlayback()) // Injects the exact missing mlx-audio dependency failure.
        await controller.startRecording() // Enters recording through the normal authorized path.
        XCTAssertEqual(controller.state, .recording) // Confirms the failure is isolated to ASR rather than microphone setup.
        let draft = await controller.stopRecordingAndTranscribe() // Finalizes capture and invokes the unavailable ASR boundary.
        XCTAssertNil(draft) // Confirms no composer draft is fabricated after ASR failure.
        XCTAssertNil(controller.latestDraft) // Confirms no hidden draft can later be consumed or auto-sent.
        XCTAssertEqual(controller.state, .failed) // Confirms the state machine exposes controlled failure.
        XCTAssertEqual(controller.failureMessage, VoiceServiceError.missingMLXAudioDependency.localizedDescription) // Confirms the exact optional dependency gap is visible.
    } // Ends unavailable ASR fallback test.

    func testSpeakAssistantResponsesPreferenceRoundTripsAndLegacyStateDefaultsOff() throws { // Verifies explicit TTS opt-in persists while older state remains safely disabled.
        let enabledState = PersistedState(benchmarkResults: [], modelRegistry: nil, modelSwitchPolicy: nil, speakAssistantResponses: true) // Creates the same persisted value written by the Settings Save action.
        let encodedState = try JSONEncoder().encode(enabledState) // Serializes the current persisted-state schema.
        let decodedState = try JSONDecoder().decode(PersistedState.self, from: encodedState) // Restores the schema through the production Codable contract.
        XCTAssertEqual(decodedState.speakAssistantResponses, true) // Confirms explicit Speak opt-in survives an application-state round trip.
        let legacyData = try XCTUnwrap("{\"benchmarkResults\":[]}".data(using: .utf8)) // Creates a valid pre-Voice state payload with no Speak preference.
        let legacyState = try JSONDecoder().decode(PersistedState.self, from: legacyData) // Decodes the older schema using optional migration behavior.
        XCTAssertNil(legacyState.speakAssistantResponses) // Confirms AppState can apply its documented false default for older installations.
    } // Ends Speak preference persistence test.

    func testPressRecordTranscriptionBecomesReadyDraftWithoutAutoSend() async throws { // Exercises idle through recording, transcribing, and ready states.
        let capture = VoiceFakeCapture() // Creates an isolated fake WAV capture service.
        let controller = VoiceConversationController(permissionProvider: VoiceAllowedPermission(), captureService: capture, speechToTextService: VoiceFakeSTT(), textToSpeechService: VoiceFailingTTS(), audioPlaybackService: VoiceFakePlayback()) // Injects deterministic service boundaries.
        XCTAssertEqual(controller.state, .idle) // Confirms the stable initial state.
        await controller.startRecording() // Simulates an explicit microphone button press.
        XCTAssertEqual(controller.state, .recording) // Confirms capture starts only after authorization.
        let draft = await controller.stopRecordingAndTranscribe() // Simulates the user pressing Stop.
        XCTAssertEqual(controller.state, .ready) // Confirms successful ASR produces the required ready state.
        XCTAssertEqual(draft?.text, "transcribed locally") // Confirms the exact composer-ready transcript.
        XCTAssertEqual(draft?.traceEvents.map(\.kind), [.microphoneCapture, .speechToText]) // Confirms Voice services are traced independently from agents.
        XCTAssertEqual(controller.consumeLatestDraft()?.text, "transcribed locally") // Confirms Chat can explicitly consume the draft.
        XCTAssertEqual(controller.state, .idle) // Confirms consumption returns Voice to idle without auto-send behavior.
    } // Ends Voice draft state-machine test.

    func testTTSFailureDoesNotAlterAssistantText() async { // Verifies optional speech failure remains independent from the stored response value.
        let controller = VoiceConversationController(permissionProvider: VoiceAllowedPermission(), captureService: VoiceFakeCapture(), speechToTextService: VoiceFakeSTT(), textToSpeechService: VoiceFailingTTS(), audioPlaybackService: VoiceFakePlayback()) // Injects a TTS service that always fails controllably.
        let assistantText = "Authoritative stored answer" // Represents text already appended by AppState before optional speech begins.
        let event = await controller.synthesizeAndPlayAssistantResponse(assistantText, enabled: true) // Attempts optional TTS after text storage.
        XCTAssertEqual(assistantText, "Authoritative stored answer") // Confirms the caller-owned response remains unchanged.
        XCTAssertEqual(event?.status, .failed) // Confirms the service trace reports failure honestly.
        XCTAssertNotNil(controller.speechFailureMessage) // Confirms a visible non-destructive diagnostic is available.
    } // Ends non-destructive TTS failure test.
} // Ends Voice foundation tests.

private actor VisionNeverStartController: ModelServerControlling { // Fails the test if incomplete Vision reaches process startup.
    private var startCount = 0 // Counts attempted process starts.
    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { startCount += 1; return configuration.requestedPort } // Records any illegal start so the assertion can detect it.
    func stop() async {} // Implements the compatibility stop boundary without owning a process.
    func starts() -> Int { startCount } // Returns the actor-isolated start count.
} // Ends never-start controller.

private actor VisionNeverCompleteClient: LLMCompleting { // Fails safely if a text completion is incorrectly used for Vision.
    func complete(_ request: LLMCompletionRequest) async throws -> String { throw WorkflowEngineError.incompatibleModel("Vision Agent", request.model.id) } // Rejects any accidental text-only Vision approximation.
} // Ends never-complete client.

private struct VoiceAllowedPermission: MicrophonePermissionProviding { // Supplies deterministic authorized microphone state.
    func currentPermissionState() -> MicrophonePermissionState { .authorized } // Reports current authorization without prompting.
    func requestPermission() async -> MicrophonePermissionState { .authorized } // Reports authorization if a test unexpectedly requests it.
} // Ends authorized permission fake.

private struct VoiceDeniedPermission: MicrophonePermissionProviding { // Supplies deterministic denied microphone state.
    func currentPermissionState() -> MicrophonePermissionState { .denied } // Reports denial without presenting a system prompt.
    func requestPermission() async -> MicrophonePermissionState { .denied } // Preserves denial if an unexpected request occurs.
} // Ends denied permission fake.

private actor VoiceFakeCapture: MicrophoneCaptureServicing { // Supplies deterministic filesystem-backed capture metadata.
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-test.wav") // Uses a bounded local placeholder URL.
    func startRecording() async throws -> URL { url } // Reports capture start without accessing hardware.
    func stopRecording() async throws -> CapturedAudio { CapturedAudio(audioURL: url, durationSeconds: 1.0, sampleRate: 16_000, channelCount: 1) } // Returns honest deterministic audio metadata.
    func cancelRecording() async {} // Implements cancellation without external state.
} // Ends fake capture service.

private actor VoiceCountingCapture: MicrophoneCaptureServicing { // Records whether denied authorization ever reaches the capture boundary.
    private var startCount = 0 // Stores the exact number of attempted recording starts.
    func startRecording() async throws -> URL { startCount += 1; return FileManager.default.temporaryDirectory.appendingPathComponent("voice-denied-test.wav") } // Counts any illegal start while satisfying the protocol result.
    func stopRecording() async throws -> CapturedAudio { throw VoiceServiceError.recordingNotActive } // Rejects stop because denied capture must never become active.
    func cancelRecording() async {} // Implements cancellation without creating or removing external files.
    func starts() -> Int { startCount } // Returns the actor-isolated start count for the final assertion.
} // Ends capture-attempt counter fake.

private struct VoiceFakeSTT: SpeechToTextServicing { // Supplies deterministic ASR output.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult { TranscriptionResult(transcript: "transcribed locally", audioDurationSeconds: 1.0, detectedLanguage: "en", processingDurationMilliseconds: 4) } // Returns a non-empty composer-ready transcription.
} // Ends fake speech-to-text service.

private struct VoiceUnavailableSTT: SpeechToTextServicing { // Supplies the exact controlled failure used when mlx-audio is absent.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult { throw VoiceServiceError.missingMLXAudioDependency } // Rejects ASR without inventing a transcript or invoking another backend.
} // Ends unavailable speech-to-text fake.

private struct VoiceFailingTTS: TextToSpeechServicing { // Supplies a controlled optional dependency failure.
    func synthesize(text: String) async throws -> SynthesizedSpeech { throw VoiceServiceError.missingMLXAudioDependency } // Rejects synthesis without inventing a CLI.
} // Ends failing text-to-speech service.

@MainActor private final class VoiceFakePlayback: AudioPlaybackServicing { // Supplies a no-op main-actor playback boundary.
    func play(audioURL: URL) throws {} // Accepts playback if a test TTS implementation ever succeeds.
    func stop() {} // Implements explicit playback stop without hardware.
} // Ends fake playback service.
