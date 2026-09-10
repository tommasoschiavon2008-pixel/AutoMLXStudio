import Foundation // Supplies Codable, URL, UUID, and LocalizedError for the Voice foundation value types.

enum MicrophonePermissionState: String, Codable, Equatable, Sendable { // Describes every microphone authorization state without requesting access implicitly.
    case notDetermined // Indicates that macOS has not shown the microphone permission prompt yet.
    case requestingPermission // Indicates that access was requested directly in response to a Voice action.
    case authorized // Indicates that microphone capture may begin.
    case denied // Indicates that the user denied microphone access.
    case restricted // Indicates that system policy prevents microphone access.
    case unavailable // Indicates that the platform returned an unknown or unsupported authorization state.
} // Ends the microphone permission state definition.

enum VoiceWorkflowState: String, Codable, Equatable, Sendable { // Defines the bounded press-record Voice workflow lifecycle.
    case idle // Indicates that Voice is ready for a new user action.
    case requestingPermission // Indicates that the controller is waiting for the system authorization result.
    case recording // Indicates that audio is actively being captured.
    case transcribing // Indicates that captured audio is being converted to text.
    case ready // Indicates that a transcription is ready to place in the Chat composer.
    case failed // Indicates that the latest Voice operation ended with a controlled error.
} // Ends the Voice workflow state definition.

enum AudioPlaybackState: String, Codable, Equatable, Sendable { // Describes the one synthesized-audio player lifecycle.
    case idle // Indicates that no generated response audio is currently playing.
    case playing // Indicates that one app-owned generated response is currently playing.
} // Ends synthesized-audio playback states.

struct CapturedAudio: Codable, Equatable, Sendable { // Stores a filesystem-backed recording without placing AVFoundation objects in core models.
    let audioURL: URL // Identifies the local WAV recording produced by microphone capture.
    let durationSeconds: Double // Stores the measured recording duration in seconds.
    let sampleRate: Double // Stores the recording sample rate needed by downstream ASR validation.
    let channelCount: Int // Stores the number of recorded audio channels.
} // Ends the captured-audio value type.

struct TranscriptionResult: Codable, Equatable, Sendable { // Stores honest speech-recognition output and timings.
    let transcript: String // Stores the text returned by the ASR backend.
    let audioDurationSeconds: Double // Stores the source-audio duration processed by ASR.
    let detectedLanguage: String? // Stores a language only when the backend actually reports one.
    let processingDurationMilliseconds: Int // Stores measured ASR processing time without fabricating confidence.
    let modelID: String? // Stores the actual physical ASR model when supplied by a real backend.

    init(transcript: String, audioDurationSeconds: Double, detectedLanguage: String?, processingDurationMilliseconds: Int, modelID: String? = nil) { // Preserves existing call sites while allowing real backend identity.
        self.transcript = transcript // Stores actual recognized text.
        self.audioDurationSeconds = audioDurationSeconds // Stores measured source-audio duration.
        self.detectedLanguage = detectedLanguage // Stores only backend-reported language metadata.
        self.processingDurationMilliseconds = processingDurationMilliseconds // Stores measured ASR processing duration.
        self.modelID = modelID // Stores optional physical model identity.
    } // Ends transcription-result construction.
} // Ends the transcription result value type.

struct SynthesizedSpeech: Codable, Equatable, Sendable { // Stores filesystem-backed TTS output and operational timings.
    let audioURL: URL // Identifies the generated local audio file.
    let durationSeconds: Double // Stores the generated audio duration when the backend reports it.
    let synthesisDurationMilliseconds: Int // Stores measured text-to-speech processing time.
    let modelID: String? // Stores the actual physical TTS model when supplied by a real backend.

    init(audioURL: URL, durationSeconds: Double, synthesisDurationMilliseconds: Int, modelID: String? = nil) { // Preserves existing call sites while allowing real backend identity.
        self.audioURL = audioURL // Stores the filesystem-backed generated audio.
        self.durationSeconds = durationSeconds // Stores measured generated-audio duration.
        self.synthesisDurationMilliseconds = synthesisDurationMilliseconds // Stores measured TTS process duration.
        self.modelID = modelID // Stores optional physical model identity.
    } // Ends synthesized-speech construction.
} // Ends the synthesized-speech value type.

enum VoiceServiceKind: String, Codable, Equatable, Sendable { // Classifies non-agent Voice operations for later workflow trace integration.
    case microphoneCapture // Identifies press-record audio capture.
    case speechToText // Identifies ASR inference.
    case textToSpeech // Identifies TTS inference.
    case audioPlayback // Identifies local playback of generated speech.
} // Ends the Voice service kind definition.

enum VoiceServiceTraceStatus: String, Codable, Equatable, Sendable { // Describes the outcome of one Voice service operation.
    case succeeded // Indicates that the service operation completed successfully.
    case skipped // Indicates that policy intentionally omitted the service operation.
    case failed // Indicates that the service operation returned a controlled error.
} // Ends the Voice service trace status definition.

