import XCTest // Supplies deterministic unit-test assertions for the V0.5 logical routing foundation.
@testable import AutoMLXStudio // Exposes internal registry, taxonomy, router, and director contracts to the test target.

final class V05RoutingTests: XCTestCase { // Verifies logical specialists, exact boundaries, deterministic precedence, and bounded compound plans.
    private let router = DeterministicFastRouter() // Uses the production zero-inference router for every taxonomy assertion.
    private let agentRegistry = AgentRegistry() // Uses the production logical registry for identity and prompt assertions.

    func testLogicalSpecialistsAreRegisteredExactlyOnce() throws { // Confirms every requested V0.5 specialist exists without duplicate logical identities.
        let expectedIDs = [AgentID.python, AgentID.cAndCpp, AgentID.cSharp, AgentID.web, AgentID.database, AgentID.math, AgentID.data, AgentID.document] // Lists the eight bounded logical additions.
        let registeredIDs = agentRegistry.agents.map(\.id) // Reads stable registry order without mutating configuration.
        XCTAssertEqual(Set(expectedIDs).count, expectedIDs.count) // Confirms aliases did not create duplicate expected identities.
        for identifier in expectedIDs { // Validates each requested logical specialist independently.
            let agent = try XCTUnwrap(agentRegistry.agent(id: identifier)) // Resolves the exact registered definition.
            XCTAssertEqual(agent.kind, .specialist) // Confirms every addition is a specialist rather than an orchestration stage.
            XCTAssertEqual(registeredIDs.filter { $0 == identifier }.count, 1) // Confirms the definition occurs exactly once.
        } // Ends logical-specialist validation.
    } // Ends logical registry coverage testing.

    func testLogicalSpecialistsReuseExistingPhysicalCatalogModels() throws { // Confirms specialization adds assignments rather than physical model profiles.
        let missingRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-V05-Missing-\(UUID().uuidString)").path // Creates a unique path that is intentionally never written.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: "legacy/local-model", modelsRoot: missingRoot) // Builds production defaults without downloads or filesystem mutation.
        XCTAssertEqual(registry.assignment(for: AgentID.python)?.preferredModelID, Project5ModelCatalog.coding) // Confirms Python shares the installed coder choice.
        XCTAssertEqual(registry.assignment(for: AgentID.cAndCpp)?.preferredModelID, Project5ModelCatalog.coding) // Confirms C/C++ shares the installed coder choice.
        XCTAssertEqual(registry.assignment(for: AgentID.cSharp)?.preferredModelID, Project5ModelCatalog.coding) // Confirms C# shares the installed coder choice.
        XCTAssertEqual(registry.assignment(for: AgentID.web)?.preferredModelID, Project5ModelCatalog.coding) // Confirms Web shares the installed coder choice.
        XCTAssertEqual(registry.assignment(for: AgentID.database)?.preferredModelID, Project5ModelCatalog.coding) // Confirms Database shares the installed coder choice.
        XCTAssertEqual(registry.assignment(for: AgentID.math)?.preferredModelID, Project5ModelCatalog.reasoning) // Confirms Math shares the installed reasoning choice.
        XCTAssertEqual(registry.assignment(for: AgentID.data)?.preferredModelID, Project5ModelCatalog.reasoning) // Confirms Data shares the installed reasoning choice.
        XCTAssertEqual(registry.assignment(for: AgentID.document)?.preferredModelID, Project5ModelCatalog.general) // Confirms Document shares the installed general choice.
        XCTAssertNil(registry.model(id: AgentID.python)) // Confirms an agent identity was not incorrectly added as a physical model identity.
        XCTAssertNil(registry.model(id: AgentID.database)) // Confirms another logical agent did not create a physical catalog entry.
    } // Ends shared-physical-model testing.

