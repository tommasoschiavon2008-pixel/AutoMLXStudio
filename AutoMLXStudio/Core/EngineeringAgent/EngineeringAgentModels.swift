import Foundation // Supplies UUID, Date, Error, and Sendable-friendly value types for engineering sessions.

extension AgentExecutionQuality { // Maps the existing visible quality choice to a hard autonomous-loop ceiling.
    var engineeringIterationLimit: Int { // Returns the non-configurable safety ceiling associated with the selected quality.
        switch self { // Selects the bounded iteration count without consulting model output.
        case .fast: return 8 // Limits Fast engineering sessions to eight primary or repair model turns.
        case .balanced: return 16 // Limits Balanced engineering sessions to sixteen primary or repair model turns.
        case .thorough: return 30 // Limits Thorough engineering sessions to thirty primary or repair model turns.
        } // Ends quality-to-limit selection.
    } // Ends the engineering iteration-limit accessor.
} // Ends the existing quality-policy extension.

enum EngineeringAgentLimits { // Centralizes inspectable bounds enforced independently from model behavior.
    static let maximumNativeToolCallsPerTurn = 4 // Limits one provider-native response to four sequential Mac tool proposals.
    static let historyCharacterBudget = 196_608 // Caps cumulative live model-message history at 192 Ki characters before every generation.
} // Ends bounded Engineering Agent limits.

enum EngineeringAgentSessionStatus: String, Equatable, Sendable { // Defines every terminal outcome exposed by the bounded engineering engine.
    case completed // Indicates that the model declared completion and the engine recorded verification truthfully.
    case failed // Indicates that an unrecoverable orchestration or model error stopped the session.
    case cancelled // Indicates that the user or owning task cancelled the exact active session.
    case permissionDenied // Indicates that the plan or concrete Mac runtime denied a proposed tool operation.
    case iterationLimit // Indicates that the selected quality ceiling was reached without completion.
    case loopDetected // Indicates that the same tool request and result repeated beyond the safety threshold.
    case busy // Indicates that another session already owns the single active engine slot.
} // Ends terminal engineering outcomes.

enum EngineeringAgentVerificationState: String, Equatable, Sendable { // Distinguishes evidence-backed completion from an unverified model claim.
    case verified // Indicates that at least one successful verification tool supplied concrete evidence.
    case unverified // Indicates that no successful build, test, syntax, or equivalent evidence was observed.
} // Ends verification-state choices.

struct EngineeringAgentVerificationEvidence: Equatable, Sendable { // Carries bounded runtime-produced evidence rather than a model assertion.
    enum Kind: String, Equatable, Sendable { // Identifies the concrete verification category performed by the Mac runtime.
        case build // Represents a compiler or project build result.
        case tests // Represents a test-suite or targeted-test result.
        case syntax // Represents a parser, linter, or syntax-check result.
        case command // Represents another explicit verification command.
    } // Ends verification evidence categories.

    let kind: Kind // Records which verification category ran.
    let succeeded: Bool // Records the concrete runtime outcome without inferring success from prose.
    let summary: String // Stores a bounded operational summary suitable for the final report.
} // Ends one verification-evidence record.

struct EngineeringAgentVerificationSummary: Equatable, Sendable { // Summarizes all real verification evidence retained by a session.
    let state: EngineeringAgentVerificationState // Records whether successful evidence exists.
    let evidence: [EngineeringAgentVerificationEvidence] // Preserves each bounded build, test, syntax, or command result.
    let detail: String // Explains the verified or unverified state without overstating model confidence.
} // Ends the verification summary.

enum EngineeringAgentDataKind: String, Equatable, Sendable { // Labels external content that must never become tool-policy authority.
    case workspaceIdentity // Identifies the user-visible workspace name as data rather than a system-prompt interpolation.
    case workspaceOverview // Identifies a user-selected workspace map or file excerpt.
    case projectMemory // Identifies retrieval output supplied by Project Memory.
    case toolResult // Identifies output returned by the local Mac tool runtime.
    case modelOutput // Identifies an intermediate model candidate retained only as non-authoritative data.
    case reviewerOutput // Identifies optional model-produced review text used only as composition data.
} // Ends untrusted-data source categories.

