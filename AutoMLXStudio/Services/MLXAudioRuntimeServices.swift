import AVFoundation // Supplies authoritative readable-audio duration inspection for ASR input and TTS output.
import Foundation // Supplies JSON decoding, filesystem URLs, timing, and task-safe service values.

typealias RuntimeModelProvider = @MainActor @Sendable () -> ModelProfile? // Resolves the latest persisted model profile when the user invokes a runtime.
typealias RuntimeConfigurationProvider = @MainActor @Sendable () -> ModelRuntimeConfiguration // Resolves the latest configured virtual environment and port policy.

struct MLXASRRuntimeAdapter: SpeechToTextServicing { // Executes Qwen3-ASR through the inspected mlx-audio command-line contract.
    private let modelProvider: RuntimeModelProvider // Supplies the current speech-to-text registry profile.
    private let configurationProvider: RuntimeConfigurationProvider // Supplies the current configured MLX virtual environment.
    private let resourceManager: ModelResourceManager // Coordinates unified-memory safety with text and Vision runtimes.
    private let runner: ManagedPythonProcessRunner // Owns and serializes the exact ASR subprocess.

    init(modelProvider: @escaping RuntimeModelProvider, configurationProvider: @escaping RuntimeConfigurationProvider, resourceManager: ModelResourceManager, runner: ManagedPythonProcessRunner = ManagedPythonProcessRunner()) { // Injects current configuration and exact process ownership boundaries.
        self.modelProvider = modelProvider // Stores late-bound model lookup so folder edits take effect without app restart.
        self.configurationProvider = configurationProvider // Stores late-bound environment lookup so Settings changes take effect.
        self.resourceManager = resourceManager // Stores the central budget and lifecycle authority.
        self.runner = runner // Stores the actor that owns only this service's process.
    } // Ends ASR adapter construction.

    func transcribe(audioURL: URL) async throws -> TranscriptionResult { // Converts one local readable audio file into actual backend transcription output.
        guard FileManager.default.fileExists(atPath: audioURL.path) else { throw VoiceServiceError.microphoneCaptureFailed("Recorded audio file is unavailable.") } // Rejects a missing source before model work.
        let sourceDuration = try Self.audioDuration(at: audioURL) // Validates AVFoundation readability and measures the actual source duration.
        guard let model = await modelProvider() else { throw VoiceServiceError.speechToTextUnavailable } // Requires the current physical ASR registry profile.
        let configuration = await configurationProvider() // Captures one immutable environment snapshot for this transcription.
        let reservation = try await resourceManager.reserveOneShot(model: model, configuration: configuration) // Reserves budgeted Audio ownership and stops text only when the measured policy requires it.
        do { // Runs and parses the exact inspected mlx_audio.stt.generate command.
            let directory = try VoiceTemporaryArtifacts.createOperationDirectory(prefix: "asr") // Creates an isolated app-owned output scope.
            defer { try? FileManager.default.removeItem(at: directory) } // Removes generated transcription metadata after parsing without touching source audio or model files.
            let outputBase = directory.appendingPathComponent("transcription", isDirectory: false) // Defines the CLI output base whose JSON extension is appended by mlx-audio.
            let executable = URL(fileURLWithPath: configuration.executableDirectory, isDirectory: true).appendingPathComponent("mlx_audio.stt.generate", isDirectory: false) // Resolves the installed ASR entrypoint discovered during the environment audit.
            let command = ManagedPythonCommand( // Builds a shell-free offline command from the installed help contract.
                executableURL: executable, // Uses only the configured virtual-environment entrypoint.
                arguments: ["--model", model.launchReference, "--audio", audioURL.path, "--output-path", outputBase.path, "--format", "json", "--max-tokens", "256"], // Supplies actual supported ASR arguments without inventing language or confidence metadata.
                workingDirectoryURL: directory, // Restricts relative artifacts to the app-owned operation directory.
                environment: Self.offlineEnvironment, // Prevents network fallback or weight downloads at runtime.
                timeoutMilliseconds: 120_000 // Bounds local ASR load and inference while allowing cold Apple Silicon startup.
            ) // Ends ASR command construction.
            let result = try await runner.run(command) // Launches and awaits only the exact app-owned process.
            guard result.terminationStatus == 0 else { throw VoiceServiceError.runtimeFailed(Self.failureDetail(result)) } // Rejects a non-zero backend exit with bounded diagnostics.
            let jsonURL = outputBase.appendingPathExtension("json") // Resolves the actual documented JSON output path.
            guard let data = try? Data(contentsOf: jsonURL) else { throw VoiceServiceError.runtimeFailed("ASR completed without its requested JSON output.") } // Requires actual filesystem-backed transcription output.
            let payload: ASROutputPayload // Declares the supported JSON fields returned by the installed package.
            do { payload = try JSONDecoder().decode(ASROutputPayload.self, from: data) } // Decodes text and optional reported language without parsing console prose.
            catch { throw VoiceServiceError.runtimeFailed("ASR JSON could not be decoded: \(Self.bounded(error.localizedDescription))") } // Reports bounded schema mismatch detail.
            let transcript = payload.text.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes actual backend output for the composer.
            guard !transcript.isEmpty else { throw VoiceServiceError.emptyTranscription } // Rejects an unusable successful process result.
            await resourceManager.releaseOneShot(reservation) // Releases the exact Audio budget reservation after process exit and output parsing.
            return TranscriptionResult(transcript: transcript, audioDurationSeconds: sourceDuration, detectedLanguage: payload.language, processingDurationMilliseconds: result.durationMilliseconds, modelID: model.id) // Returns actual text, measured durations, optional backend language, and physical model identity.
        } catch { // Releases central resource ownership on every process, timeout, cancellation, or parsing failure.
            await resourceManager.releaseOneShot(reservation) // Releases only this adapter's exact reservation.
            throw error // Preserves the typed runtime or Voice failure.
        } // Ends ASR process recovery.
    } // Ends real local transcription.