    func testEachNewTaxonomyIntentRoutesDeterministically() { // Exercises a clear primary example for all eight requested logical specialists.
        let examples: [(request: String, intent: UserIntent)] = [ // Declares stable representative requests and expected primary intents.
            ("Debug Python FastAPI dependency injection.", .python), // Covers explicit Python framework routing.
            ("Fix this CMake configuration for a C++ template library.", .cpp), // Covers explicit C++ and CMake routing.
            ("Build an Avalonia view in C# and .NET.", .cSharp), // Covers explicit C# and .NET routing.
            ("Create an accessible HTML and CSS frontend.", .web), // Covers local web-development routing.
            ("Design SQL indexes for this relational schema.", .database), // Covers non-executing database expertise routing.
            ("Solve the equation using linear algebra.", .math), // Covers formal mathematical reasoning routing.
            ("Analyze data quality in this CSV dataset.", .data), // Covers structured-data analysis routing.
            ("Summarize this project document and extract key points.", .document) // Covers project-document transformation routing.
        ] // Ends representative taxonomy examples.
        for example in examples { // Routes every example through the same production entry point.
            XCTAssertEqual(router.route(example.request).intent, example.intent, "Unexpected route for: \(example.request)") // Confirms exact deterministic intent selection.
        } // Ends taxonomy example iteration.
    } // Ends complete new-intent routing testing.

    func testStandaloneCUsesExactBoundariesWithoutFalsePositives() { // Proves the shortest language name cannot match arbitrary surrounding text.
        XCTAssertEqual(router.route("Write a C function that owns a pointer.").intent, .cpp) // Confirms a standalone C token selects C/C++ Agent.
        XCTAssertEqual(router.route("Explain concurrency cancellation semantics.").intent, .general) // Confirms C inside ordinary words does not select C/C++ Agent.
        XCTAssertEqual(router.route("Can you clarify this concept?").intent, .general) // Confirms common prose containing the letter c remains general.
        XCTAssertFalse(RoutingTaxonomy.classify("Explain concurrency cancellation semantics.").matchedIntents.contains(.cpp)) // Confirms C/C++ is absent even from secondary-planning metadata.
    } // Ends exact standalone-C boundary testing.

    func testCVariantsRemainDistinct() { // Confirms punctuation-aware tokenization separates C, C++, and C# ecosystems.
        let cppClassification = RoutingTaxonomy.classify("Use C++ RAII and templates.") // Classifies an explicit modern C++ request.
        let cSharpClassification = RoutingTaxonomy.classify("Use C# with ASP.NET and Entity Framework.") // Classifies an explicit C# request.
        XCTAssertEqual(cppClassification.primaryIntent, .cpp) // Confirms C++ selects the C/C++ logical specialist.
        XCTAssertFalse(cppClassification.matchedIntents.contains(.cSharp)) // Confirms C++ does not leak into C# metadata.
        XCTAssertEqual(cSharpClassification.primaryIntent, .cSharp) // Confirms C# selects the C# logical specialist.
        XCTAssertFalse(cSharpClassification.matchedIntents.contains(.cpp)) // Confirms the exact C signal does not match the C in C#.
    } // Ends C-family punctuation disambiguation testing.

    func testSwiftPrecedenceSuppressesAmbiguousCppConcepts() { // Confirms weak C++ concepts cannot steal named Swift development work.
        let classification = RoutingTaxonomy.classify("Explain Swift memory management and generic templates.") // Combines explicit Swift with concepts that can occur in several languages.
        XCTAssertEqual(classification.primaryIntent, .swift) // Confirms Swift remains the primary named language.
        XCTAssertFalse(classification.matchedIntents.contains(.cpp)) // Confirms ambiguous concept-only C/C++ support is suppressed.
    } // Ends Swift-versus-C/C++ ambiguity testing.

    func testResearchPrecedenceCanRetainOneSwiftSecondary() throws { // Documents the chosen Research-versus-Swift ambiguity behavior.
        let request = "Research Swift concurrency and find sources." // Supplies explicit research and Swift signals.
        let decision = router.route(request) // Routes through the production deterministic precedence.
        let plan = try Director(registry: agentRegistry).makePlan(for: decision, request: request) // Converts the route into a bounded plan.
        XCTAssertEqual(decision.intent, .research) // Confirms explicit source-seeking language remains primary for compatibility.
        XCTAssertEqual(plan.specialistID, AgentID.research) // Confirms Research Agent owns the primary response.
        XCTAssertEqual(plan.secondarySpecialistID, AgentID.swift) // Confirms one Swift specialist may provide bounded domain support.
    } // Ends research ambiguity and secondary-planning testing.