enum EngineeringAgentMessageTrust: Equatable, Sendable { // Makes the trust boundary explicit on every model conversation item.
    case systemInstruction // Marks application-owned policy instructions.
    case userRequest // Marks the user objective, which cannot override runtime permission enforcement.
    case untrustedData(EngineeringAgentDataKind) // Marks workspace, memory, tool, or reviewer content as non-authoritative data.
} // Ends model-message trust labels.

enum EngineeringAgentMessageRole: String, Equatable, Sendable { // Defines the provider-neutral roles used by the narrow model adapter.
    case user // Represents the visible engineering objective or application correction.
    case assistant // Represents a provider-normalized assistant response retained only inside the live loop.
    case tool // Represents a local runtime result returned to the model as untrusted data.
} // Ends provider-neutral engineering roles.

struct EngineeringAgentModelMessage: Equatable, Sendable { // Carries one bounded live-loop message with an explicit trust label.
    let role: EngineeringAgentMessageRole // Records the transport-independent message role.
    let content: String // Stores bounded content for the current session only.
    let trust: EngineeringAgentMessageTrust // Prevents workspace or tool text from being mistaken for application policy.
    let toolCalls: [EngineeringAgentToolCall] // Preserves provider-neutral assistant tool-call structure for native follow-up turns.
    let toolCallID: String? // Correlates one tool-role message with the originating native or fallback call.

    init(role: EngineeringAgentMessageRole, content: String, trust: EngineeringAgentMessageTrust, toolCalls: [EngineeringAgentToolCall] = [], toolCallID: String? = nil) { // Constructs one live-loop message without provider-specific dictionaries.
        self.role = role // Stores the normalized role.
        self.content = content // Stores bounded current-session content.
        self.trust = trust // Stores the explicit authority boundary.
        self.toolCalls = toolCalls // Stores any normalized assistant tool calls.
        self.toolCallID = toolCallID // Stores optional tool-result correlation.
    } // Ends model-message construction.
} // Ends one engineering model message.

struct EngineeringExecutionPlan: Equatable, Sendable { // Declares the complete inspectable policy for one bounded engineering session.
    let workspaceID: UUID // Identifies the separately authorized engineering workspace.
    let workspaceName: String // Supplies the non-secret user-facing workspace label.
    let quality: AgentExecutionQuality // Selects the fixed Fast, Balanced, or Thorough iteration ceiling.
    let allowedToolNames: Set<String> // Restricts proposals before the concrete runtime performs its own permission checks.
    let reviewerEnabled: Bool // Enables at most one optional post-loop reviewer inference.
    let composerEnabled: Bool // Enables at most one optional post-loop final-composer inference.
    let verificationExpected: Bool // Records whether the caller expects practical verification for this task.

    var maximumIterations: Int { quality.engineeringIterationLimit } // Exposes the fixed loop ceiling for UI and trace inspection.

    init( // Constructs an explicit plan without hidden recursive or swarm behavior.
        workspaceID: UUID, // Accepts the exact authorized workspace identity.
        workspaceName: String, // Accepts the display-only workspace name.
        quality: AgentExecutionQuality = .balanced, // Defaults to the sixteen-turn Balanced policy.
        allowedToolNames: Set<String>, // Accepts only tools the surrounding application authorizes for consideration.
        reviewerEnabled: Bool = true, // Enables one reviewer stage unless the caller chooses the faster path.
        composerEnabled: Bool = true, // Enables one composer stage unless the caller chooses direct output.
        verificationExpected: Bool = true // Expects evidence for normal implementation tasks by default.
    ) { // Starts plan construction.
        self.workspaceID = workspaceID // Stores the exact workspace identity.
        self.workspaceName = workspaceName // Stores the visible workspace label.
        self.quality = quality // Stores the fixed quality policy.
        self.allowedToolNames = allowedToolNames // Stores the application-approved tool-name boundary.
        self.reviewerEnabled = reviewerEnabled // Stores the bounded reviewer choice.
        self.composerEnabled = composerEnabled // Stores the bounded composer choice.
        self.verificationExpected = verificationExpected // Stores the caller's practical verification expectation.
    } // Ends plan construction.
} // Ends the inspectable engineering plan.