    private static let offlineEnvironment = ["HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_DATASETS_OFFLINE": "1"] // Enforces offline-first behavior across Hugging Face-backed libraries.

    private static func audioDuration(at url: URL) throws -> Double { // Measures an audio file through AVFoundation rather than estimating from bytes.
        do { // Opens the audio container and validates frame metadata.
            let file = try AVAudioFile(forReading: url) // Requires an AVFoundation-readable source.
            guard file.processingFormat.sampleRate > 0 else { throw VoiceServiceError.microphoneCaptureFailed("Audio sample rate is invalid.") } // Prevents divide-by-zero duration calculation.
            let duration = Double(file.length) / file.processingFormat.sampleRate // Calculates real duration from decoded frames and sample rate.
            guard duration > 0 else { throw VoiceServiceError.microphoneCaptureFailed("Audio duration is zero.") } // Rejects header-only or empty captures.
            return duration // Returns actual decoded duration seconds.
        } catch let error as VoiceServiceError { throw error } // Preserves controlled validation diagnostics.
        catch { throw VoiceServiceError.microphoneCaptureFailed(Self.bounded(error.localizedDescription)) } // Converts AVFoundation failure into the Voice domain.
    } // Ends source-audio duration inspection.

    private static func failureDetail(_ result: ManagedPythonResult) -> String { // Selects bounded useful process diagnostics without flooding UI or traces.
        let diagnostic = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines) // Prefers the backend diagnostic stream.
        let fallback = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) // Falls back to standard output when needed.
        return bounded(diagnostic.isEmpty ? (fallback.isEmpty ? "ASR exited with status \(result.terminationStatus)." : fallback) : diagnostic) // Returns one bounded flattened explanation.
    } // Ends ASR process failure formatting.

    private static func bounded(_ text: String) -> String { // Produces trace-safe compact backend detail.
        String(text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds length.
    } // Ends backend detail bounding.
} // Ends real MLX Audio ASR adapter.

struct MLXTTSRuntimeAdapter: TextToSpeechServicing { // Executes Qwen3-TTS through the inspected mlx-audio command-line contract.
    private let modelProvider: RuntimeModelProvider // Supplies the current text-to-speech registry profile.
    private let configurationProvider: RuntimeConfigurationProvider // Supplies the current configured MLX virtual environment.
    private let resourceManager: ModelResourceManager // Coordinates unified-memory safety with text and Vision runtimes.
    private let runner: ManagedPythonProcessRunner // Owns and serializes the exact TTS subprocess.

    init(modelProvider: @escaping RuntimeModelProvider, configurationProvider: @escaping RuntimeConfigurationProvider, resourceManager: ModelResourceManager, runner: ManagedPythonProcessRunner = ManagedPythonProcessRunner()) { // Injects current configuration and exact process ownership boundaries.
        self.modelProvider = modelProvider // Stores late-bound model lookup for persisted path edits.
        self.configurationProvider = configurationProvider // Stores late-bound environment lookup for Settings edits.
        self.resourceManager = resourceManager // Stores central budget and lifecycle authority.
        self.runner = runner // Stores exact one-shot TTS process ownership.
    } // Ends TTS adapter construction.

