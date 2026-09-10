import Foundation // Supplies Sendable protocols and deterministic text tokenization.

enum OptionalRetrievalRuntimeAvailability: Equatable, Sendable { // Describes whether an optional local retrieval model can genuinely execute.
    case available // Indicates model files and a supported runtime entrypoint are present.
    case unavailable(reason: String) // Preserves the actual missing model, package, or implementation boundary.
} // Ends retrieval-runtime availability.

protocol EmbeddingRuntimeServing: Sendable { // Defines a model-agnostic batched embedding boundary for future MLX integration.
    var modelID: String { get } // Reports the exact physical embedding model identity.
    var availability: OptionalRetrievalRuntimeAvailability { get } // Reports honest runtime availability without triggering downloads.
    func embed(_ texts: [String]) async throws -> [[Float]] // Produces one actual vector per supplied text when available.
} // Ends embedding runtime boundary.

struct EmbeddingRuntimeAdapter: EmbeddingRuntimeServing { // Provides the explicit V0.4 MLX embedding foundation without pretending unsupported inference works.
    let modelID: String // Stores the configured physical embedding profile identity.
    let availability: OptionalRetrievalRuntimeAvailability // Stores the audited missing-model or not-yet-integrated runtime reason.

    init(model: ModelProfile?) { // Audits a registry profile without network access or model mutation.
        self.modelID = model?.id ?? Project5ModelCatalog.embedding // Retains the catalog identity even when the optional model is absent.
        if let model, model.backend == .embedding, model.installationState == .installed { // Distinguishes installed weights from a working inference adapter.
            self.availability = .unavailable(reason: "Model files are present, but a compatible MLX embedding entrypoint has not been validated.") // Refuses to invent an API for an unverified runtime.
        } else { // Handles absent, incomplete, disabled, or wrong-backend catalog state.
            self.availability = .unavailable(reason: model?.statusDetail ?? "The optional Qwen3 embedding model is not installed.") // Preserves actual registry evidence when available.
        } // Ends embedding availability classification.
    } // Ends embedding adapter audit.

    func embed(_ texts: [String]) async throws -> [[Float]] { // Rejects inference until an actual compatible package contract is validated.
        let reason: String // Declares the exact unavailable explanation.
        if case let .unavailable(value) = availability { reason = value } else { reason = "No validated MLX embedding command is connected." } // Converts availability into an actionable failure.
        throw ProjectMemoryError.embeddingUnavailable(reason) // Never emits synthetic vectors.
    } // Ends unavailable embedding inference.
} // Ends honest embedding-runtime foundation.

protocol RerankerRuntimeServing: Sendable { // Defines a model-agnostic reranking boundary separate from RetrievalService orchestration.
    var modelID: String { get } // Reports the exact physical reranker identity.
    var availability: OptionalRetrievalRuntimeAvailability { get } // Reports honest optional runtime availability.
    func rerank(query: String, candidates: [MemorySearchResult]) async throws -> [MemorySearchResult] // Returns actual reordered candidates when supported.
} // Ends reranker runtime boundary.

struct RerankerRuntimeAdapter: RerankerRuntimeServing { // Provides the explicit V0.4 reranker foundation without synthetic scores.
    let modelID: String // Stores the configured physical reranker profile identity.
    let availability: OptionalRetrievalRuntimeAvailability // Stores the audited unavailable reason.

    init(model: ModelProfile?) { // Audits one optional reranker registry profile.
        self.modelID = model?.id ?? Project5ModelCatalog.reranker // Retains the future catalog identity even when absent.
        if let model, model.backend == .reranker, model.installationState == .installed { // Distinguishes installed weights from verified execution support.
            self.availability = .unavailable(reason: "Model files are present, but a compatible MLX reranker entrypoint has not been validated.") // Refuses to invent an unsupported command.
        } else { // Handles all not-installed and incompatible profile states.
            self.availability = .unavailable(reason: model?.statusDetail ?? "The optional Qwen3 reranker model is not installed.") // Preserves actual registry evidence when available.
        } // Ends reranker availability classification.
    } // Ends reranker adapter audit.

