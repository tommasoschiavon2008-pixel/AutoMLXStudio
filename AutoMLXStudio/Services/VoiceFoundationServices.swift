import AVFoundation // Supplies microphone authorization, WAV recording, and local audio playback.
import Combine // Supplies ObservableObject and Published for the main-actor Voice controller.
import Foundation // Supplies URL, FileManager, timing, and protocol support.

protocol MicrophonePermissionProviding: Sendable { // Isolates macOS microphone authorization for deterministic unit tests.
    func currentPermissionState() -> MicrophonePermissionState // Reads authorization without presenting a system prompt.
    func requestPermission() async -> MicrophonePermissionState // Requests access only when explicitly called by a Voice user action.
} // Ends the microphone permission provider boundary.

struct AVFoundationMicrophonePermissionProvider: MicrophonePermissionProviding { // Implements production authorization through AVCaptureDevice.
    func currentPermissionState() -> MicrophonePermissionState { // Maps the current read-only AVFoundation authorization value.
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio)) // Returns the typed Voice permission state without requesting access.
    } // Ends current permission-state lookup.

    func requestPermission() async -> MicrophonePermissionState { // Presents the system prompt only after the controller receives a Voice action.
        let granted = await withCheckedContinuation { continuation in // Bridges the AVFoundation completion callback into Swift concurrency.
            AVCaptureDevice.requestAccess(for: .audio) { allowed in // Requests only audio capture access from macOS.
                continuation.resume(returning: allowed) // Resumes the awaiting Voice action with the actual user decision.
            } // Ends the AVFoundation permission callback.
        } // Ends callback-to-async permission bridging.
        if granted { return .authorized } // Returns the explicit successful authorization state.
        return currentPermissionState() // Distinguishes denied, restricted, and unknown states after rejection.
    } // Ends microphone permission request.

    private static func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionState { // Converts AVFoundation authorization into the app domain model.
        switch status { // Selects the matching stable permission state.
        case .notDetermined: return .notDetermined // Preserves the state that permits a future user-triggered prompt.
        case .restricted: return .restricted // Preserves the system-policy restriction.
        case .denied: return .denied // Preserves explicit user denial.
        case .authorized: return .authorized // Preserves successful access.
        @unknown default: return .unavailable // Fails safely for future framework authorization values.
        } // Ends AVFoundation permission mapping.
    } // Ends permission-state mapping.
} // Ends the production microphone permission provider.

protocol MicrophoneCaptureServicing: Sendable { // Isolates bounded press-record capture from controller and UI code.
    func startRecording() async throws -> URL // Starts one local WAV recording and returns its destination.
    func stopRecording() async throws -> CapturedAudio // Stops the active recording and returns metadata for ASR.
    func cancelRecording() async // Stops and removes an abandoned temporary recording.
} // Ends the microphone capture service boundary.