    func testSwiftAndSQLPlanUsesOneDatabaseSecondary() throws { // Verifies the canonical compound request from the V0.5 brief.
        let request = "Write a Swift app that calls a SQL database." // Supplies one primary language and one clear supporting domain.
        let decision = router.route(request) // Applies the fixed precedence table.
        let plan = try Director(registry: agentRegistry).makePlan(for: decision, request: request) // Creates the non-recursive execution metadata.
        XCTAssertEqual(decision.intent, .swift) // Confirms Swift remains primary ahead of the database domain.
        XCTAssertEqual(plan.specialistID, AgentID.swift) // Confirms Swift Agent is the primary specialist.
        XCTAssertEqual(plan.secondarySpecialistID, AgentID.database) // Confirms Database Agent is the single optional supporting specialist.
    } // Ends canonical Swift-plus-database planning testing.

    func testCompoundPlanIsCappedAtOneSecondary() throws { // Confirms adding more explicit domains cannot produce an unbounded agent list.
        let request = "Write a Swift app using SQL to analyze data from a CSV dataset." // Supplies Swift, database, and data-analysis signals.
        let decision = router.route(request) // Selects the first domain by documented precedence.
        let plan = try Director(registry: agentRegistry).makePlan(for: decision, request: request) // Produces the fixed-shape plan contract.
        XCTAssertEqual(plan.specialistID, AgentID.swift) // Confirms Swift remains primary.
        XCTAssertEqual(plan.secondarySpecialistID, AgentID.database) // Confirms deterministic precedence chooses only the first supporting domain.
    } // Ends bounded compound-agent-count testing.

    func testGenericCodingSignalDoesNotCreateRedundantSecondary() throws { // Confirms common verbs do not add Coding Agent behind a named specialist.
        let request = "Write a Python function that returns the largest number in an array." // Combines explicit Python with established generic coding signals.
        let decision = router.route(request) // Routes the named language ahead of generic coding.
        let plan = try Director(registry: agentRegistry).makePlan(for: decision, request: request) // Builds the bounded plan.
        XCTAssertEqual(plan.specialistID, AgentID.python) // Confirms the logical Python specialist owns the request.
        XCTAssertNil(plan.secondarySpecialistID) // Confirms redundant generic Coding Agent is not scheduled.
    } // Ends redundant-secondary prevention testing.

    func testLegacyPlanInitializerDefaultsSecondaryToNil() { // Proves existing initializer call sites remain source-compatible.
        let plan = WorkflowExecutionPlan(intent: .general, specialistID: AgentID.general, reviewerID: AgentID.reviewer, finalComposerID: AgentID.finalComposer, qualityPolicy: .direct) // Uses the exact pre-V0.5 argument surface.
        XCTAssertNil(plan.secondarySpecialistID) // Confirms legacy plans remain single-specialist by default.
    } // Ends workflow-plan compatibility testing.

    func testLegacyGeneralQualityPolicyRemainsDirect() throws { // Confirms V0.5 specialization does not alter the established trivial-request optimization.
        let request = "What is a CPU?" // Uses the exact legacy general acceptance request.
        let decision = router.route(request) // Routes through the expanded taxonomy.
        let plan = try Director(registry: agentRegistry).makePlan(for: decision, request: request) // Applies the preserved quality policy.
        XCTAssertEqual(decision.intent, .general) // Confirms no new specialist steals the legacy general request.
        XCTAssertEqual(plan.qualityPolicy, .direct) // Confirms the reviewer and composer optimization remains compatible.
        XCTAssertNil(plan.secondarySpecialistID) // Confirms the legacy request remains a one-specialist plan.
    } // Ends legacy quality-policy compatibility testing.

    func testWebAndDatabasePromptsDoNotClaimExternalAccess() throws { // Confirms logical expertise is not represented as a real connector or execution tool.
        let webPrompt = try XCTUnwrap(agentRegistry.agent(id: AgentID.web)?.systemPrompt.lowercased()) // Reads the production Web Agent prompt.
        let databasePrompt = try XCTUnwrap(agentRegistry.agent(id: AgentID.database)?.systemPrompt.lowercased()) // Reads the production Database Agent prompt.
        XCTAssertTrue(webPrompt.contains("no browser")) // Confirms Web Agent states the lack of a live browser and internet surface.
        XCTAssertTrue(webPrompt.contains("never claim live verification")) // Confirms the prompt forbids fabricated external verification.
        XCTAssertTrue(databasePrompt.contains("cannot connect")) // Confirms Database Agent states the lack of an external connection.
        XCTAssertTrue(databasePrompt.contains("never claim execution")) // Confirms the prompt forbids fabricated query execution.
    } // Ends external-capability truthfulness testing.
} // Ends the V0.5 routing foundation test suite.