    func rerank(query: String, candidates: [MemorySearchResult]) async throws -> [MemorySearchResult] { // Rejects execution until a real package contract exists.
        let reason: String // Declares the exact unavailable explanation.
        if case let .unavailable(value) = availability { reason = value } else { reason = "No validated MLX reranker command is connected." } // Converts availability into an actionable failure.
        throw ProjectMemoryError.rerankerUnavailable(reason) // Never fabricates ranking scores.
    } // Ends unavailable reranking.
} // Ends honest reranker-runtime foundation.

enum VectorSimilarity { // Provides pure locally testable vector math independently from persistence or models.
    static func cosine(_ lhs: [Float], _ rhs: [Float]) throws -> Float { // Calculates cosine similarity for equal non-empty finite vectors.
        guard !lhs.isEmpty, lhs.count == rhs.count else { throw ProjectMemoryError.invalidVector("cosine inputs must have the same non-zero dimension.") } // Rejects incomparable inputs.
        guard lhs.allSatisfy(\.isFinite), rhs.allSatisfy(\.isFinite) else { throw ProjectMemoryError.invalidVector("cosine inputs must contain only finite values.") } // Rejects NaN and infinity propagation.
        var dot: Float = 0 // Accumulates the vector dot product.
        var lhsMagnitude: Float = 0 // Accumulates the squared left magnitude.
        var rhsMagnitude: Float = 0 // Accumulates the squared right magnitude.
        for index in lhs.indices { // Visits each validated dimension exactly once.
            dot += lhs[index] * rhs[index] // Adds the per-dimension dot product.
            lhsMagnitude += lhs[index] * lhs[index] // Adds the left squared magnitude.
            rhsMagnitude += rhs[index] * rhs[index] // Adds the right squared magnitude.
        } // Ends vector accumulation.
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { throw ProjectMemoryError.invalidVector("cosine inputs cannot have zero magnitude.") } // Rejects undefined cosine results.
        return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude)) // Returns the normalized similarity score.
    } // Ends cosine similarity calculation.
} // Ends pure vector similarity helpers.

struct ProjectVectorStore: Sendable { // Searches the simple JSON-backed vector records already owned by ProjectMemoryStore.
    let memoryStore: ProjectMemoryStore // Supplies isolated chunks, documents, and vector sidecars.

    func replace(projectID: UUID, records: [MemoryVectorRecord]) async throws { // Validates and persists one complete project vector batch.
        try await memoryStore.replaceVectors(projectID: projectID, records: records) // Delegates atomic cross-reference and dimension validation to the durable store.
    } // Ends vector batch replacement.

    func search(projectID: UUID, queryEmbedding: [Float], modelID: String, topK: Int) async throws -> [MemorySearchResult] { // Ranks stored vectors by local cosine similarity.
        guard topK > 0 else { return [] } // Returns no work for a zero or negative result limit.
        try Task.checkCancellation() // Stops before loading a potentially large local vector index.
        let vectors = try await memoryStore.vectors(projectID: projectID).filter { $0.modelID == modelID } // Restricts comparison to the same actual embedding model.
        let chunks = try await memoryStore.chunks(projectID: projectID) // Loads only project-owned source windows.
        let documents = try await memoryStore.documents(projectID: projectID) // Loads only project-owned source metadata.
        let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) }) // Builds a stable local chunk join index.
        let documentMap = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) }) // Builds a stable local document join index.
        var results: [MemorySearchResult] = [] // Accumulates validated scored joins.
        for record in vectors { // Scores each comparable stored vector exactly once.
            guard let chunk = chunkMap[record.chunkID], let document = documentMap[chunk.documentID] else { continue } // Ignores impossible stale joins defensively without crossing projects.
            guard record.chunkFingerprint == nil || record.chunkFingerprint == chunk.contentFingerprint else { continue } // Ignores explicitly stale vectors rather than comparing them to changed text.
            try Task.checkCancellation() // Allows cancellation during a large local cosine pass.
            let score = try VectorSimilarity.cosine(queryEmbedding, record.vector) // Calculates actual local cosine similarity.
            results.append(MemorySearchResult(chunk: chunk, document: document, score: score)) // Stores score with real source metadata.
        } // Ends stored-vector scoring.
        return results.sorted { lhs, rhs in if lhs.score != rhs.score { return lhs.score > rhs.score }; if lhs.document.id != rhs.document.id { return lhs.document.id.uuidString < rhs.document.id.uuidString }; return lhs.chunk.index < rhs.chunk.index }.prefix(topK).map { $0 } // Returns stable descending similarity order across documents and chunks.
    } // Ends local vector search.
} // Ends simple JSON-backed vector storage and search.