struct EngineeringAgentInput: Equatable, Sendable { // Supplies only the user objective and explicitly labelled optional data contexts.
    let task: String // Stores the visible engineering objective.
    let workspaceOverview: String? // Stores an optional bounded workspace map treated strictly as untrusted data.
    let projectMemoryContext: String? // Stores optional retrieval context treated strictly as untrusted data.

    init(task: String, workspaceOverview: String? = nil, projectMemoryContext: String? = nil) { // Constructs one engine input without embedding application objects.
        self.task = task // Stores the user objective.
        self.workspaceOverview = workspaceOverview // Stores optional workspace data for orientation.
        self.projectMemoryContext = projectMemoryContext // Stores optional project-memory data for relevance only.
    } // Ends engine-input construction.
} // Ends the transport-independent engine input.

struct EngineeringAgentToolDefinition: Equatable, Sendable { // Describes one local Mac tool to a provider-neutral model adapter.
    let name: String // Stores the stable function name.
    let summary: String // Stores a concise capability description.
    let inputSchemaJSON: String // Stores the bounded JSON Schema supplied by the concrete runtime.
} // Ends one tool definition.

enum EngineeringAgentToolCallOrigin: String, Equatable, Sendable { // Records which bounded protocol produced a tool proposal.
    case native // Identifies a provider-normalized native function call.
    case strictJSONFallback // Identifies an exact JSON envelope parsed only after native support was unavailable.
} // Ends tool-call protocol origins.

struct EngineeringAgentToolCall: Equatable, Sendable { // Carries one typed tool proposal while leaving argument validation outside the model.
    let id: String // Preserves the provider or fallback-envelope call identity.
    let name: String // Stores the exact registered tool name.
    let argumentsJSON: String // Stores the raw bounded JSON object for deterministic validation and dispatch.
    let origin: EngineeringAgentToolCallOrigin // Records native or strict fallback provenance.

    init(id: String, name: String, argumentsJSON: String, origin: EngineeringAgentToolCallOrigin = .native) { // Creates one provider-normalized tool proposal.
        self.id = id // Stores the call identity.
        self.name = name // Stores the requested tool name.
        self.argumentsJSON = argumentsJSON // Stores arguments for engine and runtime validation.
        self.origin = origin // Stores the protocol provenance.
    } // Ends tool-call construction.
} // Ends a typed engineering tool call.

enum EngineeringAgentToolStatus: String, Equatable, Sendable { // Normalizes every concrete runtime outcome used by the loop.
    case succeeded // Indicates that the exact tool operation completed successfully.
    case failed // Indicates a bounded operational failure that the model may try to repair.
    case denied // Indicates that external application or runtime policy denied the proposal.
    case cancelled // Indicates that cancellation stopped the exact owned operation.
} // Ends normalized tool outcomes.

struct EngineeringAgentToolResult: Equatable, Sendable { // Returns bounded tool data plus operational metadata to the engine.
    let callID: String // Correlates the result with the exact proposed call.
    let status: EngineeringAgentToolStatus // Records success, failure, denial, or cancellation.
    let output: String // Supplies bounded result data to the model without making it policy authority.
    let operationalSummary: String // Supplies a short secret-safe description for public trace events.
    let durationMilliseconds: Int // Records measured local runtime duration.
    let exitCode: Int? // Records a process exit code only when a command actually ran.
    let changedPaths: [String] // Records root-relative files changed by the concrete runtime.
    let verification: EngineeringAgentVerificationEvidence? // Records real verification evidence when the operation performed such a check.

