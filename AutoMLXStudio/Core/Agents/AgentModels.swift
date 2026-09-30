import Foundation // Supplies UUID, Codable, and collection support used by the agent domain types.

enum AgentKind: String, Codable, CaseIterable { // Classifies an agent by its orchestration responsibility.
    case core // Identifies a core orchestration component that may later become model-backed.
    case specialist // Identifies an agent that produces the first domain-specific answer.
    case engineering // Identifies the bounded workspace-and-tool orchestration agent introduced in V0.6.
    case reviewer // Identifies an agent that validates and improves a candidate answer.
    case output // Identifies an agent that prepares the final user-facing response.
    case service // Identifies a dedicated bounded service represented as a logical product role.

    var displayName: String { // Converts the stored enum value into concise UI copy.
        switch self { // Selects the label that corresponds to the current kind.
        case .core: return "Core" // Labels core orchestration components.
        case .specialist: return "Specialist" // Labels domain specialist agents.
        case .engineering: return "Engineering" // Labels the one permission-controlled coding-workspace agent.
        case .reviewer: return "Reviewer" // Labels quality-review agents.
        case .output: return "Output" // Labels final-output agents.
        case .service: return "Service" // Labels ASR, TTS, and deterministic retrieval truthfully.
        } // Ends the kind-to-label mapping.
    } // Ends the display-name accessor.
} // Ends the agent-kind definition.

enum ModelCapability: String, Codable, CaseIterable, Hashable { // Defines capabilities that models and agents can declare explicitly.
    case general // Represents broad conversational and knowledge work.
    case reasoning // Represents validation, synthesis, and multi-step reasoning work.
    case coding // Represents source-code generation and debugging work.
    case swiftLanguage = "swift" // Represents specialist Swift and Apple-platform development work.
    case research // Represents source-oriented analysis performed from available context.
    case translation // Represents multilingual translation and localization work.
    case vision // Reserves support for future image-understanding models.
    case speechToText // Reserves support for future speech-recognition models.
    case textToSpeech // Reserves support for future speech-synthesis models.
    case embedding // Reserves support for future vector-embedding models.
    case reranking // Reserves support for future retrieval reranking models.
    case imageGeneration // Leaves a typed extension point for later image generation.
    case video // Leaves a typed extension point for later video processing.
    case audioAnalysis // Leaves a typed extension point for later non-speech audio analysis.
    case planning // Records verified bounded task-decomposition suitability when known.
    case debugging // Records verified fault-diagnosis suitability when known.
    case reviewing // Records verified candidate-critique suitability when known.
    case toolUse // Records verified structured tool-call support when known.
    case longContext // Records a verified extended usable context window when known.

    var displayName: String { // Produces a stable human-readable capability label.
        switch self { // Selects a readable label for every persisted capability value.
        case .general: return "General" // Labels broad conversational capability.
        case .reasoning: return "Reasoning" // Labels validation and synthesis capability.
        case .coding: return "Coding" // Labels general programming capability.
        case .swiftLanguage: return "Swift" // Labels Swift and Apple-platform capability.
        case .research: return "Research" // Labels context-oriented research capability.
        case .translation: return "Translation" // Labels multilingual translation capability.
        case .vision: return "Vision" // Labels future image-understanding capability.
        case .speechToText: return "Speech to Text" // Labels future speech recognition capability.
        case .textToSpeech: return "Text to Speech" // Labels future speech synthesis capability.
        case .embedding: return "Embedding" // Labels future vector embedding capability.
        case .reranking: return "Reranking" // Labels future retrieval reranking capability.
        case .imageGeneration: return "Image Generation" // Labels the future image-generation extension point.
        case .video: return "Video" // Labels the future video extension point.
        case .audioAnalysis: return "Audio Analysis" // Labels the future general-audio extension point.
        case .planning: return "Planning" // Labels task-decomposition capability.
        case .debugging: return "Debugging" // Labels fault-diagnosis capability.
        case .reviewing: return "Reviewing" // Labels candidate-critique capability.
        case .toolUse: return "Tool Use" // Labels structured tool calls.
        case .longContext: return "Long Context" // Labels extended usable context.
        } // Ends capability-label selection.
    } // Ends the capability label accessor.
} // Ends the model-capability definition.