struct ProjectRetrievalOptions: Equatable, Sendable { // Configures candidate ranking independently from final prompt-context assembly limits.
    let resultLimit: Int // Stores the maximum ranked chunks returned to the context assembler.
    let candidateLimit: Int // Stores the wider candidate pool available to hybrid search or reranking.
    let usesHybridRanking: Bool // Enables deterministic lexical-plus-vector evidence only when actual vectors exist.

    init(resultLimit: Int = 5, candidateLimit: Int = 12, usesHybridRanking: Bool = true) { // Creates conservative defaults for project chat.
        self.resultLimit = max(0, resultLimit) // Prevents negative result limits.
        self.candidateLimit = max(max(0, resultLimit), candidateLimit) // Ensures the candidate pool can contain every final result.
        self.usesHybridRanking = usesHybridRanking // Stores the explicit ranking policy without implying an embedding runtime exists.
    } // Ends retrieval-option construction.
} // Ends retrieval ranking options.

struct ProjectMemoryRetrievalService: Sendable { // Orchestrates retrieval as a service rather than a fake autonomous agent.
    let memoryStore: ProjectMemoryStore // Supplies isolated project documents and chunks.
    let vectorStore: ProjectVectorStore // Supplies local cosine retrieval when actual embeddings exist.
    let embeddingRuntime: (any EmbeddingRuntimeServing)? // Supplies optional actual query embeddings.
    let rerankerRuntime: (any RerankerRuntimeServing)? // Supplies optional actual reranking.

    init(memoryStore: ProjectMemoryStore, embeddingRuntime: (any EmbeddingRuntimeServing)? = nil, rerankerRuntime: (any RerankerRuntimeServing)? = nil) { // Creates a retrieval pipeline with optional skip-capable model services.
        self.memoryStore = memoryStore // Stores durable source authority.
        self.vectorStore = ProjectVectorStore(memoryStore: memoryStore) // Searches the same isolated persisted vector records.
        self.embeddingRuntime = embeddingRuntime // Stores an optional real embedding boundary.
        self.rerankerRuntime = rerankerRuntime // Stores an optional real reranking boundary.
    } // Ends retrieval service construction.

    func retrieve(query: String, projectID: UUID, topK: Int = 5, candidateCount: Int = 12) async throws -> MemoryRetrievalResult { // Preserves the V0.4 Foundation call surface and vector-only behavior for existing integrations.
        try await retrieve(query: query, projectID: projectID, options: ProjectRetrievalOptions(resultLimit: topK, candidateLimit: candidateCount, usesHybridRanking: false)) // Delegates to the measured production pipeline without changing legacy mode expectations.
    } // Ends source-compatible retrieval.