actor MicrophoneCaptureService: MicrophoneCaptureServicing { // Owns the non-Sendable AVAudioRecorder inside one serialized actor.
    private static let sampleRate = 16_000.0 // Uses a common speech-recognition sample rate.
    private static let channelCount = 1 // Records mono audio to minimize temporary data and ASR work.
    private var recorder: AVAudioRecorder? // Retains the one active AVFoundation recorder.
    private var recordingURL: URL? // Retains the exact temporary file owned by the active recording.

    func startRecording() async throws -> URL { // Starts a new deterministic WAV capture without requesting permission itself.
        guard recorder == nil else { throw VoiceServiceError.recordingAlreadyActive } // Prevents overlapping microphone ownership.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioVoice", isDirectory: true) // Uses an app-specific temporary recording directory.
        do { // Creates the temporary destination and AVFoundation recorder.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) // Creates the directory only when recording is explicitly requested.
            let destination = directory.appendingPathComponent("voice-\(UUID().uuidString).wav", isDirectory: false) // Gives each capture an isolated local WAV path.
            let settings: [String: Any] = [ // Defines uncompressed mono PCM suitable for later ASR adapters.
                AVFormatIDKey: Int(kAudioFormatLinearPCM), // Selects linear PCM rather than a lossy speech codec.
                AVSampleRateKey: Self.sampleRate, // Records at the declared speech-oriented sample rate.
                AVNumberOfChannelsKey: Self.channelCount, // Records exactly one microphone channel.
                AVLinearPCMBitDepthKey: 16, // Uses conventional signed 16-bit PCM samples.
                AVLinearPCMIsFloatKey: false, // Stores integer samples.
                AVLinearPCMIsBigEndianKey: false // Stores native little-endian PCM data.
            ] // Ends WAV recorder settings.
            let newRecorder = try AVAudioRecorder(url: destination, settings: settings) // Creates the recorder without starting it prematurely.
            newRecorder.isMeteringEnabled = true // Leaves an audio-level boundary available for future VAD integration.
            guard newRecorder.prepareToRecord(), newRecorder.record() else { throw VoiceServiceError.microphoneCaptureFailed("AVAudioRecorder could not begin recording.") } // Requires both preparation and actual capture start.
            recorder = newRecorder // Retains the active recorder after successful startup.
            recordingURL = destination // Retains ownership of the temporary file.
            return destination // Returns the exact recording destination for UI diagnostics when needed.
        } catch let error as VoiceServiceError { // Preserves typed Voice failures.
            throw error // Returns the existing controlled diagnostic unchanged.
        } catch { // Converts AVFoundation or filesystem failures into the Voice domain.
            throw VoiceServiceError.microphoneCaptureFailed(error.localizedDescription) // Returns a bounded localized capture failure.
        } // Ends microphone startup recovery.
    } // Ends WAV microphone recording startup.

    func stopRecording() async throws -> CapturedAudio { // Stops the active recorder and returns filesystem-backed audio metadata.
        guard let recorder, let recordingURL else { throw VoiceServiceError.recordingNotActive } // Requires a matching active recorder and destination.
        let duration = max(0, recorder.currentTime) // Captures measured duration before AVFoundation resets recording state.
        recorder.stop() // Ends microphone capture synchronously.
        self.recorder = nil // Releases the AVFoundation recorder.
        self.recordingURL = nil // Releases actor ownership while preserving the returned file URL.
        return CapturedAudio(audioURL: recordingURL, durationSeconds: duration, sampleRate: Self.sampleRate, channelCount: Self.channelCount) // Returns honest capture metadata for ASR.
    } // Ends WAV microphone recording stop.

    func cancelRecording() async { // Cancels an in-progress recording without exposing incomplete audio downstream.
        recorder?.stop() // Stops capture when a recorder exists.
        recorder = nil // Releases the AVFoundation recorder.
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) } // Removes only the exact temporary file created by this service.
        recordingURL = nil // Clears temporary-file ownership after best-effort cleanup.
    } // Ends microphone recording cancellation.
} // Ends the production microphone capture actor.

protocol VoiceActivityDetecting: Sendable { // Reserves a replaceable VAD boundary without coupling it to microphone capture.
    func detectsSpeech(levelDecibels: Float) -> Bool // Classifies one measured audio level without controlling recording.
} // Ends the Voice activity detector boundary.

struct NoOpVoiceActivityDetector: VoiceActivityDetecting { // Provides the safe V0.3 foundation behavior for manual press-record mode.
    func detectsSpeech(levelDecibels: Float) -> Bool { // Accepts future metering data while leaving automatic detection disabled.
        false // Never changes recording state because full real-time VAD is outside this milestone.
    } // Ends no-op speech detection.
} // Ends the no-op Voice activity detector.

protocol SpeechToTextServicing: Sendable { // Isolates ASR inference from capture, controller, and text-model networking.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult // Converts one local audio reference into typed transcription output.
} // Ends the speech-to-text service boundary.

struct SpeechToTextService: SpeechToTextServicing { // Provides a compile-safe production placeholder until an inspected MLX Audio adapter is connected.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult { // Rejects unsupported execution rather than inventing mlx-audio commands.
        guard FileManager.default.fileExists(atPath: audioURL.path) else { throw VoiceServiceError.microphoneCaptureFailed("Recorded audio file is unavailable.") } // Reports a missing local input before dependency status.
        throw VoiceServiceError.missingMLXAudioDependency // Reports the exact dependency required for real ASR integration.
    } // Ends unavailable ASR execution.
} // Ends the speech-to-text production foundation.

