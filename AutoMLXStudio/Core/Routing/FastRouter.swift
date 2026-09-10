import Foundation // Supplies deterministic string normalization and collection support for routing.

protocol FastRouting { // Isolates intent classification so a small model can replace the rules later.
    func route(_ request: String) -> RoutingDecision // Converts user text into a structured routing intent.
    func route(_ request: UserRequest) -> RoutingDecision // Converts typed text and attachments into a multimodal-ready structured intent.
} // Ends the fast-router interface.

extension FastRouting { // Preserves source compatibility for existing routers and test doubles.
    func route(_ request: UserRequest) -> RoutingDecision { // Supplies a text-only default for implementations not yet attachment-aware.
        route(request.text) // Delegates to the proven text routing rule.
    } // Ends the compatibility typed-request route.
} // Ends FastRouting compatibility behavior.

struct RoutingTaxonomyClassification: Equatable { // Stores ordered deterministic taxonomy matches without exposing implementation rules to workflows.
    let primaryIntent: UserIntent // Stores the highest-precedence matched intent or the general fallback.
    let matchedIntents: [UserIntent] // Stores unique explicit matches in documented precedence order for bounded secondary planning.
    let confidence: Double // Stores the primary rule's stable operational confidence.
    let summary: String // Stores the primary rule's trace-safe explanation.
} // Ends the reusable taxonomy-classification value.

private struct RoutingTaxonomyRule { // Describes one declarative intent rule and its exact bounded signals.
    let intent: UserIntent // Identifies the intent selected when this rule has highest precedence.
    let confidence: Double // Provides a stable operational score without pretending to be learned probability.
    let summary: String // Provides a short trace-safe reason for the route.
    let explicitSignals: [String] // Lists strong bounded phrases that independently identify the intent.
    let contextualSignals: [String] // Lists weaker bounded phrases accepted only under the rule's ambiguity guard.
} // Ends one declarative taxonomy rule.

enum RoutingTaxonomy { // Owns the documented V0.5 deterministic precedence shared by Fast Router and Director.
    static func classify(_ request: String) -> RoutingTaxonomyClassification { // Evaluates one request without inference, I/O, or mutable state.
        let normalized = request.lowercased() // Normalizes case while preserving punctuation needed to distinguish C, C++, and C#.
        let explicitIntents = Set(orderedRules.compactMap { rule in // Finds every strong rule before considering ambiguous contextual concepts.
            containsAny(normalized, signals: rule.explicitSignals) ? rule.intent : nil // Records a rule only when an exact bounded signal matches.
        }) // Ends strong-match collection.
        let explicitLanguageIntents = explicitIntents.intersection(languageIntents) // Detects named languages that suppress ambiguous C/C++ concept-only matches.
        let matchedRules = orderedRules.filter { rule in // Retains all valid matches in the single documented precedence order.
            if explicitIntents.contains(rule.intent) { return true } // Accepts every explicit domain signal immediately.
            guard containsAny(normalized, signals: rule.contextualSignals) else { return false } // Rejects rules with neither explicit nor contextual evidence.
            if rule.intent == .cpp, !explicitLanguageIntents.isEmpty { return false } // Prevents words such as templates or memory management from stealing Swift and other named-language requests.
            return true // Accepts an unambiguous contextual concept when no guard excludes it.
        } // Ends ordered rule filtering.
        guard let primaryRule = matchedRules.first else { // Uses the broad safe fallback when no specialist evidence exists.
            return RoutingTaxonomyClassification( // Creates a deterministic general classification.
                primaryIntent: .general, // Selects the broad General Agent intent.
                matchedIntents: [], // Records that no explicit specialist signal was present.
                confidence: 0.70, // Preserves the established general fallback score.
                summary: "No specialist domain signal was required." // Preserves the established general fallback explanation.
            ) // Ends general fallback construction.
        } // Ends no-match fallback handling.
        return RoutingTaxonomyClassification( // Creates one complete ordered specialist classification.
            primaryIntent: primaryRule.intent, // Selects the first rule according to documented precedence.
            matchedIntents: matchedRules.map(\.intent), // Exposes bounded unique matches for optional secondary planning.
            confidence: primaryRule.confidence, // Preserves the stable score owned by the primary rule.
            summary: primaryRule.summary // Preserves the trace-safe explanation owned by the primary rule.
        ) // Ends specialist classification construction.
    } // Ends declarative request classification.

    private static func containsAny(_ request: String, signals: [String]) -> Bool { // Applies exact token boundaries to every declarative signal family.
        signals.contains { containsBoundedPhrase(request, phrase: $0) } // Returns true as soon as one bounded phrase matches.
    } // Ends bounded signal-family matching.

