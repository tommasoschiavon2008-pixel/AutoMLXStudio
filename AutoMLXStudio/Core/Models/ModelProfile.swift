import Foundation // Supplies Codable, Hashable, and filesystem-friendly value types.

enum ModelBackend: String, Codable, CaseIterable, Hashable { // Identifies the runtime family independently from a physical model.
    case mlxLM // Runs text generation through the existing mlx-lm server.
    case mlxVLM // Reserves image-and-text inference through a future MLX VLM runtime.
    case mlxAudio // Reserves speech and audio inference through a future MLX audio runtime.
    case embedding // Reserves vector generation through a future embedding runtime.
    case reranker // Reserves retrieval reranking through a future reranker runtime.

    var displayName: String { // Produces concise backend labels for Models UI.
        switch self { // Selects the label for the current runtime family.
        case .mlxLM: return "MLX LM" // Labels the active V0.2 text backend.
        case .mlxVLM: return "MLX VLM" // Labels the future vision backend.
        case .mlxAudio: return "MLX Audio" // Labels the future speech and audio backend.
        case .embedding: return "Embedding" // Labels the future embedding backend.
        case .reranker: return "Reranker" // Labels the future reranking backend.
        } // Ends backend-label selection.
    } // Ends the backend display-name accessor.
} // Ends model-backend definitions.

enum ModelInstallationState: String, Codable, CaseIterable, Hashable { // Describes whether a physical model can be resolved locally.
    case installed // Indicates that the configured model source passed local validation.
    case notInstalled // Indicates that the expected local folder is absent.
    case downloading // Indicates that a folder exists but its externally managed download is incomplete.
    case invalid // Indicates that a folder exists but required model files are missing.

    var displayName: String { // Produces a readable installation label for Models UI.
        switch self { // Selects a label for the current installation state.
        case .installed: return "Installed" // Labels a validated local or migrated legacy model.
        case .notInstalled: return "Not installed" // Labels an absent optional catalog model.
        case .downloading: return "Downloading / incomplete" // Labels a partial external download without calling it corrupt.
        case .invalid: return "Invalid" // Labels an incomplete or incompatible local folder.
        } // Ends installation-label selection.
    } // Ends installation display-name access.
} // Ends model-installation definitions.

enum ModelRuntimeState: String, Codable, CaseIterable, Hashable { // Describes one model's current single-server lifecycle state.
    case installed // Indicates that installation was found before a runtime decision was made.
    case unloaded // Indicates that the model is usable but not resident in the server.
    case loading // Indicates that a serialized server transition is loading the model.
    case loaded // Indicates that the model is the one active text model.
    case stopping // Indicates that the active server process is being stopped.
    case failed // Indicates that the most recent load or inference attempt failed.
    case unavailable // Indicates that the model cannot currently be launched.

    var displayName: String { // Produces concise lifecycle text for UI and traces.
        rawValue.capitalized // Capitalizes the stable persisted runtime-state value.
    } // Ends runtime-state display access.
} // Ends model-runtime definitions.

struct ModelProfile: Identifiable, Codable, Hashable { // Describes a physical or repository-backed model independently from agents.
    let id: String // Stores a stable registry key, normally the full repository identifier.
    var displayName: String // Stores concise user-facing model identity.
    var repositoryID: String // Stores the Hugging Face repository or compatible runtime reference.
    var localPath: String? // Stores an optional validated or expected offline model folder.
    var backend: ModelBackend // Stores the runtime family required to execute this model.
    var capabilities: Set<ModelCapability> // Declares work this model is expected to support.
    var approximateDiskGB: Double? // Stores detected or catalog disk size when available.
    var approximateMemoryGB: Double? // Stores an informational memory estimate for planning.
    var enabled: Bool // Stores whether deterministic routing may select this model.
    var installationState: ModelInstallationState // Stores the most recent offline installation inspection.
    var runtimeState: ModelRuntimeState // Stores the most recent resource-manager lifecycle state.
    var isLegacyFallback: Bool // Marks the migrated V0.1 model that remains the final compatibility fallback.
    var statusDetail: String? // Stores a bounded validation or runtime failure diagnostic.

    var launchReference: String { // Selects the exact reference supplied to mlx-lm.
        if installationState == .installed, let localPath, !localPath.isEmpty { return localPath } // Prefers validated local files to avoid network dependence.
        return repositoryID // Preserves the repository reference for the migrated working V0.1 model.
    } // Ends runtime launch-reference selection.

    var completionModel: LLMModel { // Adapts a V0.2 profile to the existing typed completion client.
        LLMModel(id: launchReference, name: displayName, repository: repositoryID, capabilities: capabilities) // Keeps networking independent from registry persistence.
    } // Ends completion-model adaptation.

    var supportsTextChat: Bool { // Prevents future backends from entering the V0.2 chat pipeline.
        backend == .mlxLM // Allows only the existing working text server in V0.2.
    } // Ends text-chat compatibility access.
} // Ends the V0.2 model-profile value type.

enum Project5ModelCatalog { // Centralizes stable repository identifiers used by catalog, assignments, tests, and documentation.
    static let general = "mlx-community/Qwen3-8B-4bit" // Identifies the recommended general and composition model.
    static let coding = "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit" // Identifies the recommended coding and Swift model.
    static let reasoning = "mlx-community/DeepSeek-R1-0528-Qwen3-8B-4bit" // Identifies the recommended review and reasoning model.
    static let translation = "mlx-community/translategemma-4b-it-4bit" // Identifies the future translation model.
    static let vision = "mlx-community/Qwen3-VL-8B-Instruct-4bit" // Identifies the V0.3 vision model actually stored in Project5.
    static let speechToText = "mlx-community/Qwen3-ASR-0.6B-4bit" // Identifies the future V0.3 speech-recognition model.
    static let textToSpeech = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit" // Identifies the V0.3 speech-synthesis model actually stored in Project5.
    static let embedding = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ" // Identifies the future V0.4 embedding model.
    static let reranker = "mlx-community/Qwen3-Reranker-0.6B-4bit" // Identifies the future V0.4 reranking model.
    static let defaultRoot = "/Volumes/Crucial X9 Pro/app/Models/Project5" // Stores the requested offline Project 5 model root.
    static let deprecatedVision = "mlx-community/Qwen3.5-9B-MLX-4bit" // Identifies the obsolete V0.2 Vision placeholder for persisted-state migration.
    static let deprecatedTextToSpeech = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-5bit" // Identifies the obsolete V0.2 TTS placeholder for persisted-state migration.
} // Ends catalog identifier definitions.