    init( // Constructs one complete normalized runtime result.
        callID: String, // Accepts the correlated tool-call identity.
        status: EngineeringAgentToolStatus, // Accepts the concrete runtime outcome.
        output: String, // Accepts bounded untrusted result data.
        operationalSummary: String, // Accepts bounded public operational metadata.
        durationMilliseconds: Int, // Accepts measured runtime duration.
        exitCode: Int? = nil, // Accepts an optional real process exit code.
        changedPaths: [String] = [], // Accepts any root-relative file mutations.
        verification: EngineeringAgentVerificationEvidence? = nil // Accepts optional runtime-produced verification evidence.
    ) { // Starts normalized result construction.
        self.callID = callID // Stores the correlated call identity.
        self.status = status // Stores the runtime outcome.
        self.output = output // Stores bounded data for the live loop.
        self.operationalSummary = operationalSummary // Stores public trace-safe metadata.
        self.durationMilliseconds = durationMilliseconds // Stores elapsed runtime duration.
        self.exitCode = exitCode // Stores the optional real exit code.
        self.changedPaths = changedPaths // Stores root-relative mutation evidence.
        self.verification = verification // Stores optional verification evidence.
    } // Ends normalized result construction.
} // Ends one tool result.

protocol EngineeringAgentToolExecuting: Sendable { // Defines the narrow bridge root can adapt to the centralized EngineeringToolRuntime.
    func toolDefinitions() async -> [EngineeringAgentToolDefinition] // Returns currently registered tools without granting model authority.
    func execute(_ call: EngineeringAgentToolCall, sessionID: UUID) async -> EngineeringAgentToolResult // Validates permissions and executes one proposal on the Mac.
} // Ends the concrete-tool-runtime adapter contract.

enum EngineeringAgentModelPhase: String, Equatable, Sendable { // Identifies each strictly bounded model stage.
    case primary // Represents a normal inspect, edit, verify, or completion turn.
    case argumentRepair // Represents the single permitted malformed-call repair turn.
    case reviewer // Represents the optional one-shot post-loop review.
    case composer // Represents the optional one-shot user-facing composition.
} // Ends bounded model stages.

enum EngineeringAgentToolProtocol: String, Equatable, Sendable { // Declares how one model request may express tool calls.
    case nativePreferred // Requests provider-native tools while retaining a strict fallback only if unavailable.
    case strictJSONFallback // Requests the exact bounded JSON envelope after native support is explicitly unavailable.
    case noTools // Forbids tools during Reviewer and Composer stages.
} // Ends tool-call protocol choices.

struct EngineeringAgentModelRequest: Equatable, Sendable { // Isolates the engine from local or remote provider-specific request dictionaries.
    let sessionID: UUID // Correlates model work with the exact active engineering session.
    let iteration: Int // Records the bounded primary-loop iteration or zero for post-loop stages.
    let phase: EngineeringAgentModelPhase // Identifies primary, repair, reviewer, or composer behavior.
    let systemInstructions: String // Supplies application-owned operational and security instructions.
    let messages: [EngineeringAgentModelMessage] // Supplies bounded live-loop context with explicit trust labels.
    let tools: [EngineeringAgentToolDefinition] // Supplies only plan-allowed tool schemas.
    let toolProtocol: EngineeringAgentToolProtocol // Requests native, strict fallback, or no-tool behavior.
    let maximumResponseCharacters: Int // Gives adapters a transport-independent output bound.
} // Ends the provider-neutral model request.

enum EngineeringAgentModelFinishReason: String, Equatable, Sendable { // Normalizes only finish metadata needed by the engine.
    case complete // Indicates an explicit user-facing completion response.
    case toolCalls // Indicates that the response intentionally proposed tools.
    case length // Indicates that the provider output bound interrupted the response.
    case stopped // Indicates that a provider or user stop interrupted the response.
    case unknown // Indicates that the backend could not classify its finish condition.
} // Ends normalized model finish reasons.

struct EngineeringAgentModelAttempt: Equatable, Sendable { // Makes preferred and fallback model/backend attempts transparent in the public trace.
    let modelID: String // Records the logical or provider model identity actually attempted.
    let backendID: String // Records the local or remote backend identity.
    let location: String // Records a non-secret user-facing execution location.
    let succeeded: Bool // Records whether this exact attempt produced the normalized response.
    let failureSummary: String? // Stores a bounded operational failure description when unsuccessful.