protocol TextToSpeechServicing: Sendable { // Isolates TTS inference from response storage and playback policy.
    func synthesize(text: String) async throws -> SynthesizedSpeech // Converts non-empty assistant text into filesystem-backed speech.
} // Ends the text-to-speech service boundary.

struct TextToSpeechService: TextToSpeechServicing { // Provides a compile-safe production placeholder until an inspected MLX Audio adapter is connected.
    func synthesize(text: String) async throws -> SynthesizedSpeech { // Rejects unsupported execution rather than inventing mlx-audio commands.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceServiceError.invalidSynthesisText } // Rejects empty synthesis input deterministically.
        throw VoiceServiceError.missingMLXAudioDependency // Reports the exact dependency required for real TTS integration.
    } // Ends unavailable TTS execution.
} // Ends the text-to-speech production foundation.

@MainActor protocol AudioPlaybackServicing: AnyObject { // Isolates UI-requested playback while keeping AVAudioPlayer on the main actor.
    var playbackState: AudioPlaybackState { get } // Reports whether the one owned player is idle or actively playing.
    var currentFile: URL? { get } // Reports only the exact file currently owned for playback.
    var elapsedSeconds: Double { get } // Reports current player time when available.
    func play(audioURL: URL) throws // Starts playback only when explicitly requested by Voice policy.
    func stop() // Stops only audio owned by this playback service.
} // Ends the audio playback service boundary.

extension AudioPlaybackServicing { // Preserves source compatibility for deterministic playback fakes.
    var playbackState: AudioPlaybackState { .idle } // Supplies an idle default for tests that do not model player state.
    var currentFile: URL? { nil } // Supplies no current file for no-op test players.
    var elapsedSeconds: Double { 0 } // Supplies zero elapsed playback for no-op test players.
} // Ends playback fake compatibility defaults.

@MainActor final class AudioPlaybackService: NSObject, AudioPlaybackServicing, AVAudioPlayerDelegate { // Owns the one AVFoundation player used for generated speech.
    private var player: AVAudioPlayer? // Retains playback for the complete audio duration.
    private(set) var playbackState: AudioPlaybackState = .idle // Exposes the exact one-player lifecycle.
    private(set) var currentFile: URL? // Exposes the exact generated file owned until playback stops.
    var elapsedSeconds: Double { player?.currentTime ?? 0 } // Returns current AVAudioPlayer time without a separate timer.

    func play(audioURL: URL) throws { // Starts local audio playback for a synthesized file.
        stop() // Cancels and cleans any prior owned generated playback before creating a replacement player.
        do { // Creates and starts an AVFoundation player.
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL) // Opens only the supplied local audio file.
            newPlayer.delegate = self // Receives natural completion so the player and temporary output are released.
            guard newPlayer.prepareToPlay(), newPlayer.play() else { throw VoiceServiceError.audioPlaybackFailed("AVAudioPlayer could not begin playback.") } // Requires successful preparation and playback start.
            player = newPlayer // Retains the active player after successful startup.
            currentFile = audioURL // Retains the exact generated file while playback owns it.
            playbackState = .playing // Publishes active playback state.
        } catch let error as VoiceServiceError { // Preserves typed Voice playback failures.
            throw error // Returns the existing controlled diagnostic unchanged.
        } catch { // Converts AVFoundation file or decoding failures into the Voice domain.
            throw VoiceServiceError.audioPlaybackFailed(error.localizedDescription) // Returns a bounded localized playback failure.
        } // Ends playback startup recovery.
    } // Ends local synthesized-speech playback.

    func stop() { // Stops playback owned by this service.
        let previousFile = currentFile // Captures the exact owned temporary artifact before clearing state.
        player?.stop() // Stops the active player when present.
        player?.delegate = nil // Breaks the delegate relationship before releasing the player.
        player = nil // Releases the stopped player.
        currentFile = nil // Releases the file reference after player shutdown.
        playbackState = .idle // Publishes stable idle state.
        if let previousFile { VoiceTemporaryArtifacts.removeGeneratedAudio(at: previousFile) } // Cleans only proven app-owned generated audio.
    } // Ends audio playback stop.

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { // Receives the nonisolated AVFoundation callback safely.
        Task { @MainActor [weak self] in self?.stop() } // Returns to main-actor player ownership before cleanup and state mutation.
    } // Ends natural playback completion handling.
} // Ends the production audio playback service.