struct AgentDefinition: Identifiable, Codable, Equatable { // Stores one centrally registered LLM agent configuration.
    let id: String // Provides the stable registry key used by workflow plans.
    let name: String // Provides the user-facing agent name.
    let kind: AgentKind // Describes the agent's orchestration role.
    let systemPrompt: String // Keeps the agent's instructions out of views and workflow call sites.
    let requiredCapabilities: Set<ModelCapability> // Declares the capabilities required from an assigned model.
    var operatingPolicy: AgentOperatingPolicy { AgentPolicyRegistry.policy(for: id) } // Resolves host permissions and context limits from code, not model prose.
} // Ends the agent-definition value type.

enum AgentID { // Centralizes identifiers so routing and execution never repeat raw keys.
    static let general = "general-agent" // Identifies the general-purpose specialist.
    static let coding = "coding-agent" // Identifies the general software-development specialist.
    static let engineering = "engineering-agent" // Identifies the bounded V0.6 agent that may request centrally controlled Mac tools.
    static let planner = "planner-agent" // Identifies the bounded advisory task planner.
    static let debugger = "debugging-agent" // Identifies the fault-diagnosis specialist.
    static let asr = "asr-agent" // Identifies the dedicated speech-recognition role.
    static let tts = "tts-agent" // Identifies the dedicated speech-synthesis role.
    static let retrieval = "retrieval-agent" // Identifies the isolated Project Memory retrieval role.
    static let swift = "swift-agent" // Identifies the Apple-development specialist.
    static let research = "research-agent" // Identifies the context-only research specialist.
    static let python = "python-agent" // Identifies the logical Python specialist that shares the installed coding model.
    static let cAndCpp = "c-cpp-agent" // Identifies the logical C and C++ specialist that shares the installed coding model.
    static let cpp = cAndCpp // Provides a concise source-compatible alias for C and C++ routing call sites.
    static let cFamily = cAndCpp // Provides a descriptive alias without registering a duplicate logical agent.
    static let cSharp = "csharp-agent" // Identifies the logical C# and .NET specialist that shares the installed coding model.
    static let csharp = cSharp // Provides a conventional lowercase-sharp alias without registering a duplicate logical agent.
    static let web = "web-agent" // Identifies the logical frontend and web-development specialist that shares the installed coding model.
    static let database = "database-agent" // Identifies the logical relational-database specialist that shares the installed coding model.
    static let math = "math-agent" // Identifies the logical mathematics specialist that shares the installed reasoning model.
    static let data = "data-agent" // Identifies the logical data-analysis specialist that shares the installed reasoning model.
    static let document = "document-agent" // Identifies the logical document-transformation specialist that shares the installed general model.
    static let vision = "vision-agent" // Identifies the V0.3 image-understanding specialist.
    static let reviewer = "reviewer-agent" // Identifies the quality-review agent.
    static let finalComposer = "final-composer" // Identifies the final response composer.
} // Ends the central agent identifier namespace.

enum UserIntent: String, Codable, CaseIterable, Identifiable { // Defines every intent supported by the V0.1 router.
    case general // Routes broad questions to the general agent.
    case coding // Routes general development work to the coding agent.
    case swift // Routes Apple-platform development work to the Swift agent.
    case research // Routes documentation and source-oriented work to the research agent.
    case python // Routes explicit Python development work to the Python specialist.
    case cpp // Routes explicit C and C++ development work to the C/C++ specialist.
    case cSharp = "csharp" // Routes explicit C# and .NET development work to the C# specialist.
    case web // Routes frontend and web-development work to the Web specialist without implying internet access.
    case database // Routes SQL and relational-modeling work to the Database specialist without implying database execution.
    case math // Routes explicit mathematical reasoning work to the Math specialist.
    case data // Routes structured-data analysis work to the Data specialist.
    case document // Routes summarization, rewriting, and structured extraction to the Document specialist.
    case vision // Routes image attachments and explicit visual-analysis requests to Vision Agent.