    func retrieve(query: String, projectID: UUID, options: ProjectRetrievalOptions) async throws -> MemoryRetrievalResult { // Retrieves bounded project candidates with explicit hybrid and fallback behavior.
        let startedAt = DispatchTime.now().uptimeNanoseconds // Starts monotonic end-to-end retrieval timing.
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only query edges.
        guard !normalizedQuery.isEmpty, options.resultLimit > 0 else { return MemoryRetrievalResult(projectID: projectID, query: normalizedQuery, mode: .lexical, matches: [], citations: [], fallbackReason: "The retrieval query or result limit was empty.", durationMilliseconds: Self.elapsedMilliseconds(since: startedAt), candidateCount: 0) } // Returns an honest empty retrieval without model work.
        try Task.checkCancellation() // Stops before optional model or index work when the user cancelled.
        if let embeddingRuntime, case .available = embeddingRuntime.availability { // Uses embeddings only when the runtime explicitly claims availability.
            do { // Attempts actual query embedding and stored-vector retrieval.
                let vectors = try await embeddingRuntime.embed([normalizedQuery]) // Requests one actual query vector through the model-agnostic batch API.
                guard vectors.count == 1, let queryVector = vectors.first else { throw ProjectMemoryError.invalidVector("embedding runtime returned a mismatched batch count.") } // Validates actual batch cardinality.
                guard !queryVector.isEmpty, queryVector.allSatisfy(\.isFinite) else { throw ProjectMemoryError.invalidVector("embedding runtime returned an empty or non-finite query vector.") } // Rejects unusable physical output before index comparison.
                var candidates = try await vectorStore.search(projectID: projectID, queryEmbedding: queryVector, modelID: embeddingRuntime.modelID, topK: options.candidateLimit) // Retrieves a broader cosine-ranked candidate set.
                guard !candidates.isEmpty else { return try await lexicalResult(query: normalizedQuery, projectID: projectID, limit: options.resultLimit, mode: .fallbackLexical, reason: "No compatible stored vectors were available; deterministic lexical fallback used.", startedAt: startedAt) } // Prevents an empty vector sidecar from hiding useful lexical memory.
                var mode: MemoryRetrievalMode = .embedding // Records vector-only ranking unless actual reranking succeeds.
                var fallbackReason: String? // Stores optional reranker fallback evidence.
                if options.usesHybridRanking { // Combines lexical evidence only for the new integrated Project Chat path.
                    let lexicalCandidates = try await lexicalCandidates(query: normalizedQuery, projectID: projectID, limit: options.candidateLimit) // Retrieves transparent term-overlap candidates from the same isolated project.
                    if !lexicalCandidates.isEmpty { candidates = Self.hybrid(vector: candidates, lexical: lexicalCandidates, limit: options.candidateLimit); mode = .hybrid } // Applies deterministic normalized rank fusion when both evidence sources exist.
                } // Ends optional hybrid fusion.
                if let rerankerRuntime, case .available = rerankerRuntime.availability { // Attempts reranking only when it explicitly claims availability.
                    do { let reranked = try await rerankerRuntime.rerank(query: normalizedQuery, candidates: candidates); candidates = try Self.validatedRerankerOutput(reranked, candidates: candidates); mode = .embeddingAndReranker } // Applies only a finite, duplicate-free subset of actual candidates.
                    catch { fallbackReason = "Reranker failed; embedding order was retained: \(Self.bounded(error.localizedDescription))" } // Preserves useful cosine results after optional reranker failure.
                } else { // Records why the optional reranker stage did not execute.
                    fallbackReason = rerankerRuntime.map { Self.unavailableReason($0.availability) } ?? "No reranker runtime is configured; current ranking was retained." // Distinguishes absent configuration from an audited unavailable model.
                } // Ends optional reranker execution.
                let candidateCount = candidates.count // Captures actual ranked candidates before applying the final limit.
                let matches = Array(candidates.prefix(options.resultLimit)) // Applies the final bounded retrieval result limit.
                return result(projectID: projectID, query: normalizedQuery, mode: mode, matches: matches, fallbackReason: fallbackReason, durationMilliseconds: Self.elapsedMilliseconds(since: startedAt), candidateCount: candidateCount) // Returns actual vector results and measured metadata.
            } catch { // Falls back deterministically when optional embeddings cannot produce usable vector retrieval.
                if error is CancellationError { throw error } // Preserves explicit user cancellation instead of converting it into fallback work.
                return try await lexicalResult(query: normalizedQuery, projectID: projectID, limit: options.resultLimit, mode: .fallbackLexical, reason: "Embedding retrieval unavailable; lexical fallback used: \(Self.bounded(error.localizedDescription))", startedAt: startedAt) // Keeps local memory useful without claiming vector inference.
            } // Ends embedding retrieval recovery.
        } // Ends available embedding path.
        let reason = embeddingRuntime.map { Self.unavailableReason($0.availability) } ?? "No embedding runtime is configured." // Captures actual optional-runtime state.
        return try await lexicalResult(query: normalizedQuery, projectID: projectID, limit: options.resultLimit, mode: .lexical, reason: "\(reason) Deterministic lexical retrieval used.", startedAt: startedAt) // Uses honest term overlap until a real embedding runtime exists.
    } // Ends project retrieval orchestration.

