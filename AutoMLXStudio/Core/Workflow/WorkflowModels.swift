import Foundation // Supplies UUID and Date for workflow trace records.

enum WorkflowStageKind: String, Codable, CaseIterable, Sendable { // Groups trace stages by operational responsibility without exposing prompts or reasoning.
    case routing // Identifies deterministic request classification and planning work.
    case agent // Identifies a model-backed specialist, reviewer, or composer operation.
    case service // Identifies non-agent Voice and local media services.
    case retrieval // Identifies deterministic Project Memory decision, search, and context assembly services.
    case modelResource // Identifies model selection, loading, reuse, switching, or release work.
    case validation // Identifies input and attachment validation work.
    case output // Identifies final user-visible delivery or playback work.

    var displayName: String { // Produces a concise category label for workflow inspection UI.
        switch self { // Selects the user-facing category name.
        case .routing: return "Routing" // Labels deterministic routing and planning.
        case .agent: return "Agent" // Labels an LLM or VLM agent stage.
        case .service: return "Service" // Labels an ASR, TTS, or microphone service.
        case .retrieval: return "Retrieval" // Labels Project Memory services separately from reasoning agents.
        case .modelResource: return "Model resource" // Labels physical model lifecycle work.
        case .validation: return "Validation" // Labels attachment and input checks.
        case .output: return "Output" // Labels final playback or user delivery.
        } // Ends category-label selection.
    } // Ends workflow-stage-kind display access.
} // Ends typed workflow-stage categories.

enum WorkflowStage: String, Codable, CaseIterable { // Defines operational stages used by legacy and V0.2 multi-model traces.
    case attachmentValidation = "Attachment Validation" // Represents read-only media validation before routing.
    case microphoneCapture = "Microphone Capture" // Represents press-record audio capture as a service rather than an agent.
    case speechToText = "Speech-to-Text" // Represents ASR processing as a backend service.
    case fastRouter = "Fast Router" // Represents deterministic intent classification.
    case director = "Director" // Represents deterministic plan creation.
    case memoryDecision = "Memory Decision" // Represents deterministic project, preference, document, and request eligibility evaluation.
    case retrieval = "Retrieval" // Represents project-isolated lexical, embedding, hybrid, or reranked search.
    case contextAssembly = "Context Assembly" // Represents bounded untrusted-data prompt context selection.
    case modelRouter = "Model Router" // Represents deterministic agent-to-physical-model selection.
    case modelResource = "Model Resource" // Represents model reuse, load, or serialized server switching.
    case specialist = "Specialist" // Represents the selected specialist inference.
    case secondarySpecialist = "Secondary Specialist" // Represents the optional single bounded supporting specialist in a compound plan.
    case reviewer = "Reviewer" // Represents optional quality review inference.
    case finalComposer = "Final Composer" // Represents optional final response composition inference.
    case textToSpeech = "Text-to-Speech" // Represents optional response synthesis after text is safely stored.
    case audioPlayback = "Audio Playback" // Represents explicit local playback of synthesized speech.

    var kind: WorkflowStageKind { // Maps every concrete trace stage to one stable visual and analytical category.
        switch self { // Selects the typed category for the concrete stage.
        case .attachmentValidation: return .validation // Classifies media inspection as validation.
        case .fastRouter, .director: return .routing // Classifies deterministic request decisions as routing.
        case .memoryDecision, .retrieval, .contextAssembly: return .retrieval // Classifies Project Memory work as deterministic services rather than agents.
        case .modelRouter, .modelResource: return .modelResource // Classifies physical selection and residency as resource work.
        case .specialist, .secondarySpecialist, .reviewer, .finalComposer: return .agent // Classifies model-backed answer stages as agents.
        case .microphoneCapture, .speechToText, .textToSpeech: return .service // Classifies Voice work as non-agent services.
        case .audioPlayback: return .output // Classifies audible delivery as an output stage.
        } // Ends concrete-stage mapping.
    } // Ends typed stage-kind access.
} // Ends the workflow-stage definition.