@MainActor final class VoiceConversationController: ObservableObject { // Coordinates permission, press-record capture, ASR, composer output, optional TTS, and playback.
    @Published private(set) var state: VoiceWorkflowState = .idle // Exposes the exact compact Voice UI state.
    @Published private(set) var permissionState: MicrophonePermissionState // Exposes authorization without requesting it during initialization.
    @Published private(set) var latestDraft: VoiceDraft? // Exposes transcription output for insertion into the Chat composer.
    @Published private(set) var failureMessage: String? // Exposes a concise recoverable Voice failure.
    @Published private(set) var speechFailureMessage: String? // Exposes optional TTS/playback failure without changing the text response.

    private let permissionProvider: any MicrophonePermissionProviding // Supplies injectable read/request authorization behavior.
    private let captureService: any MicrophoneCaptureServicing // Supplies injectable WAV microphone capture.
    private let speechToTextService: any SpeechToTextServicing // Supplies injectable ASR behavior.
    private let textToSpeechService: any TextToSpeechServicing // Supplies injectable TTS behavior.
    private let audioPlaybackService: any AudioPlaybackServicing // Supplies injectable local playback behavior.

    init( // Injects every side-effect boundary while providing safe production foundations.
        permissionProvider: any MicrophonePermissionProviding = AVFoundationMicrophonePermissionProvider(), // Uses AVFoundation authorization without requesting access immediately.
        captureService: any MicrophoneCaptureServicing = MicrophoneCaptureService(), // Uses serialized local WAV recording.
        speechToTextService: any SpeechToTextServicing = SpeechToTextService(), // Uses the explicit missing-dependency ASR foundation.
        textToSpeechService: any TextToSpeechServicing = TextToSpeechService(), // Uses the explicit missing-dependency TTS foundation.
        audioPlaybackService: (any AudioPlaybackServicing)? = nil // Allows tests to inject playback while deferring the main-actor production instance safely.
    ) { // Starts Voice controller construction.
        self.permissionProvider = permissionProvider // Stores the permission boundary.
        self.captureService = captureService // Stores the microphone capture boundary.
        self.speechToTextService = speechToTextService // Stores the ASR boundary.
        self.textToSpeechService = textToSpeechService // Stores the TTS boundary.
        self.audioPlaybackService = audioPlaybackService ?? AudioPlaybackService() // Creates default playback only inside the controller's main-actor initializer.
        self.permissionState = permissionProvider.currentPermissionState() // Reads current authorization without showing a prompt.
    } // Ends Voice controller construction.

    func startRecording() async { // Handles the user-triggered transition from idle, ready, or failed into recording.
        guard state == .idle || state == .ready || state == .failed else { return } // Ignores duplicate actions while permission, capture, or ASR work is active.
        latestDraft = nil // Clears a previously consumed or replaceable Voice draft.
        failureMessage = nil // Clears the previous capture or ASR diagnostic.
        var authorization = permissionProvider.currentPermissionState() // Rechecks current authorization immediately before capture.
        permissionState = authorization // Publishes the latest read-only authorization value.
        if authorization == .notDetermined { // Requests permission only because the user invoked Voice.
            state = .requestingPermission // Publishes the compact permission-request UI state.
            permissionState = .requestingPermission // Distinguishes the in-flight system prompt from not-determined state.
            authorization = await permissionProvider.requestPermission() // Awaits the actual macOS decision.
            permissionState = authorization // Publishes the terminal authorization result.
        } // Ends optional user-triggered permission request.
        guard authorization == .authorized else { // Converts every unavailable permission state into controlled failure.
            fail(permissionError(for: authorization)) // Publishes denied, restricted, or unavailable guidance.
            return // Prevents microphone capture without authorization.
        } // Ends microphone authorization enforcement.
        do { // Starts local microphone capture.
            _ = try await captureService.startRecording() // Creates and starts the WAV recording through the injected service.
            state = .recording // Publishes successful recording state only after capture actually starts.
        } catch { // Converts capture startup failure into the compact failed state.
            fail(error) // Publishes the localized capture diagnostic.
        } // Ends microphone capture startup recovery.
    } // Ends user-triggered recording startup.