    private static func containsBoundedPhrase(_ request: String, phrase: String) -> Bool { // Avoids substring collisions such as C inside concurrency or Swift inside Swiftly.
        guard !request.isEmpty, !phrase.isEmpty else { return false } // Rejects empty inputs instead of treating them as universal matches.
        var searchStart = request.startIndex // Starts scanning at the beginning of normalized text.
        while searchStart < request.endIndex, let range = request.range(of: phrase, range: searchStart..<request.endIndex) { // Visits every literal occurrence until one has valid token boundaries.
            let leftIsBounded = range.lowerBound == request.startIndex || !isIdentifierCharacter(request[request.index(before: range.lowerBound)]) // Requires a non-identifier character before the phrase.
            let rightIsBounded = range.upperBound == request.endIndex || !isIdentifierCharacter(request[range.upperBound]) // Requires a non-identifier character after the phrase.
            if leftIsBounded, rightIsBounded { return true } // Accepts only the exact standalone token or phrase.
            searchStart = range.upperBound > searchStart ? range.upperBound : request.index(after: searchStart) // Advances monotonically after a rejected embedded occurrence.
        } // Ends literal occurrence scanning.
        return false // Reports no match when every occurrence was embedded in another identifier.
    } // Ends exact bounded-phrase matching.

    private static func isIdentifierCharacter(_ character: Character) -> Bool { // Defines language-aware token characters for exact specialist matching.
        character.isLetter || character.isNumber || character == "_" || character == "+" || character == "#" || character == "." // Keeps C++, C#, .NET, and dotted framework names indivisible.
    } // Ends routing identifier-character classification.

    private static let languageIntents: Set<UserIntent> = [.swift, .python, .cpp, .cSharp, .web] // Lists explicit programming-language families used by the C/C++ ambiguity guard.

