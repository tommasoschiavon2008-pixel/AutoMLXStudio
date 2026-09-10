import Foundation // Supplies localized error support and request tokenization.

enum WorkflowDirectorError: LocalizedError { // Defines deterministic plan failures that the workflow can recover from visibly.
    case missingSpecialist(String) // Reports a centralized mapping that points to an unavailable agent.

    var errorDescription: String? { // Produces a concise diagnostic suitable for logs and trace metadata.
        switch self { // Selects the message for the current director failure.
        case let .missingSpecialist(identifier): return "The selected specialist is not registered: \(identifier)" // Describes the missing registry key.
        } // Ends director error message selection.
    } // Ends the localized director error accessor.
} // Ends the director-error definition.

protocol WorkflowDirecting { // Isolates plan creation from the workflow execution engine.
    func makePlan(for decision: RoutingDecision, request: String) throws -> WorkflowExecutionPlan // Converts structured intent into one centralized execution plan.
} // Ends the director interface.

struct Director: WorkflowDirecting { // Implements deterministic specialist selection, bounded compound planning, and the preserved quality policy.
    private let registry: AgentRegistry // Provides validation that mapped agents actually exist.

    init(registry: AgentRegistry) { // Injects the central agent registry used for plan validation.
        self.registry = registry // Stores the registry for deterministic lookups.
    } // Ends director construction.

    func makePlan(for decision: RoutingDecision, request: String) throws -> WorkflowExecutionPlan { // Builds one complete workflow plan.
        let specialistID = Self.specialistMapping[decision.intent] ?? AgentID.general // Uses the central intent-to-specialist mapping with a safe general fallback.
        guard registry.agent(id: specialistID) != nil else { // Verifies the selected specialist before inference begins.
            throw WorkflowDirectorError.missingSpecialist(specialistID) // Surfaces a traceable missing-agent failure.
        } // Ends specialist registry validation.
        let secondarySpecialistID = Self.secondarySpecialistID(primaryIntent: decision.intent, request: request) // Selects zero or one explicit supporting domain without recursive planning.
        if let secondarySpecialistID, registry.agent(id: secondarySpecialistID) == nil { // Validates an optional supporting specialist exactly like the primary specialist.
            throw WorkflowDirectorError.missingSpecialist(secondarySpecialistID) // Surfaces a traceable registry inconsistency before inference begins.
        } // Ends optional supporting-specialist validation.

        return WorkflowExecutionPlan( // Returns a complete plan consumed only by WorkflowEngine.
            intent: decision.intent, // Preserves the structured intent.
            specialistID: specialistID, // Stores the selected specialist key.
            reviewerID: AgentID.reviewer, // Stores the centralized reviewer key.
            finalComposerID: AgentID.finalComposer, // Stores the centralized composer key.
            qualityPolicy: Self.qualityPolicy(for: decision.intent, request: request), // Applies the explicit V0.1 performance rule.
            requiresVisionAnalysis: decision.requiresVisionAnalysis, // Preserves deterministic image-assisted technical routing.
            nextLikelyModelID: nil, // Leaves future prefetch metadata explicit without starting unsafe concurrent loading.
            secondarySpecialistID: secondarySpecialistID // Stores at most one deterministic supporting specialist for later bounded execution.
        ) // Ends execution-plan construction.
    } // Ends deterministic plan creation.

    private static let specialistMapping: [UserIntent: String] = [ // Centralizes every supported routing destination without embedding physical models.
        .general: AgentID.general, // Sends general questions to General Agent.
        .coding: AgentID.coding, // Sends general development work to Coding Agent.
        .swift: AgentID.swift, // Sends Apple-platform work to Swift Agent.
        .research: AgentID.research, // Sends source-oriented work to Research Agent.
        .python: AgentID.python, // Sends explicit Python work to the logical Python specialist.
        .cpp: AgentID.cAndCpp, // Sends explicit C and C++ work to the logical C/C++ specialist.
        .cSharp: AgentID.cSharp, // Sends explicit C# and .NET work to the logical C# specialist.
        .web: AgentID.web, // Sends frontend and web coding work to the logical Web specialist.
        .database: AgentID.database, // Sends SQL and relational design work to the logical Database specialist.
        .math: AgentID.math, // Sends explicit mathematical reasoning to the logical Math specialist.
        .data: AgentID.data, // Sends structured-data analysis to the logical Data specialist.
        .document: AgentID.document, // Sends document transformation work to the logical Document specialist.
        .vision: AgentID.vision // Sends image-bearing and visual-analysis requests to Vision Agent.
    ] // Ends the centralized specialist mapping.

    private static func secondarySpecialistID(primaryIntent: UserIntent, request: String) -> String? { // Produces a single bounded supporting specialist only from clear explicit taxonomy evidence.
        let classification = RoutingTaxonomy.classify(request) // Reuses the Fast Router's declarative signals and precedence instead of duplicating keyword rules.
        let supportingIntent = classification.matchedIntents.first { candidate in // Selects the first eligible distinct domain in deterministic precedence order.
            candidate != primaryIntent && secondaryEligibleIntents.contains(candidate) // Excludes the primary, general fallback, Vision service, and redundant generic Coding Agent.
        } // Ends bounded supporting-intent selection.
        guard let supportingIntent else { return nil } // Leaves ordinary single-domain requests on the proven one-specialist plan.
        return specialistMapping[supportingIntent] // Resolves the selected logical intent through the same centralized mapping as the primary.
    } // Ends optional supporting-specialist planning.

    private static let secondaryEligibleIntents: Set<UserIntent> = [.research, .swift, .python, .cpp, .cSharp, .web, .database, .math, .data, .document] // Bounds compound plans to one meaningful non-generic text specialist and prevents recursive swarms.

    private static func qualityPolicy(for intent: UserIntent, request: String) -> WorkflowQualityPolicy { // Applies one narrow deterministic optimization policy.
        let normalized = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() // Normalizes the request for stable policy evaluation.
        let wordCount = normalized.split(whereSeparator: { $0.isWhitespace }).count // Measures request length without model inference.
        let directPrefixes = ["what is ", "who is ", "define "] // Limits fast-path use to simple definition-shaped questions.
        let hasDirectPrefix = directPrefixes.contains { normalized.hasPrefix($0) } // Checks whether the request has an approved trivial form.
        let isSingleLine = !normalized.contains("\n") // Prevents multi-part prompts from using the direct path.

        if intent == .general, wordCount <= 10, hasDirectPrefix, isSingleLine { // Requires all explicit triviality conditions.
            return .direct // Skips reviewer and composer while recording both skipped stages.
        } // Ends direct-answer policy selection.

        return .full // Uses the complete three-inference pipeline for every other request.
    } // Ends workflow quality-policy selection.
} // Ends the deterministic director.