    init(modelID: String, backendID: String, location: String, succeeded: Bool, failureSummary: String? = nil) { // Constructs one transparent routing attempt.
        self.modelID = modelID // Stores the model identity.
        self.backendID = backendID // Stores the backend identity.
        self.location = location // Stores the visible execution location.
        self.succeeded = succeeded // Stores the attempt outcome.
        self.failureSummary = failureSummary // Stores optional bounded failure metadata.
    } // Ends model-attempt construction.
} // Ends one model/backend attempt.

struct EngineeringAgentModelResponse: Equatable, Sendable { // Normalizes native tools, fallback content, and routing evidence from any backend.
    let text: String? // Stores final text or the exact strict JSON fallback envelope.
    let nativeToolCalls: [EngineeringAgentToolCall] // Stores provider-normalized native function calls.
    let nativeToolCallingAvailable: Bool? // Distinguishes physically known native support from known unavailability or uncertainty.
    let finishReason: EngineeringAgentModelFinishReason // Records why the selected backend ended generation.
    let attempts: [EngineeringAgentModelAttempt] // Records preferred and compatible fallback attempts in order.

    init( // Constructs one normalized generation response.
        text: String? = nil, // Accepts optional response text or strict fallback JSON.
        nativeToolCalls: [EngineeringAgentToolCall] = [], // Accepts zero or more provider-native calls.
        nativeToolCallingAvailable: Bool? = nil, // Preserves unknown capability instead of inventing precision.
        finishReason: EngineeringAgentModelFinishReason, // Accepts the normalized finish reason.
        attempts: [EngineeringAgentModelAttempt] // Accepts transparent routing-attempt metadata.
    ) { // Starts response construction.
        self.text = text // Stores optional model text.
        self.nativeToolCalls = nativeToolCalls // Stores normalized native tool calls.
        self.nativeToolCallingAvailable = nativeToolCallingAvailable // Stores known, unavailable, or unknown native capability.
        self.finishReason = finishReason // Stores normalized finish metadata.
        self.attempts = attempts // Stores ordered model/backend attempts.
    } // Ends response construction.
} // Ends the normalized generation response.

struct EngineeringAgentModelFailure: LocalizedError, Equatable, Sendable { // Preserves model fallback evidence when all compatible attempts fail.
    let summary: String // Stores the bounded terminal generation failure.
    let attempts: [EngineeringAgentModelAttempt] // Stores every preferred and fallback attempt made before failure.

    var errorDescription: String? { summary } // Exposes only the bounded operational summary to standard error handling.
} // Ends typed model-generation failure.

protocol EngineeringAgentModelGenerating: Sendable { // Defines the narrow bridge root can adapt to ModelRouter plus local or remote inference.
    func generate(_ request: EngineeringAgentModelRequest) async throws -> EngineeringAgentModelResponse // Produces one provider-normalized bounded turn.
} // Ends the transport-independent model adapter contract.

enum EngineeringAgentEventKind: String, Equatable, Sendable { // Defines operational trace events without retaining prompts or chain-of-thought.
    case sessionStarted // Records ownership of the single active session slot.
    case modelAttempt // Records one local or remote model/backend attempt.
    case modelFallback // Records that routing moved from an unsuccessful attempt to a compatible successor.
    case toolRequested // Records one validated tool proposal before concrete runtime execution.
    case toolSucceeded // Records one successful local Mac tool operation.
    case toolFailed // Records one recoverable local Mac tool failure.
    case toolDenied // Records a plan or runtime permission denial.
    case toolCancelled // Records cancellation of the exact owned tool operation.
    case argumentRepair // Records use of the single malformed-call repair allowance.
    case loopWarning // Records that a repeated action must change strategy.
    case loopDetected // Records terminal repeated-call detection.
    case reviewerStarted // Records the optional one-shot Reviewer stage.
    case reviewerSucceeded // Records a successful Reviewer response.
    case reviewerFailed // Records progressive recovery from Reviewer failure.
    case composerStarted // Records the optional one-shot FinalComposer stage.
    case composerSucceeded // Records a successful user-facing composition.
    case composerFailed // Records progressive recovery to the best prior candidate.
    case sessionCompleted // Records explicit terminal completion.
    case sessionFailed // Records an unrecoverable terminal failure.
    case sessionCancelled // Records user cancellation.
    case iterationLimit // Records exhaustion of the selected quality ceiling.
    case sessionBusy // Records rejection because another session owns the engine.
} // Ends operational event categories.