    private func lexicalResult(query: String, projectID: UUID, limit: Int, mode: MemoryRetrievalMode, reason: String, startedAt: UInt64) async throws -> MemoryRetrievalResult { // Produces deterministic project-isolated lexical ranking with measured metadata.
        let candidates = try await lexicalCandidates(query: query, projectID: projectID, limit: limit) // Ranks only selected-project chunks through the shared pure search.
        return result(projectID: projectID, query: query, mode: mode, matches: candidates, fallbackReason: reason, durationMilliseconds: Self.elapsedMilliseconds(since: startedAt), candidateCount: candidates.count) // Returns bounded lexical context and explicit fallback evidence.
    } // Ends lexical result construction.

    private func lexicalCandidates(query: String, projectID: UUID, limit: Int) async throws -> [MemorySearchResult] { // Produces deterministic project-isolated lexical candidates.
        try Task.checkCancellation() // Stops before loading project source memory.
        let chunks = try await memoryStore.chunks(projectID: projectID) // Loads only the requested project's chunks.
        let documents = try await memoryStore.documents(projectID: projectID) // Loads only the requested project's source metadata.
        return ProjectMemoryLexicalSearch.rank(query: query, chunks: chunks, documents: documents, limit: limit) // Reuses the transparent deterministic ranking implementation.
    } // Ends lexical candidate retrieval.

    private func result(projectID: UUID, query: String, mode: MemoryRetrievalMode, matches: [MemorySearchResult], fallbackReason: String?, durationMilliseconds: Int, candidateCount: Int) -> MemoryRetrievalResult { // Builds citations only from actual ranked source metadata.
        let citations = matches.map { match in LocalMemoryCitation(id: match.chunk.id, documentID: match.document.id, documentTitle: match.document.title, sourceFilename: match.document.sourceURL?.lastPathComponent, sourceURL: match.document.sourceURL, chunkIndex: match.chunk.index, score: match.score, excerpt: match.chunk.text) } // Creates no fake pages, dates, authors, or locations.
        return MemoryRetrievalResult(projectID: projectID, query: query, mode: mode, matches: matches, citations: citations, fallbackReason: fallbackReason, durationMilliseconds: durationMilliseconds, candidateCount: candidateCount) // Returns complete trace-ready retrieval output.
    } // Ends retrieval-result construction.

    private static func hybrid(vector: [MemorySearchResult], lexical: [MemorySearchResult], limit: Int) -> [MemorySearchResult] { // Combines two real rankings with deterministic reciprocal-rank fusion.
        var records: [UUID: (MemorySearchResult, Float)] = [:] // Accumulates one actual chunk and its normalized fused evidence.
        for (index, result) in vector.enumerated() { records[result.chunk.id] = (result, 0.65 / Float(index + 1)) } // Gives vector evidence the larger bounded weight while avoiding incomparable raw-score scales.
        for (index, result) in lexical.enumerated() { let prior = records[result.chunk.id]; records[result.chunk.id] = (prior?.0 ?? result, (prior?.1 ?? 0) + 0.35 / Float(index + 1)) } // Adds lexical rank evidence for the same exact chunk identity.
        return records.values.map { MemorySearchResult(chunk: $0.0.chunk, document: $0.0.document, score: $0.1) }.sorted { lhs, rhs in if lhs.score != rhs.score { return lhs.score > rhs.score }; if lhs.document.id != rhs.document.id { return lhs.document.id.uuidString < rhs.document.id.uuidString }; return lhs.chunk.index < rhs.chunk.index }.prefix(limit).map { $0 } // Returns stable fused candidates with meaningful relative scores.
    } // Ends hybrid rank fusion.