    var id: String { rawValue } // Makes each intent directly usable by SwiftUI collections.

    static var cAndCpp: UserIntent { .cpp } // Provides a descriptive alias while keeping one persisted C/C++ intent value.
    static var cFamily: UserIntent { .cpp } // Provides a language-family alias without creating another route.
    static var csharp: UserIntent { .cSharp } // Provides a conventional lowercase-sharp alias for callers.
} // Ends the supported-intent definition.

struct RoutingDecision: Equatable { // Carries structured output from the fast router to the director.
    let intent: UserIntent // Stores the selected request category.
    let confidence: Double // Stores an operational confidence score for future router comparison.
    let summary: String // Stores a short operational explanation without model reasoning.
    let requiresVisionAnalysis: Bool // Indicates that a real Vision prelude must run even when a technical specialist owns the final domain response.

    init(intent: UserIntent, confidence: Double, summary: String, requiresVisionAnalysis: Bool = false) { // Preserves all V0.1 call sites while enabling deterministic Vision-assisted routing.
        self.intent = intent // Stores the selected domain intent.
        self.confidence = confidence // Stores the operational confidence.
        self.summary = summary // Stores the trace-safe route explanation.
        self.requiresVisionAnalysis = requiresVisionAnalysis // Stores whether image evidence must precede the specialist.
    } // Ends routing-decision construction.
} // Ends the structured routing decision.

enum WorkflowQualityPolicy: String, Codable { // Defines when the workflow should run the optional QA and composition stages.
    case full // Runs specialist, reviewer, and final composer for normal requests.
    case direct // Returns a specialist answer directly for narrowly defined trivial questions.
} // Ends the workflow-quality policy definition.

struct WorkflowExecutionPlan: Equatable { // Captures the director's deterministic plan for one request.
    let intent: UserIntent // Preserves the router intent used to create the plan.
    let specialistID: String // Identifies the specialist selected by the centralized mapping.
    let secondarySpecialistID: String? // Identifies at most one bounded supporting specialist for an explicit compound request.
    let reviewerID: String // Identifies the reviewer stage when the full policy is active.
    let finalComposerID: String // Identifies the output stage when the full policy is active.
    let qualityPolicy: WorkflowQualityPolicy // Records whether optional quality stages should execute.
    let requiresVisionAnalysis: Bool // Records whether Vision must produce structured evidence before the selected specialist.
    let nextLikelyModelID: String? // Exposes a future prefetch hint without starting simultaneous loading.

    init(intent: UserIntent, specialistID: String, reviewerID: String, finalComposerID: String, qualityPolicy: WorkflowQualityPolicy, requiresVisionAnalysis: Bool = false, nextLikelyModelID: String? = nil, secondarySpecialistID: String? = nil) { // Preserves every existing initializer call while adding one bounded optional supporting specialist.
        self.intent = intent // Stores router intent.
        self.specialistID = specialistID // Stores the selected specialist.
        self.secondarySpecialistID = secondarySpecialistID // Stores zero or one supporting specialist without recursive planning.
        self.reviewerID = reviewerID // Stores the review stage.
        self.finalComposerID = finalComposerID // Stores the output stage.
        self.qualityPolicy = qualityPolicy // Stores direct or full quality policy.
        self.requiresVisionAnalysis = requiresVisionAnalysis // Stores the required real Vision prelude.
        self.nextLikelyModelID = nextLikelyModelID // Stores documentation-only predictive metadata without resource mutation.
    } // Ends workflow-plan construction.
} // Ends the workflow execution-plan type.
