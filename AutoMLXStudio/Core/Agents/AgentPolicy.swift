import Foundation // Supplies durable, typed agent-policy values without importing host execution APIs.

enum AgentToolPermission: String, Codable, CaseIterable, Hashable { // Names capabilities granted by application code rather than by model prose.
    case imageAnalysis // Permits only the dedicated attached-image analysis service.
    case speechRecognition // Permits only the configured microphone/ASR service.
    case speechSynthesis // Permits only the configured local TTS service.
    case projectRetrieval // Permits only project-isolated bounded memory retrieval.
    case workspaceRead // Permits bounded Engineering workspace inspection.
    case workspaceWrite // Permits approved and hash-checked Engineering mutations.
    case commandExecution // Permits approved commands under the V0.6.1.1 process sandbox.
    case gitInspection // Permits read-only contained Git inspection.
    case buildAndTest // Permits approved contained build and test commands.

    var displayName: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized } // Provides compact readable native UI labels.
} // Ends the code-enforced tool-capability vocabulary.

enum AgentContextScope: String, Codable { // Limits which application-owned context a logical role may receive.
    case requestOnly // Supplies only the current visible task.
    case recentConversation // Supplies a bounded suffix of visible prior turns.
    case projectEvidence // Supplies only selected, injection-labelled project chunks.
    case workspaceEvidence // Supplies only explicitly authorized bounded Engineering tool results.
    case candidateOnly // Supplies the request and prior agent candidate for review or composition.
    case attachedImage // Supplies only explicitly attached image evidence.
    case audioInput // Supplies only microphone audio selected for transcription.
    case outputText // Supplies only the final text selected for synthesis.
} // Ends typed per-agent context selection.

enum EngineeringPermissionProfile: String, Codable, CaseIterable, Identifiable { // Makes current and future Engineering authority profiles explicit.
    case safe // Runs only in the selected workspace and private runtime with mandatory process containment.
    case advanced // Reserves explicit additional-resource grants; not executable until scoped-resource enforcement exists.
    case fullAccessFuture // Reserves host-level Computer access; never executable in this milestone.
    var id: String { rawValue } // Supplies a stable persisted profile identifier.
    var isExecutable: Bool { self == .safe } // Fails closed for profiles without a concrete enforcement backend.
    var displayName: String { self == .fullAccessFuture ? "Full Access (future)" : rawValue.capitalized } // Distinguishes future authority from today's Safe mode.
} // Ends explicit permission-profile architecture.

struct AgentOperatingPolicy: Equatable { // Describes one logical role's real tool, context, and execution ceiling.
    let agentID: String // Binds policy to a stable registered role instead of a prompt name.
    let allowedTools: Set<AgentToolPermission> // Records host capabilities granted independently from model output.
    let contextScope: AgentContextScope // Selects the only context category the role should receive.
    let maximumContextCharacters: Int // Bounds injected context even if source material is larger.
    let maximumModelTurns: Int // Bounds the role's model activity independently from model suggestions.
} // Ends inspectable per-agent policy.