    private static func validatedRerankerOutput(_ reranked: [MemorySearchResult], candidates: [MemorySearchResult]) throws -> [MemorySearchResult] { // Prevents a runtime from introducing synthetic or cross-project candidate records.
        let candidateIDs = Set(candidates.map(\.chunk.id)) // Captures the only chunk identities supplied to the physical reranker.
        let outputIDs = reranked.map(\.chunk.id) // Captures returned ordering and duplicate evidence.
        guard !reranked.isEmpty || candidates.isEmpty else { throw ProjectMemoryError.invalidVector("reranker returned no candidates.") } // Treats an empty unexpected ranking as a recoverable reranker failure.
        guard Set(outputIDs).count == outputIDs.count, outputIDs.allSatisfy(candidateIDs.contains), reranked.allSatisfy({ $0.score.isFinite }) else { throw ProjectMemoryError.invalidVector("reranker returned duplicate, unknown, or non-finite candidates.") } // Requires a finite duplicate-free subset of actual inputs.
        return reranked // Returns the validated physical order and scores.
    } // Ends reranker output validation.

    private static func unavailableReason(_ availability: OptionalRetrievalRuntimeAvailability) -> String { // Converts runtime audit state into concise fallback metadata.
        switch availability { // Selects the concrete availability explanation.
        case .available: return "Runtime reported available but did not execute." // Handles a defensive impossible call path.
        case let .unavailable(reason): return reason // Preserves actual audit evidence.
        } // Ends availability explanation selection.
    } // Ends unavailable-reason formatting.

    private static func bounded(_ value: String) -> String { // Produces concise trace-safe runtime failure details.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds output.
    } // Ends retrieval detail bounding.

    private static func elapsedMilliseconds(since start: UInt64) -> Int { // Converts monotonic retrieval timing into trace-friendly whole milliseconds.
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Returns non-negative elapsed wall-clock work.
    } // Ends retrieval timing conversion.
} // Ends Project Memory retrieval service.

enum ProjectMemoryUseDecision: Equatable, Sendable { // Records deterministic project-context routing independently from LLM intent routing.
    case disabledByUser // Honors an explicit manual OFF control.
    case noProject // Reports that no project can supply isolated memory.
    case enabledByUser // Honors an explicit manual ON control.
    case recommended // Enables project context for clear prior-decision or project-reference language.
    case notNeeded // Skips retrieval for self-contained requests.
} // Ends Project Memory use decisions.

struct ProjectMemoryRouter: Sendable { // Applies simple auditable heuristics plus explicit user control.
    func decide(text: String, projectID: UUID?, manualPreference: Bool?) -> ProjectMemoryUseDecision { // Decides whether RetrievalService should run before a specialist.
        guard projectID != nil else { return .noProject } // Prevents cross-project or global memory lookup.
        if manualPreference == false { return .disabledByUser } // Gives explicit OFF control highest priority.
        if manualPreference == true { return .enabledByUser } // Gives explicit ON control deterministic priority over heuristics.
        let normalized = text.lowercased() // Normalizes visible request text for simple phrase matching.
        let signals = ["we decided", "our project", "in this project", "last week", "previous decision", "project memory", "the backend decision", "earlier discussion"] // Defines bounded recall-oriented phrases rather than an opaque LLM router.
        return signals.contains(where: normalized.contains) ? .recommended : .notNeeded // Enables retrieval only for an explicit deterministic recall signal.
    } // Ends project-context routing.
} // Ends deterministic Project Memory routing.