    @discardableResult func stopRecordingAndTranscribe() async -> VoiceDraft? { // Stops press-record capture and returns composer-ready text without auto-sending it.
        guard state == .recording else { // Rejects invalid stop actions deterministically.
            fail(VoiceServiceError.recordingNotActive) // Publishes the controlled state-transition error.
            return nil // Returns no draft because no audio was captured.
        } // Ends active-recording validation.
        state = .transcribing // Publishes the ASR progress state before stopping and processing audio.
        let captureStopStart = DispatchTime.now().uptimeNanoseconds // Starts stop-finalization timing.
        do { // Finalizes capture and attempts real injected ASR.
            let captured = try await captureService.stopRecording() // Produces the local WAV reference and measured duration.
            let captureStopDuration = Self.elapsedMilliseconds(since: captureStopStart) // Measures capture finalization cost.
            let asrStart = DispatchTime.now().uptimeNanoseconds // Starts end-to-end ASR service timing.
            let transcription = try await speechToTextService.transcribe(audioURL: captured.audioURL) // Delegates ASR without forcing audio through the text server.
            let trimmedTranscript = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes composer output.
            guard !trimmedTranscript.isEmpty else { throw VoiceServiceError.emptyTranscription } // Rejects an unusable empty ASR result.
            let normalizedTranscription = TranscriptionResult(transcript: trimmedTranscript, audioDurationSeconds: transcription.audioDurationSeconds, detectedLanguage: transcription.detectedLanguage, processingDurationMilliseconds: transcription.processingDurationMilliseconds, modelID: transcription.modelID) // Preserves honest backend metadata and physical model identity with normalized text.
            let traceEvents = [ // Creates privacy-safe events that can later precede Fast Router in WorkflowTrace.
                VoiceServiceTraceEvent(kind: .microphoneCapture, name: "Microphone Capture", durationMilliseconds: max(Int(captured.durationSeconds * 1_000), captureStopDuration), status: .succeeded, detail: "Recorded local mono WAV audio."), // Records duration and format without audio contents.
                VoiceServiceTraceEvent(kind: .speechToText, name: "Speech-to-Text", durationMilliseconds: max(normalizedTranscription.processingDurationMilliseconds, Self.elapsedMilliseconds(since: asrStart)), status: .succeeded, detail: normalizedTranscription.detectedLanguage.map { "Detected language: \($0)." } ?? "Transcription completed; language was not reported.") // Records honest ASR timing and optional language.
            ] // Ends successful Voice trace events.
            let draft = VoiceDraft(text: trimmedTranscript, capturedAudio: captured, transcription: normalizedTranscription, traceEvents: traceEvents) // Creates the composer-ready Voice draft.
            latestDraft = draft // Publishes transcription output for Chat to place in its composer.
            failureMessage = nil // Clears any prior Voice failure.
            state = .ready // Publishes the required ready state without sending automatically.
            return draft // Returns the same published draft to an imperative UI caller.
        } catch { // Converts capture finalization or ASR failure into controlled state.
            fail(error) // Publishes the localized service diagnostic.
            return nil // Returns no composer draft after failure.
        } // Ends stop-and-transcribe recovery.
    } // Ends recording finalization and transcription.

    func cancelRecording() async { // Cancels capture and returns the controller to idle.
        await captureService.cancelRecording() // Stops and removes only audio owned by the capture service.
        latestDraft = nil // Clears any pending composer output.
        failureMessage = nil // Clears capture and ASR diagnostics.
        state = .idle // Publishes the stable idle state.
    } // Ends Voice recording cancellation.