    func synthesize(text: String) async throws -> SynthesizedSpeech { // Generates a real local WAV without autoplay.
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only leading and trailing whitespace.
        guard !normalizedText.isEmpty else { throw VoiceServiceError.invalidSynthesisText } // Rejects empty backend work early.
        guard let model = await modelProvider() else { throw VoiceServiceError.textToSpeechUnavailable } // Requires the current physical TTS registry profile.
        let configuration = await configurationProvider() // Captures one immutable environment snapshot for synthesis.
        let reservation = try await resourceManager.reserveOneShot(model: model, configuration: configuration) // Reserves budgeted Audio ownership before process launch.
        var operationDirectory: URL? // Retains the exact app-owned output scope so failures can clean it immediately.
        do { // Runs and validates the exact inspected mlx_audio.tts.generate command.
            try VoiceTemporaryArtifacts.cleanupExpiredGeneratedAudio() // Removes only old app-owned generated audio before creating a new result.
            let directory = try VoiceTemporaryArtifacts.createOperationDirectory(prefix: "tts") // Creates an isolated app-owned output scope that survives until playback cleanup.
            operationDirectory = directory // Retains exact containment-proven ownership until a validated WAV is returned.
            let executable = URL(fileURLWithPath: configuration.executableDirectory, isDirectory: true).appendingPathComponent("mlx_audio.tts.generate", isDirectory: false) // Resolves the installed TTS entrypoint discovered during audit.
            let command = ManagedPythonCommand( // Builds a shell-free offline command from the installed help contract.
                executableURL: executable, // Uses only the configured virtual-environment entrypoint.
                arguments: ["--model", model.launchReference, "--text", normalizedText, "--voice", "Ryan", "--lang_code", "English", "--max_tokens", "1024", "--output_path", directory.path, "--file_prefix", "assistant-speech", "--audio_format", "wav", "--join_audio"], // Uses the tested local base-model voice and never passes --play.
                workingDirectoryURL: directory, // Restricts all generated artifacts to the app-owned operation directory.
                environment: MLXASRRuntimeAdapter.offlineEnvironmentForServices, // Enforces the same offline-first package behavior as ASR.
                timeoutMilliseconds: 180_000 // Bounds cold TTS loading and generation conservatively.
            ) // Ends TTS command construction.
            let result = try await runner.run(command) // Launches and awaits only the exact app-owned TTS process.
            guard result.terminationStatus == 0 else { throw VoiceServiceError.runtimeFailed(Self.failureDetail(result)) } // Rejects a non-zero backend exit.
            let audioURL = try Self.generatedWAV(in: directory) // Finds the actual generated WAV within the isolated operation scope.
            let duration = try Self.audioDuration(at: audioURL) // Verifies AVFoundation readability and derives true duration.
            let fileSize = ((try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) // Reads actual generated file size.
            guard fileSize > 44 else { throw VoiceServiceError.runtimeFailed("TTS output contains no audio payload.") } // Rejects a trivial WAV header-only artifact.
            await resourceManager.releaseOneShot(reservation) // Releases Audio budget ownership after confirmed process exit and output validation.
            return SynthesizedSpeech(audioURL: audioURL, durationSeconds: duration, synthesisDurationMilliseconds: result.durationMilliseconds, modelID: model.id) // Returns real filesystem, duration, timing, and model evidence.
        } catch { // Releases central ownership and removes failed app-owned output scopes.
            await resourceManager.releaseOneShot(reservation) // Releases only this adapter's exact reservation.
            if let operationDirectory { VoiceTemporaryArtifacts.removeGeneratedOperationDirectory(at: operationDirectory) } // Removes only the exact failed app-owned generation scope immediately.
            throw error // Preserves typed timeout, cancellation, validation, or backend failure.
        } // Ends TTS process recovery.
    } // Ends real local speech synthesis.

    private static func generatedWAV(in directory: URL) throws -> URL { // Resolves the actual CLI output without assuming undocumented suffixes.
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? [] // Reads only the isolated operation directory.
        let waveFiles = files.filter { $0.pathExtension.lowercased() == "wav" } // Restricts selection to requested WAV output.
        guard let output = waveFiles.max(by: { fileSize(of: $0) < fileSize(of: $1) }) else { throw VoiceServiceError.runtimeFailed("TTS completed without a WAV output file.") } // Selects the largest actual WAV when the CLI emits segments and a joined file.
        return output // Returns the filesystem-backed generated speech.
    } // Ends TTS output resolution.

    private static func fileSize(of url: URL) -> Int { // Reads actual file size for deterministic TTS output selection.
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 // Returns zero only when filesystem metadata is unavailable.
    } // Ends TTS output-size lookup.

    private static func audioDuration(at url: URL) throws -> Double { // Measures generated speech through AVFoundation.
        do { // Opens and validates the generated audio container.
            let file = try AVAudioFile(forReading: url) // Requires AVFoundation-readable WAV output.
            guard file.processingFormat.sampleRate > 0 else { throw VoiceServiceError.runtimeFailed("TTS output sample rate is invalid.") } // Prevents invalid duration calculation.
            let duration = Double(file.length) / file.processingFormat.sampleRate // Derives actual duration from decoded frame count.
            guard duration > 0 else { throw VoiceServiceError.runtimeFailed("TTS output duration is zero.") } // Rejects empty synthesis honestly.
            return duration // Returns actual generated seconds.
        } catch let error as VoiceServiceError { throw error } // Preserves controlled output validation failures.
        catch { throw VoiceServiceError.runtimeFailed("TTS output is unreadable: \(bounded(error.localizedDescription))") } // Converts AVFoundation failure into bounded backend detail.
    } // Ends generated-audio duration inspection.

    private static func failureDetail(_ result: ManagedPythonResult) -> String { // Selects bounded useful TTS process diagnostics.
        let diagnostic = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines) // Prefers the backend diagnostic stream.
        let fallback = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) // Falls back to standard output.
        return bounded(diagnostic.isEmpty ? (fallback.isEmpty ? "TTS exited with status \(result.terminationStatus)." : fallback) : diagnostic) // Returns one bounded explanation.
    } // Ends TTS process failure formatting.

    private static func bounded(_ text: String) -> String { // Produces trace-safe compact backend detail.
        String(text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds length.
    } // Ends backend detail bounding.
} // Ends real MLX Audio TTS adapter.