enum WorkflowStepStatus: String, Codable { // Describes the result of an individual workflow stage.
    case succeeded // Indicates that the stage completed successfully.
    case skipped // Indicates that policy intentionally omitted the stage.
    case failed // Indicates that the stage encountered an operational error.
} // Ends the workflow-step status definition.

struct WorkflowStep: Identifiable, Codable, Equatable { // Stores operational metadata for one workflow stage.
    let id: UUID // Gives the stage a stable identity for SwiftUI rendering.
    let stage: WorkflowStage // Identifies which stage the metadata describes.
    let name: String // Stores the concrete stage or selected-agent name shown in the UI.
    let detail: String // Stores a concise operational result without chain-of-thought content.
    let durationMilliseconds: Int // Stores elapsed wall-clock time for the stage.
    let status: WorkflowStepStatus // Stores success, skip, or failure state.

    init( // Provides defaults for values that each workflow stage creates consistently.
        id: UUID = UUID(), // Generates a trace-local identity unless a decoded value is supplied.
        stage: WorkflowStage, // Accepts the stage represented by this record.
        name: String, // Accepts the user-facing stage name.
        detail: String, // Accepts operational metadata safe for display.
        durationMilliseconds: Int, // Accepts measured elapsed time.
        status: WorkflowStepStatus // Accepts the stage outcome.
    ) { // Starts construction of a workflow-step value.
        self.id = id // Stores the stable step identity.
        self.stage = stage // Stores the workflow stage.
        self.name = name // Stores the display name.
        self.detail = detail // Stores the safe operational detail.
        self.durationMilliseconds = durationMilliseconds // Stores the elapsed duration.
        self.status = status // Stores the execution status.
    } // Ends workflow-step construction.
} // Ends the workflow-step value type.

struct WorkflowModelExecution: Identifiable, Codable, Equatable { // Stores V0.2 physical model metadata for one agent inference attempt.
    let id: UUID // Gives repeated fallback attempts stable SwiftUI identity.
    let agentID: String // Records the agent whose capability requirements drove selection.
    let agentName: String // Records the user-facing agent stage name.
    let preferredModelID: String? // Records the configured assignment preference.
    let selectedModelID: String // Records the actual physical model selected.
    let selectionReason: ModelSelectionReason // Records the deterministic preferred, fallback, legacy, or reuse path.
    let usedFallback: Bool // Records whether actual selection differed from the assignment preference.
    let switchedModel: Bool // Records whether the resource manager changed active physical model identity.
    let modelLoadingMilliseconds: Int // Records stop plus model readiness time.
    let inferenceMilliseconds: Int // Records only the model completion request time.
    let totalStageMilliseconds: Int // Records routing, loading, and inference time for the attempt.
    let status: WorkflowStepStatus // Records whether this model attempt succeeded or failed.
    let detail: String // Stores bounded operational success or failure metadata.
    let launchReference: String? // Records the exact validated local path or repository reference used by the runtime.
    let stopMilliseconds: Int? // Records verified outgoing-process shutdown time when lifecycle metrics are available.
    let coldLoadMilliseconds: Int? // Records startup-to-readiness time independently from stop work.
    let reuseMilliseconds: Int? // Records warm-reuse decision time when no process restart occurred.
    let switchingOverheadMilliseconds: Int? // Records coordinator overhead outside stop and cold load.
    let forcedTermination: Bool? // Records whether the exact owned outgoing process required force after its grace period.
    let memoryBeforeStop: ModelMemorySnapshot? // Records the outgoing exact-PID memory sample when available.
    let memoryAfterStop: ModelMemorySnapshot? // Records the post-release host memory sample when available.
    let memoryAfterLoad: ModelMemorySnapshot? // Records the incoming exact-PID memory sample when available.

