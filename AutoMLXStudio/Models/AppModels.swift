import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case chat = "Chat"
    case projects = "Projects" // Opens the native project, document, and Project Memory workspace without changing the selected chat implicitly.
    case agents = "Agents" // Adds the real orchestration registry and trace destination to the existing sidebar order.
    case models = "Models" // Adds the V0.2 physical model registry and runtime destination.
    case remoteModels = "Remote Models" // Exposes manually configured inference servers in the shared sidebar.
    case engineering = "Engineering" // Opens the app-owned bounded engineering workspace.
    case optimize = "Optimize"
    case benchmark = "Benchmark"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .chat: "bubble.left.and.bubble.right"
        case .projects: "folder" // Uses the standard macOS folder metaphor for local project workspaces.
        case .agents: "point.3.connected.trianglepath.dotted" // Uses a native symbol that communicates connected workflow stages.
        case .models: "square.stack.3d.up" // Uses a native symbol for the installed multi-model catalog.
        case .remoteModels: "network" // Identifies LAN inference without implying remote filesystem access.
        case .engineering: "hammer" // Uses the native engineering and build metaphor.
        case .optimize: "wand.and.stars"
        case .benchmark: "speedometer"
        case .settings: "gearshape"
        }
    }
}

enum OptimizationProfile: String, CaseIterable, Identifiable, Codable {
    case speed = "Speed"
    case balanced = "Balanced"
    case quality = "Quality"
    var id: String { rawValue }

    var targetBPW: Double {
        switch self {
        case .speed: 4.5
        case .balanced: 5.0
        case .quality: 5.5
        }
    }

    var lowBits: Int {
        switch self {
        case .speed: 3
        case .balanced: 4
        case .quality: 4
        }
    }

    var highBits: Int {
        switch self {
        case .speed: 5
        case .balanced: 5
        case .quality: 6
        }
    }
}

struct HardwareProfile: Codable {
    var chip: String = "Unknown"
    var memoryGB: Double = 0
    var architecture: String = "arm64"
    var macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
}

enum ChatGenerationStatus: String, Codable, Equatable, Sendable { // Describes only visible message delivery state and never private model reasoning.
    case complete // Indicates a visible user message or finished assistant response.
    case generating // Indicates a transient assistant placeholder that should be replaced as work progresses.
    case cancelled // Indicates the user cancelled before a final stage completed.
    case failed // Indicates no valid assistant candidate could be delivered.
} // Ends visible chat generation states.

struct ChatGenerationMetadata: Codable, Equatable, Sendable { // Persists only provider-neutral operational facts returned by normal Chat inference.
    let target: ModelGenerationTarget // Records the exact backend, location, and requested model used for this response.
    let usage: ModelGenerationUsage? // Preserves token accounting only when the backend actually reports it.
    let durationMilliseconds: Int // Preserves measured end-to-end backend duration for later inspection.
    let finishReason: ModelFinishReason? // Preserves the provider completion reason without inventing one.
    let toolCallCount: Int // Records safely rejected normal-Chat tool calls without storing arguments or executing tools.
    let timeToFirstTokenMilliseconds: Int? // Remains nil until a genuinely streaming backend measures first-token latency.
} // Ends normal Chat generation metadata.

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: String
    let content: String
    let workflowTraceID: UUID? // Links assistant messages to the actual workflow trace without embedding orchestration prompts.
    let attachments: [UserAttachment] // Preserves typed user attachment metadata without raw media bytes.
    let citations: [LocalMemoryCitation] // Persists only citations for exact Project Memory chunks actually injected into the workflow.
    let createdAt: Date // Records the visible message timestamp independently from transient runtime state.
    let generationStatus: ChatGenerationStatus // Records complete, generating, cancelled, or failed visible delivery state.
    let agentID: String? // Stores the actual successful specialist identity when useful for local inspection.
    let modelID: String? // Stores the actual successful specialist model identity when useful for local inspection.
    let generationMetadata: ChatGenerationMetadata? // Stores backend-neutral usage and duration when this message came through the shared dispatcher.

    init(id: UUID = UUID(), role: String, content: String, workflowTraceID: UUID? = nil, attachments: [UserAttachment] = [], citations: [LocalMemoryCitation] = [], createdAt: Date = Date(), generationStatus: ChatGenerationStatus = .complete, agentID: String? = nil, modelID: String? = nil, generationMetadata: ChatGenerationMetadata? = nil) { // Keeps prior call sites source-compatible while enabling durable Project Chat metadata.
        self.id = id
        self.role = role
        self.content = content
        self.workflowTraceID = workflowTraceID // Stores a trace identity only for orchestrated assistant messages.
        self.attachments = attachments // Stores validated URL-backed attachments only on the originating user message.
        self.citations = citations // Stores only actual assembled local sources and remains empty for normal chat.
        self.createdAt = createdAt // Stores the visible delivery timestamp.
        self.generationStatus = generationStatus // Stores the visible delivery state without transient process objects.
        self.agentID = agentID // Stores actual specialist identity only when known.
        self.modelID = modelID // Stores actual physical model identity only when known.
        self.generationMetadata = generationMetadata // Stores only truthful dispatcher metadata when available.
    }

    private enum CodingKeys: String, CodingKey { case id, role, content, workflowTraceID, attachments, citations, createdAt, generationStatus, agentID, modelID, generationMetadata } // Defines stable keys for backward-compatible decoding.

    init(from decoder: Decoder) throws { // Decodes V0.1/V0.2 messages that predate attachments safely.
        let container = try decoder.container(keyedBy: CodingKeys.self) // Opens the keyed persisted message payload.
        id = try container.decode(UUID.self, forKey: .id) // Restores stable message identity.
        role = try container.decode(String.self, forKey: .role) // Restores the chat role.
        content = try container.decode(String.self, forKey: .content) // Restores visible message text.
        workflowTraceID = try container.decodeIfPresent(UUID.self, forKey: .workflowTraceID) // Restores optional workflow linkage.
        attachments = try container.decodeIfPresent([UserAttachment].self, forKey: .attachments) ?? [] // Uses an empty attachment list for all earlier persisted messages.
        citations = try container.decodeIfPresent([LocalMemoryCitation].self, forKey: .citations) ?? [] // Uses no sources for every pre-Project-Chat message.
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0) // Migrates timestamp-free visible history deterministically.
        generationStatus = try container.decodeIfPresent(ChatGenerationStatus.self, forKey: .generationStatus) ?? .complete // Treats every legacy stored message as already delivered.
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID) // Restores actual specialist metadata only when persisted.
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID) // Restores actual physical model metadata only when persisted.
        generationMetadata = try container.decodeIfPresent(ChatGenerationMetadata.self, forKey: .generationMetadata) // Leaves every legacy message without invented dispatcher metadata.
    } // Ends backward-compatible ChatMessage decoding.
}