private struct ASROutputPayload: Decodable { // Decodes only actual stable fields needed from mlx-audio JSON output.
    let text: String // Stores the backend transcript.
    let language: String? // Stores language only when the backend explicitly emits it.
} // Ends ASR output payload.

enum VoiceTemporaryArtifacts { // Owns temporary output creation and conservative cleanup independently from model directories.
    private static let rootName = "AutoMLXStudioVoice/Generated" // Defines the app-specific temporary namespace.

    static func createOperationDirectory(prefix: String) throws -> URL { // Creates one isolated output directory below the app-owned temporary root.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true) // Resolves the app-owned generated-audio root.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates only the temporary namespace.
        let directory = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true) // Creates an unguessable operation scope.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) // Requires a new exact directory.
        return directory // Returns the isolated writable scope.
    } // Ends operation-directory creation.

    static func cleanupExpiredGeneratedAudio(now: Date = Date()) throws { // Removes only app-owned generated operation directories older than one day.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true) // Resolves the exact app-owned root.
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return } // Treats an absent root as already clean.
        for directory in directories { // Inspects each direct app-owned operation scope.
            let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]) // Reads only metadata needed for bounded cleanup.
            guard values?.isDirectory == true, let modified = values?.contentModificationDate, now.timeIntervalSince(modified) > 86_400 else { continue } // Preserves recent and non-directory artifacts.
            try? FileManager.default.removeItem(at: directory) // Removes only the exact expired app-owned operation scope.
        } // Ends expired operation iteration.
    } // Ends conservative temporary cleanup.

    static func removeGeneratedAudio(at audioURL: URL) { // Removes an exact generated operation directory only when containment is proven.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true).standardizedFileURL // Resolves the canonical app-owned root.
        let file = audioURL.standardizedFileURL // Normalizes the supplied playback reference.
        guard file.path.hasPrefix(root.path + "/") else { return } // Never removes user recordings, imports, or model artifacts.
        let operationDirectory = file.deletingLastPathComponent() // Resolves the immediate app-owned generation scope.
        guard operationDirectory.deletingLastPathComponent() == root else { return } // Requires exactly one scope level below the owned root.
        try? FileManager.default.removeItem(at: operationDirectory) // Removes the exact generated scope after playback ownership ends.
    } // Ends exact generated-audio cleanup.

    static func removeGeneratedOperationDirectory(at directoryURL: URL) { // Removes a failed operation scope only when exact one-level containment is proven.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true).standardizedFileURL // Resolves the canonical app-owned root.
        let directory = directoryURL.standardizedFileURL // Normalizes the supplied operation scope.
        guard directory.deletingLastPathComponent() == root else { return } // Rejects user folders, model folders, the root itself, and nested arbitrary paths.
        try? FileManager.default.removeItem(at: directory) // Removes only the exact app-owned failed operation directory.
    } // Ends failed operation cleanup.
} // Ends Voice temporary artifact ownership.

private extension MLXASRRuntimeAdapter { // Shares the audited offline environment with the separate TTS adapter without widening public API.
    static var offlineEnvironmentForServices: [String: String] { offlineEnvironment } // Returns the immutable offline package environment.
} // Ends offline environment sharing.