    init( // Provides a default identity while keeping every operational field explicit.
        id: UUID = UUID(), // Generates one trace-local attempt identity.
        agentID: String, // Accepts the executing agent registry key.
        agentName: String, // Accepts the executing agent display name.
        preferredModelID: String?, // Accepts the configured model preference.
        selectedModelID: String, // Accepts the actual selected model key.
        selectionReason: ModelSelectionReason, // Accepts the deterministic selection reason.
        usedFallback: Bool, // Accepts whether fallback behavior occurred.
        switchedModel: Bool, // Accepts whether physical model identity changed.
        modelLoadingMilliseconds: Int, // Accepts measured resource transition time.
        inferenceMilliseconds: Int, // Accepts measured completion time.
        totalStageMilliseconds: Int, // Accepts measured full attempt time.
        status: WorkflowStepStatus, // Accepts attempt success or failure.
        detail: String, // Accepts bounded trace-safe operational detail.
        launchReference: String? = nil, // Accepts the exact runtime launch path or repository reference.
        stopMilliseconds: Int? = nil, // Accepts verified shutdown duration when measured.
        coldLoadMilliseconds: Int? = nil, // Accepts startup-to-readiness duration when measured.
        reuseMilliseconds: Int? = nil, // Accepts warm-reuse decision duration when measured.
        switchingOverheadMilliseconds: Int? = nil, // Accepts coordinator overhead when measured.
        forcedTermination: Bool? = nil, // Accepts whether the prior exact owned process required force.
        memoryBeforeStop: ModelMemorySnapshot? = nil, // Accepts the outgoing exact-PID sample.
        memoryAfterStop: ModelMemorySnapshot? = nil, // Accepts the post-release host sample.
        memoryAfterLoad: ModelMemorySnapshot? = nil // Accepts the incoming exact-PID sample.
    ) { // Starts model-execution construction.
        self.id = id // Stores the stable attempt identity.
        self.agentID = agentID // Stores the requesting agent key.
        self.agentName = agentName // Stores the requesting agent name.
        self.preferredModelID = preferredModelID // Stores the assignment preference.
        self.selectedModelID = selectedModelID // Stores the actual model key.
        self.selectionReason = selectionReason // Stores why the model was selected.
        self.usedFallback = usedFallback // Stores fallback use.
        self.switchedModel = switchedModel // Stores whether switching occurred.
        self.modelLoadingMilliseconds = modelLoadingMilliseconds // Stores model transition duration.
        self.inferenceMilliseconds = inferenceMilliseconds // Stores inference-only duration.
        self.totalStageMilliseconds = totalStageMilliseconds // Stores complete stage-attempt duration.
        self.status = status // Stores attempt outcome.
        self.detail = detail // Stores trace-safe operational detail.
        self.launchReference = launchReference // Stores the runtime reference needed for hardware-validation evidence.
        self.stopMilliseconds = stopMilliseconds // Stores verified shutdown duration.
        self.coldLoadMilliseconds = coldLoadMilliseconds // Stores cold startup duration.
        self.reuseMilliseconds = reuseMilliseconds // Stores warm reuse duration.
        self.switchingOverheadMilliseconds = switchingOverheadMilliseconds // Stores coordinator overhead.
        self.forcedTermination = forcedTermination // Stores whether force was required.
        self.memoryBeforeStop = memoryBeforeStop // Stores outgoing process memory evidence.
        self.memoryAfterStop = memoryAfterStop // Stores post-release memory evidence.
        self.memoryAfterLoad = memoryAfterLoad // Stores incoming process memory evidence.
    } // Ends model-execution construction.
} // Ends V0.2 model-execution metadata.

enum WorkflowOutcomeStatus: String, Codable { // Summarizes the end-to-end outcome of a workflow.
    case succeeded // Indicates all required and executed stages succeeded.
    case degraded // Indicates a useful intermediate answer survived a later-stage failure.
    case failed // Indicates no specialist answer could be produced.
} // Ends the overall workflow outcome definition.