enum AgentPolicyRegistry { // Centralizes hard permissions shared by orchestration, Engineering, UI, and tests.
    static func policy(for agentID: String) -> AgentOperatingPolicy { // Resolves one stable role without granting tools to unknown identifiers.
        switch agentID { // Assigns the smallest relevant application capability to each role.
        case AgentID.vision: return AgentOperatingPolicy(agentID: agentID, allowedTools: [.imageAnalysis], contextScope: .attachedImage, maximumContextCharacters: 12_000, maximumModelTurns: 1) // Keeps image understanding separate from host tools.
        case AgentID.asr: return AgentOperatingPolicy(agentID: agentID, allowedTools: [.speechRecognition], contextScope: .audioInput, maximumContextCharacters: 0, maximumModelTurns: 1) // Restricts ASR to selected audio.
        case AgentID.tts: return AgentOperatingPolicy(agentID: agentID, allowedTools: [.speechSynthesis], contextScope: .outputText, maximumContextCharacters: 8_000, maximumModelTurns: 1) // Restricts TTS to the response text.
        case AgentID.retrieval: return AgentOperatingPolicy(agentID: agentID, allowedTools: [.projectRetrieval], contextScope: .projectEvidence, maximumContextCharacters: 16_000, maximumModelTurns: 0) // Represents the current deterministic retrieval service truthfully.
        case AgentID.engineering: return AgentOperatingPolicy(agentID: agentID, allowedTools: [.projectRetrieval, .workspaceRead, .workspaceWrite, .commandExecution, .gitInspection, .buildAndTest], contextScope: .workspaceEvidence, maximumContextCharacters: EngineeringAgentLimits.historyCharacterBudget, maximumModelTurns: AgentExecutionQuality.thorough.engineeringIterationLimit) // Grants Engineering only its already centralized bounded runtime surface.
        case AgentID.reviewer, AgentID.finalComposer: return AgentOperatingPolicy(agentID: agentID, allowedTools: [], contextScope: .candidateOnly, maximumContextCharacters: 24_000, maximumModelTurns: 1) // Gives quality stages no Engineering authority.
        case AgentID.planner: return AgentOperatingPolicy(agentID: agentID, allowedTools: [], contextScope: .requestOnly, maximumContextCharacters: 8_000, maximumModelTurns: 1) // Keeps planning advisory and bounded.
        case AgentID.research, AgentID.document: return AgentOperatingPolicy(agentID: agentID, allowedTools: [], contextScope: .projectEvidence, maximumContextCharacters: 16_000, maximumModelTurns: 1) // Gives text specialists only application-selected evidence.
        case AgentID.debugger, AgentID.coding, AgentID.swift, AgentID.python, AgentID.cAndCpp, AgentID.cSharp, AgentID.web, AgentID.database: return AgentOperatingPolicy(agentID: agentID, allowedTools: [], contextScope: .recentConversation, maximumContextCharacters: 16_000, maximumModelTurns: 1) // Keeps coding advice separate from executable host tools.
        default: return AgentOperatingPolicy(agentID: agentID, allowedTools: [], contextScope: .recentConversation, maximumContextCharacters: 12_000, maximumModelTurns: 1) // Fails closed for unknown and ordinary text roles.
        } // Ends role policy selection.
    } // Ends policy lookup.

    static func engineeringToolNames(for agentID: String, profile: EngineeringPermissionProfile) -> Set<String> { // Converts semantic policy into the concrete existing typed-tool boundary.
        guard agentID == AgentID.engineering, profile.isExecutable else { return [] } // Refuses host tools for any other role or unimplemented authority profile.
        let granted = policy(for: agentID).allowedTools // Freezes the code-owned semantic permission set.
        return Set(EngineeringToolRuntime.definitions.compactMap { definition in // Visits only tools actually implemented by the Mac runtime.
            let required: AgentToolPermission // Declares the one semantic authority needed by the typed tool.
            switch definition.name { // Maps every concrete Engineering function without a wildcard default.
            case .listDirectory, .readFile, .searchFiles, .searchText, .fileInfo, .unifiedDiff: required = .workspaceRead // Restricts inspection tools to authorized workspace readers.
            case .writeFile, .replaceInFile, .createFile, .rollbackChange: required = .workspaceWrite // Restricts direct mutations to authorized Engineering.
            case .runCommand: required = .commandExecution // Requires the OS-contained command capability.
            case .gitStatus, .gitDiff, .gitLog: required = .gitInspection // Restricts read-only Git commands.
            case .buildProject, .runTests: required = .buildAndTest // Restricts build/test subprocesses.
            } // Ends exhaustive concrete-tool classification.
            return granted.contains(required) ? definition.name.rawValue : nil // Exposes only registered tools whose semantic permission was granted.
        }) // Ends concrete tool intersection.
    } // Ends fail-closed Engineering tool policy.
} // Ends central agent policy registry.