    // Precedence is intentionally fixed: explicit research, Swift/Apple, named languages, database, math, data, document transformation, then generic coding.
    private static let orderedRules: [RoutingTaxonomyRule] = [ // Declares the entire readable deterministic taxonomy in one data table.
        RoutingTaxonomyRule( // Gives explicit source-seeking wording first priority to preserve the established Research route.
            intent: .research, // Selects the context-only Research Agent.
            confidence: 0.98, // Preserves the established explicit-research score.
            summary: "Matched a documentation or source-oriented request.", // Preserves a concise non-reasoning trace explanation.
            explicitSignals: ["find documentation", "find docs", "documentation about", "official documentation", "research", "look up", "search for", "find sources", "citation", "citations", "cite source", "cite sources"], // Lists bounded source-oriented signals without claiming a real web search.
            contextualSignals: [] // Requires explicit research wording because generic domain knowledge belongs to another specialist.
        ), // Ends the Research taxonomy rule.
        RoutingTaxonomyRule( // Keeps Apple-development wording ahead of generic and supporting technical domains.
            intent: .swift, // Selects Swift Agent.
            confidence: 0.98, // Preserves the established explicit-Swift score.
            summary: "Matched Swift or Apple-platform development context.", // Preserves the established Swift trace explanation.
            explicitSignals: ["swift", "swiftui", "appkit", "uikit", "xcode", "avfoundation", "metal", "apple development", "ios development", "macos development"], // Lists exact Apple-platform signals so Swift remains primary in Swift-plus-SQL requests.
            contextualSignals: [] // Avoids inferring Swift merely from general application wording.
        ), // Ends the Swift taxonomy rule.
        RoutingTaxonomyRule( // Routes named Python work to its logical coding specialist.
            intent: .python, // Selects Python Agent.
            confidence: 0.98, // Records high confidence for explicit language and ecosystem names.
            summary: "Matched Python development context.", // Provides a concise Python route explanation.
            explicitSignals: ["python", "python3", "pytest", "pip", "poetry", "django", "flask", "fastapi", "asyncio", "type hints", "standard library"], // Lists bounded Python language, framework, and tooling signals.
            contextualSignals: [] // Requires an explicit Python ecosystem signal.
        ), // Ends the Python taxonomy rule.
        RoutingTaxonomyRule( // Routes C and C++ only through exact language tokens or unambiguous systems concepts.
            intent: .cpp, // Selects C/C++ Agent.
            confidence: 0.97, // Records high confidence while acknowledging concept-only routing can be broader.
            summary: "Matched C or C++ development context.", // Provides a concise C/C++ route explanation.
            explicitSignals: ["c", "c language", "c programming", "c code", "c++", "cpp", "cmake", "iostream", "std::vector", "raii"], // Uses exact boundaries so C never matches concurrency, C#, C++, or arbitrary words.
            contextualSignals: ["memory management", "pointer", "pointers", "template", "templates", "undefined behavior"] // Supports requested C/C++ concepts only when another named language is absent.
        ), // Ends the C/C++ taxonomy rule.
        RoutingTaxonomyRule( // Routes the distinct C# and .NET ecosystem without colliding with exact C tokens.
            intent: .cSharp, // Selects C# Agent.
            confidence: 0.98, // Records high confidence for explicit ecosystem names.
            summary: "Matched C# or .NET development context.", // Provides a concise C# route explanation.
            explicitSignals: ["c#", "c sharp", ".net", "dotnet", "avalonia", "asp.net", "entity framework", "blazor", "xamarin"], // Lists bounded C# language, framework, and tooling signals.
            contextualSignals: [] // Requires an explicit C# ecosystem signal.
        ), // Ends the C# taxonomy rule.
        RoutingTaxonomyRule( // Routes local web-development expertise without implying live internet access.
            intent: .web, // Selects Web Agent.
            confidence: 0.96, // Records high confidence for explicit web technologies.
            summary: "Matched frontend or web-development context.", // Provides a concise truthful Web route explanation.
            explicitSignals: ["html", "css", "javascript", "typescript", "frontend", "front end", "react", "vue", "angular", "svelte", "node.js", "web app", "dom", "browser api"], // Lists bounded client and common web-platform signals.
            contextualSignals: [] // Avoids treating research or ordinary mentions of a website as coding work.
        ), // Ends the Web taxonomy rule.
        RoutingTaxonomyRule( // Routes relational storage design and SQL to the logical Database specialist.
            intent: .database, // Selects Database Agent.
            confidence: 0.96, // Records high confidence for explicit database concepts.
            summary: "Matched SQL or relational-database context.", // Provides a concise database route explanation.
            explicitSignals: ["sql", "sqlite", "postgres", "postgresql", "mysql", "database", "schema design", "query plan", "queries", "index", "indexes", "relational model", "relational modeling", "transaction", "transactions"], // Lists bounded relational and query-design signals without claiming execution access.
            contextualSignals: [] // Requires explicit database terminology.
        ), // Ends the Database taxonomy rule.
        RoutingTaxonomyRule( // Routes explicit formal and quantitative reasoning to the logical Math specialist.
            intent: .math, // Selects Math Agent.
            confidence: 0.95, // Records high confidence for named mathematical tasks.
            summary: "Matched mathematical reasoning context.", // Provides a concise mathematics route explanation.
            explicitSignals: ["solve the equation", "equation", "algebra", "calculus", "geometry", "trigonometry", "probability", "theorem", "proof", "derivative", "integral", "linear algebra"], // Lists bounded mathematical fields and operations.
            contextualSignals: [] // Requires explicit mathematics wording rather than inferring from any number.
        ), // Ends the Math taxonomy rule.
        RoutingTaxonomyRule( // Routes structured-data reasoning separately from database design and generic coding.
            intent: .data, // Selects Data Agent.
            confidence: 0.94, // Records stable confidence for data-analysis terminology.
            summary: "Matched structured-data analysis context.", // Provides a concise Data route explanation.
            explicitSignals: ["data analysis", "analyze data", "analyse data", "dataset", "datasets", "dataframe", "pandas", "csv", "tabular", "statistics", "statistical analysis", "data cleaning", "data quality", "visualize data", "visualise data"], // Lists bounded analytical signals without colliding with the word database.
            contextualSignals: [] // Requires explicit analysis or structured-data terminology.
        ), // Ends the Data taxonomy rule.
        RoutingTaxonomyRule( // Routes transformations of supplied or project documents to the logical Document specialist.
            intent: .document, // Selects Document Agent.
            confidence: 0.94, // Records stable confidence for explicit transformation requests.
            summary: "Matched document transformation or extraction context.", // Provides a concise Document route explanation.
            explicitSignals: ["summarize", "summarise", "rewrite", "proofread", "structured extraction", "extract fields", "extract key points", "project document", "project documents", "document summary"], // Lists bounded document operations without stealing documentation research.
            contextualSignals: [] // Requires an explicit document transformation operation.
        ), // Ends the Document taxonomy rule.
        RoutingTaxonomyRule( // Retains the established broad coding route after every more specific specialist.
            intent: .coding, // Selects Coding Agent.
            confidence: 0.92, // Preserves the established generic-coding score.
            summary: "Matched a general software-development request.", // Preserves the established coding trace explanation.
            explicitSignals: ["programming", "write a function", "write code", "source code", "algorithm", "debug", "debugging", "bug", "crash", "compile", "compiler", "api", "array"], // Lists bounded language-neutral development signals used by legacy routing tests.
            contextualSignals: [] // Requires explicit development wording.
        ) // Ends the generic Coding taxonomy rule.
    ] // Ends the fixed deterministic precedence table.
} // Ends the shared V0.5 routing taxonomy.