    func consumeLatestDraft() -> VoiceDraft? { // Lets Chat move the ready transcript into its local composer state.
        let draft = latestDraft // Captures the current composer-ready value.
        latestDraft = nil // Prevents inserting the same transcript more than once.
        if state == .ready { state = .idle } // Returns to idle only after a successful draft is consumed.
        return draft // Returns the captured draft and its trace metadata.
    } // Ends Voice draft consumption.

    func resetFailure() { // Lets UI dismiss a controlled failure before another attempt.
        failureMessage = nil // Clears the displayed failure text.
        if state == .failed { state = .idle } // Restores idle only from the failed state.
    } // Ends Voice failure reset.

    func synthesizeAndPlayAssistantResponse(_ text: String, enabled: Bool) async -> VoiceServiceTraceEvent? { // Applies optional speak-response policy without affecting stored text.
        guard enabled else { return VoiceServiceTraceEvent(kind: .textToSpeech, name: "Text-to-Speech", durationMilliseconds: 0, status: .skipped, detail: "Speak assistant responses is disabled.") } // Records explicit policy skip without backend work.
        speechFailureMessage = nil // Clears only the previous optional speech diagnostic.
        let synthesisStart = DispatchTime.now().uptimeNanoseconds // Starts measured optional synthesis timing.
        do { // Attempts injected TTS and explicit playback.
            let speech = try await textToSpeechService.synthesize(text: text) // Generates filesystem-backed speech without autoplay inside the TTS service.
            let synthesisDuration = max(speech.synthesisDurationMilliseconds, Self.elapsedMilliseconds(since: synthesisStart)) // Preserves backend timing while covering total service latency.
            try audioPlaybackService.play(audioURL: speech.audioURL) // Starts playback only because Voice mode requested it.
            return VoiceServiceTraceEvent(kind: .textToSpeech, name: "Text-to-Speech", durationMilliseconds: synthesisDuration, status: .succeeded, detail: "Generated speech and started local playback.") // Reports successful optional speech work.
        } catch { // Contains TTS or playback failure independently from the assistant text response.
            speechFailureMessage = error.localizedDescription // Publishes a non-destructive optional speech diagnostic.
            return VoiceServiceTraceEvent(kind: .textToSpeech, name: "Text-to-Speech", durationMilliseconds: Self.elapsedMilliseconds(since: synthesisStart), status: .failed, detail: Self.boundedDetail(error.localizedDescription)) // Records failure without removing or replacing text.
        } // Ends optional TTS recovery.
    } // Ends optional assistant-response speech handling.

    func stopPlayback() { // Stops only synthesized speech owned by the injected playback service.
        audioPlaybackService.stop() // Delegates explicit playback cancellation.
    } // Ends synthesized-speech playback stop.

    private func permissionError(for state: MicrophonePermissionState) -> VoiceServiceError { // Maps non-authorized states to precise recovery errors.
        switch state { // Selects the failure matching the actual authorization result.
        case .denied: return .permissionDenied // Reports user denial.
        case .restricted: return .permissionRestricted // Reports system-policy restriction.
        default: return .permissionUnavailable // Covers not-determined, requesting, and unknown unavailable states safely.
        } // Ends permission error mapping.
    } // Ends permission error construction.

    private func fail(_ error: Error) { // Publishes one controlled Voice failure consistently.
        failureMessage = error.localizedDescription // Stores the user-facing diagnostic.
        state = .failed // Publishes the required failed UI state.
    } // Ends controlled failure publication.

    private static func elapsedMilliseconds(since start: UInt64) -> Int { // Converts monotonic timing into trace-friendly milliseconds.
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Returns whole elapsed milliseconds.
    } // Ends Voice timing conversion.

    private static func boundedDetail(_ text: String) -> String { // Prevents verbose runtime failures from flooding future traces.
        String(text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(180)) // Flattens repeated whitespace and bounds diagnostic length.
    } // Ends Voice trace-detail bounding.
} // Ends the main-actor Voice conversation controller.
