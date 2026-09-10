import Foundation // Supplies Codable and Hashable support for persisted assignments.

struct ModelAssignment: Codable, Hashable, Identifiable { // Stores an agent-to-model preference independently from both definitions.
    var id: String { agentID } // Uses the stable agent identifier for list and persistence identity.
    let agentID: String // Identifies the agent whose runtime model is being selected.
    var preferredModelID: String? // Stores the first model considered when available and compatible.
    var preferredCapability: ModelCapability // Stores the primary capability used for registry preference fallback.
    var fallbackModelIDs: [String] // Stores explicit deterministic fallback order.
    var fallbackCapabilities: [ModelCapability] // Stores ordered capability fallback categories.
    var allowsRuntimeReuse: Bool // Allows explicit switching policy to reuse a compatible active model.
} // Ends the model-assignment value type.

struct ModelCapabilityPreference: Codable, Hashable, Identifiable { // Persists one user-selected preferred model for a capability.
    var id: String { capability.rawValue } // Uses the capability value as stable preference identity.
    let capability: ModelCapability // Identifies the capability whose default is being configured.
    var modelID: String // Identifies the preferred registered model.
} // Ends the capability-preference value type.

enum ModelSwitchPolicy: String, Codable, CaseIterable, Identifiable { // Defines deterministic quality-versus-switching behavior.
    case qualityPreferred // Always tries the assignment's preferred model before runtime reuse.
    case balanced // Reuses only an explicitly allowed preferred or declared-fallback active model.
    case minimizeSwitches // Reuses any compatible active text model before considering a switch.

    var id: String { rawValue } // Makes policies directly selectable in a SwiftUI Picker.

    var displayName: String { // Produces concise Settings labels.
        switch self { // Selects a user-facing policy name.
        case .qualityPreferred: return "Prefer quality" // Labels strict preference behavior.
        case .balanced: return "Balanced" // Labels the default explicit reuse behavior.
        case .minimizeSwitches: return "Minimize switches" // Labels latency-first active-model reuse.
        } // Ends policy-label selection.
    } // Ends policy display-name access.

    var detail: String { // Explains the deterministic tradeoff shown in Settings.
        switch self { // Selects an explanation for the current policy.
        case .qualityPreferred: return "Use each agent’s preferred model whenever it is usable." // Explains strict preferred-model selection.
        case .balanced: return "Reuse the active model only when the assignment explicitly allows it as a preferred or fallback choice." // Explains bounded active-model reuse.
        case .minimizeSwitches: return "Reuse any active compatible text model before loading another model." // Explains latency-first compatible reuse.
        } // Ends policy-detail selection.
    } // Ends policy detail access.
} // Ends switching-policy definitions.

enum ModelSelectionReason: String, Codable, Hashable { // Records why deterministic routing selected a physical model.
    case preferredModel // Indicates the assignment's preferred model was selected.
    case capabilityPreference // Indicates a user capability preference was selected.
    case declaredFallback // Indicates an explicitly ordered fallback model was selected.
    case capabilityFallback // Indicates registry capability matching supplied the model.
    case legacyFallback // Indicates the migrated V0.1 model preserved compatibility.
    case activeModelReuse // Indicates switching policy reused the already loaded compatible model.

    var displayName: String { // Produces trace-safe selection reason text.
        switch self { // Selects a concise operational label.
        case .preferredModel: return "Preferred model" // Labels the primary assignment path.
        case .capabilityPreference: return "Capability preference" // Labels a user-selected capability default.
        case .declaredFallback: return "Declared fallback" // Labels explicit ordered recovery.
        case .capabilityFallback: return "Capability fallback" // Labels dynamic compatible recovery.
        case .legacyFallback: return "Legacy fallback" // Labels V0.1 compatibility recovery.
        case .activeModelReuse: return "Active model reuse" // Labels a deterministic no-switch optimization.
        } // Ends reason-label selection.
    } // Ends reason display-name access.
} // Ends model-selection reasons.

struct ModelSelection: Codable, Hashable { // Captures one deterministic ModelRouter decision for trace and UI.
    let requestedAgentID: String // Records the agent requiring a runtime model.
    let preferredModelID: String? // Records the assignment preference even when unavailable.
    let selectedModelID: String // Records the actual registered model chosen.
    let reason: ModelSelectionReason // Records the deterministic selection path.
    let usedFallback: Bool // Records whether actual selection differed from the preferred model.
} // Ends the structured model-selection result.