struct WorkflowRequestOptions: Equatable, Sendable { // Configures only the opt-in Project Chat workflow while leaving every legacy execute overload unchanged.
    let conversationID: UUID? // Links the execution to one durable visible conversation when the caller has selected one.
    let projectID: UUID? // Restricts every memory lookup to one exact project identity or disables project lookup when absent.
    let memoryPreference: Bool? // Stores explicit ON or OFF when the user chose it and nil when deterministic recommendation heuristics should decide.
    let quality: AgentExecutionQuality // Selects the explicit Fast, Balanced, or Thorough V0.5 execution policy.
    let retrievalOptions: ProjectRetrievalOptions // Bounds and configures project-isolated candidate ranking before prompt assembly.
    let contextLimits: ProjectContextLimits // Bounds selected chunks, total characters, and per-document contribution.
    let queryLimits: ProjectMemoryQueryLimits // Bounds the current-request-only query supplied to lexical or optional model retrieval.

    init( // Supplies conservative defaults so callers can opt into the integrated path one concern at a time.
        conversationID: UUID? = nil, // Leaves durable conversation linkage absent for ephemeral calls.
        projectID: UUID? = nil, // Leaves the request outside Project Memory unless a concrete project is supplied.
        memoryPreference: Bool? = nil, // Uses the transparent ProjectMemoryRouter recommendation when the user has not chosen ON or OFF.
        quality: AgentExecutionQuality = .balanced, // Uses the normal latency-versus-quality policy by default.
        retrievalOptions: ProjectRetrievalOptions = ProjectRetrievalOptions(), // Uses the retrieval service's bounded hybrid-capable defaults.
        contextLimits: ProjectContextLimits = .balanced, // Uses the balanced, injection-resistant context budget by default.
        queryLimits: ProjectMemoryQueryLimits = .standard // Uses a bounded query derived only from the current visible request.
    ) { // Starts integrated request-option construction.
        self.conversationID = conversationID // Stores the optional durable conversation identity.
        self.projectID = projectID // Stores the only project identity retrieval is permitted to access.
        self.memoryPreference = memoryPreference // Stores the user's tri-state memory preference without inferring a hidden setting.
        self.quality = quality // Stores the explicit execution-quality policy.
        self.retrievalOptions = retrievalOptions // Stores candidate search limits and hybrid preference.
        self.contextLimits = contextLimits // Stores the complete hard context-assembly limits.
        self.queryLimits = queryLimits // Stores current-request query limits.
    } // Ends integrated request-option construction.
} // Ends backward-compatible integrated workflow options.

struct WorkflowMemoryTrace: Codable, Equatable, Sendable { // Stores retrieval operations and exact selected identities without persisting document contents or prompts.
    let projectID: UUID? // Identifies the exact isolated project searched or records that memory evaluation found no selected project.
    let decision: String // Stores the deterministic visible decision label.
    let query: String? // Stores the bounded visible retrieval query when search executed.
    let strategy: MemoryRetrievalMode? // Stores the actual lexical, vector, hybrid, reranked, or fallback strategy.
    let candidateCount: Int // Stores ranked candidates considered before context limits.
    let selectedChunkIDs: [UUID] // Stores only exact chunk identities injected into agent context.
    let injectedCharacterCount: Int // Stores the actual bounded project-context character count.
    let durationMilliseconds: Int // Stores measured decision, retrieval, and assembly duration.
    let fallbackReason: String? // Stores a bounded optional-runtime or no-result explanation.
} // Ends Project Memory trace metadata.