struct BenchmarkResult: Identifiable, Codable {
    let id: UUID
    let date: Date
    let model: String
    let promptTokensPerSecond: Double
    let generationTokensPerSecond: Double
    let peakMemoryGB: Double
    let profile: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        model: String,
        promptTokensPerSecond: Double,
        generationTokensPerSecond: Double,
        peakMemoryGB: Double,
        profile: String
    ) {
        self.id = id
        self.date = date
        self.model = model
        self.promptTokensPerSecond = promptTokensPerSecond
        self.generationTokensPerSecond = generationTokensPerSecond
        self.peakMemoryGB = peakMemoryGB
        self.profile = profile
    }
}

struct OpenAIChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let max_tokens: Int
}

struct OpenAIChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String? // Accepts reasoning-capable servers that legally omit user-facing content when their token budget ends during private reasoning.
            let reasoning: String? // Decodes separate local-server reasoning metadata so its presence does not break the response contract.

            var userFacingContent: String? { // Returns only safe assistant content and never substitutes private reasoning.
                guard let content else { return nil } // Rejects a reasoning-only response instead of exposing or forwarding chain-of-thought text.
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes server whitespace before accepting the answer.
                return trimmed.isEmpty ? nil : trimmed // Treats empty content as unavailable while retaining non-empty assistant output.
            } // Ends safe content access.
        }
        let message: Message
    }
    let choices: [Choice]
}


struct PersistedState: Codable {
    var benchmarkResults: [BenchmarkResult] = []
    var modelRegistry: ModelRegistry? // Persists V0.2 catalog edits, assignments, and capability preferences while decoding V0.1 state safely.
    var modelSwitchPolicy: ModelSwitchPolicy? // Persists the explicit quality-versus-switching policy while decoding older state safely.
    var speakAssistantResponses: Bool? // Persists the opt-in Voice response preference while decoding earlier state as disabled.
    var sendAutomaticallyAfterTranscription: Bool? // Persists the opt-in Voice draft auto-send preference while older state decodes as disabled.

    init(benchmarkResults: [BenchmarkResult] = [], modelRegistry: ModelRegistry? = nil, modelSwitchPolicy: ModelSwitchPolicy? = nil, speakAssistantResponses: Bool? = nil, sendAutomaticallyAfterTranscription: Bool? = nil) { // Preserves older construction while extending Voice preferences safely.
        self.benchmarkResults = benchmarkResults // Stores benchmark history.
        self.modelRegistry = modelRegistry // Stores optional multi-model registry state.
        self.modelSwitchPolicy = modelSwitchPolicy // Stores optional switching policy.
        self.speakAssistantResponses = speakAssistantResponses // Stores optional TTS playback preference.
        self.sendAutomaticallyAfterTranscription = sendAutomaticallyAfterTranscription // Stores optional Voice draft auto-send preference.
    } // Ends persisted-state construction.
}

enum ModelTestStatus: String { // Describes the user-triggered Models page validation lifecycle.
    case running // Indicates that a model is loading or answering the deterministic test prompt.
    case succeeded // Indicates that loading and non-empty completion validation passed.
    case failed // Indicates validation, loading, or completion failure.
} // Ends model-test status definitions.

struct ModelTestResult: Identifiable { // Stores observable feedback for one Models page Test action.
    var id: String { modelID } // Uses the tested model registry key as stable identity.
    let modelID: String // Identifies the physical model tested.
    let status: ModelTestStatus // Stores running, succeeded, or failed state.
    let message: String // Stores concise load, inference, or failure feedback.
    let loadMilliseconds: Int? // Stores measured model preparation time when available.
    let inferenceMilliseconds: Int? // Stores measured completion time when available.
    let date: Date // Records when the test state was produced.
} // Ends model-test result values.