struct VoiceServiceTraceEvent: Identifiable, Codable, Equatable, Sendable { // Stores privacy-safe operational metadata for a Voice service step.
    let id: UUID // Gives the event stable identity for later trace rendering.
    let kind: VoiceServiceKind // Identifies the service rather than incorrectly labeling it as an agent.
    let name: String // Stores concise user-facing service identity.
    let durationMilliseconds: Int // Stores measured wall-clock duration.
    let status: VoiceServiceTraceStatus // Stores success, skip, or failure state.
    let detail: String // Stores bounded operational detail without recorded audio contents.

    init( // Creates a trace event while providing a stable default identity.
        id: UUID = UUID(), // Generates a new identity unless a decoded or test identity is supplied.
        kind: VoiceServiceKind, // Accepts the concrete Voice service classification.
        name: String, // Accepts the user-facing operation name.
        durationMilliseconds: Int, // Accepts measured operation duration.
        status: VoiceServiceTraceStatus, // Accepts the operation outcome.
        detail: String // Accepts privacy-safe operational detail.
    ) { // Starts Voice service trace event construction.
        self.id = id // Stores the stable trace-event identity.
        self.kind = kind // Stores the service classification.
        self.name = name // Stores the display name.
        self.durationMilliseconds = durationMilliseconds // Stores the measured duration.
        self.status = status // Stores the operation outcome.
        self.detail = detail // Stores the bounded operational detail.
    } // Ends Voice service trace event construction.
} // Ends the Voice service trace event value type.

struct VoiceDraft: Codable, Equatable, Sendable { // Carries a transcription into the Chat composer with its source metadata intact.
    let text: String // Stores the transcript that should populate the composer rather than auto-send by default.
    let capturedAudio: CapturedAudio // Preserves the local audio reference and technical metadata.
    let transcription: TranscriptionResult // Preserves actual ASR output and timing.
    let traceEvents: [VoiceServiceTraceEvent] // Preserves capture and ASR service events until the user sends the draft.
} // Ends the Voice draft value type.

enum VoiceServiceError: LocalizedError, Codable, Equatable, Sendable { // Defines controlled permission, capture, runtime, transcription, synthesis, and playback failures.
    case permissionDenied // Reports explicit user denial without crashing or retrying automatically.
    case permissionRestricted // Reports a system-policy microphone restriction.
    case permissionUnavailable // Reports an unknown or unavailable microphone authorization state.
    case recordingAlreadyActive // Reports an invalid duplicate start request.
    case recordingNotActive // Reports a stop request made without an active recording.
    case microphoneCaptureFailed(String) // Preserves a bounded AVFoundation capture diagnostic.
    case missingMLXAudioDependency // Reports the absent mlx-audio runtime without inventing commands.
    case speechToTextUnavailable // Reports that no real ASR adapter is connected.
    case textToSpeechUnavailable // Reports that no real TTS adapter is connected.
    case emptyTranscription // Reports an ASR success that returned no usable composer text.
    case invalidSynthesisText // Reports an empty TTS input before backend work begins.
    case audioPlaybackFailed(String) // Preserves a bounded AVFoundation playback diagnostic.
    case runtimeFailed(String) // Preserves a bounded MLX Audio process or output diagnostic.

    var errorDescription: String? { // Produces concise UI-safe messages for every Voice failure.
        switch self { // Selects the message matching the concrete failure.
        case .permissionDenied: return "Microphone access was denied. Enable it in System Settings to use Voice." // Explains denied recovery without opening Settings automatically.
        case .permissionRestricted: return "Microphone access is restricted by system policy." // Explains an authorization state the app cannot change.
        case .permissionUnavailable: return "Microphone authorization is unavailable on this system." // Explains an unknown platform authorization state.
        case .recordingAlreadyActive: return "A microphone recording is already active." // Explains duplicate recording protection.
        case .recordingNotActive: return "No microphone recording is active." // Explains an invalid stop request.
        case let .microphoneCaptureFailed(detail): return "Microphone capture failed: \(detail)" // Preserves the concrete AVFoundation diagnostic.
        case .missingMLXAudioDependency: return "The mlx-audio dependency is not installed in the configured MLX environment." // Reports the exact optional dependency gap.
        case .speechToTextUnavailable: return "Speech-to-text is unavailable because no MLX Audio ASR runtime adapter is connected." // Explains the intentionally incomplete foundation.
        case .textToSpeechUnavailable: return "Text-to-speech is unavailable because no MLX Audio TTS runtime adapter is connected." // Explains the intentionally incomplete foundation.
        case .emptyTranscription: return "Speech-to-text returned an empty transcription." // Rejects unusable ASR output honestly.
        case .invalidSynthesisText: return "Text-to-speech requires non-empty text." // Rejects empty synthesis requests early.
        case let .audioPlaybackFailed(detail): return "Audio playback failed: \(detail)" // Preserves the concrete AVFoundation playback diagnostic.
        case let .runtimeFailed(detail): return "MLX Audio runtime failed: \(detail)" // Preserves a bounded local backend diagnostic.
        } // Ends Voice error message selection.
    } // Ends localized Voice error access.
} // Ends the Voice service error definition.