struct WorkflowTrace: Identifiable, Codable, Equatable { // Captures actual operational execution for one chat request.
    let id: UUID // Links the trace to the corresponding assistant chat message.
    let createdAt: Date // Records when the workflow began.
    let intent: UserIntent // Records the selected structured intent.
    let specialistID: String // Records the specialist registry key selected by the director.
    let specialistName: String // Records the specialist name shown in Chat and Agents views.
    let modelIdentifier: String // Records the actual model used by the successful specialist for compact Chat metadata.
    let totalDurationMilliseconds: Int // Records elapsed time across the complete workflow.
    let status: WorkflowOutcomeStatus // Records success, degraded recovery, or failure.
    let steps: [WorkflowStep] // Records each executed, skipped, or failed workflow stage in order.
    let modelExecutions: [WorkflowModelExecution] // Records V0.2 per-agent selection, fallback, loading, and inference metadata.
    let attachmentMetadata: [AttachmentTraceMetadata]? // Records privacy-safe attachment facts without paths, names, or raw media contents.
    let conversationID: UUID? // Links operational metadata to an actual durable conversation when Project Chat invoked it.
    let projectID: UUID? // Identifies project association without embedding any project document contents.
    let quality: AgentExecutionQuality? // Records the actual Fast, Balanced, or Thorough request policy when supplied.
    let memory: WorkflowMemoryTrace? // Records retrieval strategy and exact injected chunk identities without source text.

    init(id: UUID, createdAt: Date, intent: UserIntent, specialistID: String, specialistName: String, modelIdentifier: String, totalDurationMilliseconds: Int, status: WorkflowOutcomeStatus, steps: [WorkflowStep], modelExecutions: [WorkflowModelExecution], attachmentMetadata: [AttachmentTraceMetadata] = [], conversationID: UUID? = nil, projectID: UUID? = nil, quality: AgentExecutionQuality? = nil, memory: WorkflowMemoryTrace? = nil) { // Creates a trace while keeping prior call sites source-compatible.
        self.id = id // Stores workflow identity.
        self.createdAt = createdAt // Stores workflow creation time.
        self.intent = intent // Stores deterministic routing intent.
        self.specialistID = specialistID // Stores selected specialist identity.
        self.specialistName = specialistName // Stores selected specialist display name.
        self.modelIdentifier = modelIdentifier // Stores actual specialist model identity.
        self.totalDurationMilliseconds = totalDurationMilliseconds // Stores end-to-end measured duration.
        self.status = status // Stores overall workflow outcome.
        self.steps = steps // Stores ordered agent and service operations.
        self.modelExecutions = modelExecutions // Stores physical model attempts and timing.
        self.attachmentMetadata = attachmentMetadata.isEmpty ? nil : attachmentMetadata // Omits the field for text-only traces and preserves privacy-safe facts for multimodal requests.
        self.conversationID = conversationID // Stores durable conversation linkage only when known.
        self.projectID = projectID // Stores project association only when known.
        self.quality = quality // Stores the actual execution-quality policy only for integrated requests.
        self.memory = memory // Stores retrieval operational metadata only when Project Memory was evaluated.
    } // Ends workflow trace construction.
} // Ends the structured workflow trace.

struct WorkflowResult { // Returns both the user-facing answer and its real operational trace.
    let answer: String // Contains the best valid answer available after recovery rules run.
    let trace: WorkflowTrace // Contains the trace used by Chat and Agents views.
    let activeModelID: String? // Reports the physical model left active after the workflow.
    let activeServerPort: Int? // Reports the actual ready port after automatic selection and switching.
    let citations: [LocalMemoryCitation] // Returns only sources corresponding to chunks actually injected into agent context.
    let generationStatus: ChatGenerationStatus // Reports whether the visible answer completed, degraded, failed, or was cancelled.

    init(answer: String, trace: WorkflowTrace, activeModelID: String?, activeServerPort: Int?, citations: [LocalMemoryCitation] = [], generationStatus: ChatGenerationStatus = .complete) { // Preserves every existing engine call while adding Project Chat output metadata.
        self.answer = answer // Stores the best valid visible answer.
        self.trace = trace // Stores complete operational metadata.
        self.activeModelID = activeModelID // Stores the actual final resident model identity.
        self.activeServerPort = activeServerPort // Stores the actual ready endpoint when one remains.
        self.citations = citations // Stores only exact assembled Project Memory sources.
        self.generationStatus = generationStatus // Stores visible delivery state without private runtime objects.
    } // Ends workflow-result construction.
} // Ends the workflow result type.