struct EngineeringAgentEvent: Identifiable, Equatable, Sendable { // Stores bounded operational metadata safe for UI and persistence.
    let id: UUID // Gives the event stable list identity.
    let occurredAt: Date // Records wall-clock ordering for the visible activity feed.
    let kind: EngineeringAgentEventKind // Identifies the operational event category.
    let iteration: Int? // Associates primary-loop work with its bounded iteration when applicable.
    let modelID: String? // Records a model identity only for model-stage events.
    let backendID: String? // Records a backend identity only for model-stage events.
    let toolName: String? // Records a tool name without persisting arguments or output.
    let durationMilliseconds: Int? // Records measured tool duration when available.
    let exitCode: Int? // Records a real command exit code when available.
    let succeeded: Bool? // Records an operational outcome when binary success is meaningful.
    let summary: String // Stores a bounded secret-safe description without full file or command output.

    init( // Constructs one trace-safe operational event.
        id: UUID = UUID(), // Generates a stable event identity by default.
        occurredAt: Date = Date(), // Records current wall-clock time by default.
        kind: EngineeringAgentEventKind, // Accepts the event category.
        iteration: Int? = nil, // Accepts an optional loop iteration.
        modelID: String? = nil, // Accepts an optional model identity.
        backendID: String? = nil, // Accepts an optional backend identity.
        toolName: String? = nil, // Accepts an optional tool name.
        durationMilliseconds: Int? = nil, // Accepts optional measured duration.
        exitCode: Int? = nil, // Accepts an optional real exit code.
        succeeded: Bool? = nil, // Accepts an optional success flag.
        summary: String // Accepts the bounded public summary.
    ) { // Starts event construction.
        self.id = id // Stores the stable event identity.
        self.occurredAt = occurredAt // Stores the event timestamp.
        self.kind = kind // Stores the event category.
        self.iteration = iteration // Stores the optional iteration.
        self.modelID = modelID // Stores the optional model identity.
        self.backendID = backendID // Stores the optional backend identity.
        self.toolName = toolName // Stores the optional tool name.
        self.durationMilliseconds = durationMilliseconds // Stores optional elapsed duration.
        self.exitCode = exitCode // Stores the optional process exit code.
        self.succeeded = succeeded // Stores the optional success flag.
        self.summary = summary // Stores bounded trace-safe metadata.
    } // Ends event construction.
} // Ends one operational engineering event.

struct EngineeringAgentSessionResult: Equatable, Sendable { // Returns a terminal status, best useful summary, and evidence without hidden reasoning.
    let sessionID: UUID // Identifies the exact session that owned or attempted to own the engine.
    let status: EngineeringAgentSessionStatus // Records the precise completion, failure, cancellation, denial, limit, loop, or busy outcome.
    let finalSummary: String // Preserves the best useful candidate even when a later stage fails.
    let iterationsUsed: Int // Records primary and repair model turns consumed against the plan ceiling.
    let maximumIterations: Int // Records the fixed quality ceiling used by this session.
    let changedPaths: [String] // Records unique root-relative paths reported by the concrete runtime.
    let verification: EngineeringAgentVerificationSummary // Reports only concrete runtime verification evidence.
    let events: [EngineeringAgentEvent] // Preserves bounded operational activity without prompts, arguments, outputs, or reasoning.
    let isPartial: Bool // Identifies a useful result returned before normal verified completion.
    let qualityStagesDegraded: Bool // Identifies Reviewer or Composer failure without discarding the primary result.
    let failureSummary: String? // Stores a bounded terminal diagnostic when the session did not complete normally.
} // Ends the engineering session result.