struct DeterministicFastRouter: FastRouting { // Implements the fast zero-inference router while preserving legacy and Vision behavior.
    func route(_ request: UserRequest) -> RoutingDecision { // Classifies text and attachments without model inference.
        let normalized = request.text.lowercased() // Normalizes the textual portion for ordered multimodal and service rules.
        if request.hasImageAttachment { // Gives actual validated image evidence first priority while preserving the user's requested domain outcome.
            let classification = RoutingTaxonomy.classify(request.text) // Resolves any explicit text-domain owner through the shared deterministic taxonomy.
            if classification.primaryIntent != .general { // Keeps a named technical or content specialist responsible for the final response.
                return RoutingDecision(intent: classification.primaryIntent, confidence: 1.0, summary: "Image evidence will assist the selected \(classification.primaryIntent.rawValue) specialist.", requiresVisionAnalysis: true) // Routes Vision evidence into the selected specialist without changing the bounded plan.
            } // Ends image-assisted domain routing.
            return RoutingDecision(intent: .vision, confidence: 1.0, summary: "A validated image attachment requires a direct Vision response.", requiresVisionAnalysis: true) // Routes photo-description and other pure visual questions directly to Vision.
        } // Ends image-first domain-aware routing.
        if request.attachments.contains(where: { $0.kind == .audio }) || Self.containsAny(normalized, signals: Self.voiceSignals) { // Gives explicit Voice and audio work priority before text-only specialist signals.
            return RoutingDecision(intent: .general, confidence: 0.96, summary: "Voice or audio input requires the dedicated audio service before agent routing.") // Keeps Audio a service rather than inventing an Audio agent.
        } // Ends explicit Voice/audio classification.
        if Self.containsAny(normalized, signals: Self.visionSignals) { // Detects explicit visual-analysis wording even before an image is attached.
            return RoutingDecision(intent: .vision, confidence: 0.94, summary: "Matched an explicit visual-analysis request.", requiresVisionAnalysis: true) // Returns structured Vision intent metadata.
        } // Ends text-only Vision classification.
        return route(request.text) // Uses the same deterministic text taxonomy when no attachment-specific rule applies.
    } // Ends typed multimodal request classification.

    func route(_ request: String) -> RoutingDecision { // Classifies one user request through the shared declarative taxonomy.
        let classification = RoutingTaxonomy.classify(request) // Evaluates the complete documented precedence exactly once.
        return RoutingDecision(intent: classification.primaryIntent, confidence: classification.confidence, summary: classification.summary) // Converts taxonomy output into the preserved router contract.
    } // Ends deterministic text request classification.

    private static func containsAny(_ request: String, signals: [String]) -> Bool { // Reuses service matching without exposing taxonomy internals.
        signals.contains { signal in // Visits each service phrase until a safe literal match is found.
            request.range(of: signal, options: [.caseInsensitive]) != nil // Preserves the established service phrase behavior for Voice and Vision wording.
        } // Ends service signal evaluation.
    } // Ends service signal matching.

    private static let visionSignals = [ // Lists explicit visual-analysis wording used when no attachment exists yet.
        "analyze this image", // Matches direct image-understanding requests.
        "analyse this image", // Matches the alternate English spelling.
        "look at this image", // Matches conversational image requests.
        "screenshot", // Matches screenshot and UI-diagnostic requests.
        "what is shown in the image", // Matches evidence-oriented image questions.
        "visual analysis" // Matches explicit visual-analysis requests.
    ] // Ends Vision signal collection.

    private static let voiceSignals = [ // Lists explicit speech and audio service requests evaluated before text-only specialist signals.
        "transcribe this audio", // Matches direct ASR requests.
        "speech to text", // Matches explicit ASR terminology.
        "text to speech", // Matches explicit TTS terminology.
        "voice message", // Matches conversational Voice input.
        "read this aloud" // Matches explicit response-synthesis requests.
    ] // Ends Voice and audio service signals.
} // Ends the deterministic fast router.
