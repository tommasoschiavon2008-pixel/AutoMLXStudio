import Foundation // Supplies isolated temporary persistence and source-file fixtures.
import XCTest // Supplies asynchronous Project Memory and retrieval assertions.
@testable import AutoMLXStudio // Exposes internal V0.4 foundation types to the permanent suite.

final class ProjectMemoryChunkingTests: XCTestCase { // Verifies deterministic boundaries, overlap, and typed workflow-stage categories.
    func testChunkingIsStableOrderedAndOverlapped() { // Exercises character-window behavior without a tokenizer or model dependency.
        let documentID = UUID() // Creates one stable source identity shared by both runs.
        let projectID = UUID() // Creates one stable project identity shared by both runs.
        let text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau." // Supplies prose long enough to require several bounded windows.
        let chunker = MemoryChunker(maximumCharacters: 40, overlapCharacters: 10) // Uses small explicit limits for deterministic assertions.
        let first = chunker.chunks(documentID: documentID, projectID: projectID, text: text) // Produces the first boundary sequence.
        let second = chunker.chunks(documentID: documentID, projectID: projectID, text: text) // Repeats the exact same chunking operation.
        XCTAssertGreaterThan(first.count, 1) // Confirms the configured width produced multiple windows.
        XCTAssertEqual(first.map(\.text), second.map(\.text)) // Confirms content boundaries remain deterministic despite generated identities.
        XCTAssertEqual(first.map(\.characterStart), second.map(\.characterStart)) // Confirms source start offsets remain deterministic.
        XCTAssertEqual(first.map(\.index), Array(first.indices)) // Confirms stable zero-based source ordering.
        XCTAssertLessThan(first[1].characterStart, first[0].characterEnd) // Confirms adjacent chunks carry actual overlapping source context.
        XCTAssertTrue(first.allSatisfy { $0.projectID == projectID && $0.documentID == documentID && !$0.text.isEmpty }) // Confirms ownership and non-empty content are preserved.
    } // Ends deterministic overlap test.

    func testWorkflowStagesExposeTypedCategories() { // Verifies the V0.4 visualizer foundation categorizes every persisted stage.
        XCTAssertEqual(WorkflowStage.fastRouter.kind, .routing) // Confirms the deterministic router is not represented as an agent.
        XCTAssertEqual(WorkflowStage.specialist.kind, .agent) // Confirms specialist inference is represented as an agent stage.
        XCTAssertEqual(WorkflowStage.speechToText.kind, .service) // Confirms ASR remains a service rather than a fake agent.
        XCTAssertEqual(WorkflowStage.modelResource.kind, .modelResource) // Confirms residency work has a dedicated category.
        XCTAssertEqual(WorkflowStage.attachmentValidation.kind, .validation) // Confirms media validation is explicit.
        XCTAssertEqual(WorkflowStage.audioPlayback.kind, .output) // Confirms local audible delivery is an output stage.
    } // Ends typed stage-kind test.
} // Ends chunking and trace-schema tests.

final class ProjectMemoryPersistenceTests: XCTestCase { // Verifies atomic durable storage, ingestion, and strict project isolation.
    func testProjectsPersistDocumentsAndRemainIsolated() async throws { // Creates two projects and reloads them through a fresh store instance.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectMemory-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned persistence root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the isolated test root.
        let store = ProjectMemoryStore(rootURL: root) // Creates the first durable store instance.
        let alpha = try await store.createProject(name: "Alpha") // Persists the first isolated project.
        let beta = try await store.createProject(name: "Beta") // Persists the second isolated project.
        _ = try await store.addDocument(projectID: alpha.id, title: "Backend decision", sourceURL: URL(fileURLWithPath: "/tmp/backend.md"), text: "We decided to keep the backend offline and local.") // Adds a source only to Alpha.
        _ = try await store.addDocument(projectID: beta.id, title: "Design decision", sourceURL: nil, text: "The interface uses a restrained native macOS design.") // Adds a distinct source only to Beta.
        let reloaded = ProjectMemoryStore(rootURL: root) // Creates a fresh actor to prove disk-backed restoration.
        let projects = try await reloaded.projects() // Reads both persisted project snapshots.
        let alphaDocuments = try await reloaded.documents(projectID: alpha.id) // Reads only Alpha source memory.
        let betaDocuments = try await reloaded.documents(projectID: beta.id) // Reads only Beta source memory.
        let alphaChunks = try await reloaded.chunks(projectID: alpha.id) // Reads actor-isolated Alpha chunks before synchronous XCTest autoclosures.
        XCTAssertEqual(Set(projects.map(\.name)), Set(["Alpha", "Beta"])) // Confirms both project entities persisted.
        XCTAssertEqual(alphaDocuments.map(\.title), ["Backend decision"]) // Confirms Alpha cannot see Beta documents.
        XCTAssertEqual(betaDocuments.map(\.title), ["Design decision"]) // Confirms Beta cannot see Alpha documents.
        XCTAssertTrue(alphaChunks.allSatisfy { $0.projectID == alpha.id }) // Confirms every Alpha chunk retains exact project ownership.
    } // Ends persistence and isolation test.

    func testFileIngestionAcceptsSourceAndRejectsUnsupportedBinaryType() async throws { // Exercises the validate, extract, normalize, chunk, and store pipeline.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectIngestion-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the isolated fixture root.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the fixture directory before writing test files.
        let swiftURL = root.appendingPathComponent("Example.swift") // Resolves a supported source-code fixture.
        let pdfURL = root.appendingPathComponent("Unsupported.pdf") // Resolves an explicitly unsupported no-OCR fixture.
        try Data("struct Example {\r\n    let value = 5\r\n}\r\n".utf8).write(to: swiftURL) // Writes valid UTF-8 Swift with CRLF endings.
        try Data("not a real PDF".utf8).write(to: pdfURL) // Writes a bounded unsupported-extension fixture.
        let store = ProjectMemoryStore(rootURL: root.appendingPathComponent("store", isDirectory: true)) // Keeps persistence separate from imported fixtures.
        let project = try await store.createProject(name: "Sources") // Creates the ingestion destination.
        let document = try await store.ingestFile(projectID: project.id, url: swiftURL) // Runs the complete production ingestion pipeline.
        XCTAssertEqual(document.title, "Example") // Confirms the visible title derives from the actual filename.
        XCTAssertFalse(document.text.contains("\r")) // Confirms line endings were normalized deterministically.
        XCTAssertEqual(document.sourceURL, swiftURL.standardizedFileURL) // Confirms citation metadata retains the actual local source.
        do { // Attempts explicitly unsupported PDF ingestion.
            _ = try await store.ingestFile(projectID: project.id, url: pdfURL) // Runs the same validation entrypoint.
            XCTFail("PDF ingestion should remain unsupported until reliable extraction is implemented.") // Fails if extension validation becomes permissive accidentally.
        } catch let error as ProjectMemoryError { // Captures the expected typed ingestion rejection.
            guard case .unsupportedFileType = error else { return XCTFail("Expected unsupported file type, received \(error).") } // Confirms the failure is explicit rather than a decode accident.
        } // Ends unsupported ingestion assertion.
    } // Ends local file ingestion test.
} // Ends Project Memory persistence and ingestion tests.

final class ProjectMemoryRetrievalTests: XCTestCase { // Verifies cosine math, vector ranking, reranker fallback, lexical fallback, and real citations.
    func testCosineSimilarityRanksExpectedDirectionAndRejectsDimensions() throws { // Exercises pure vector math without persistence or a model runtime.
        XCTAssertEqual(try VectorSimilarity.cosine([1, 0], [1, 0]), 1, accuracy: 0.0001) // Confirms identical unit vectors have maximum similarity.
        XCTAssertEqual(try VectorSimilarity.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001) // Confirms orthogonal unit vectors have zero similarity.
        XCTAssertThrowsError(try VectorSimilarity.cosine([1], [1, 0])) // Confirms dimension mismatch is rejected rather than truncated.
    } // Ends cosine similarity test.

    func testEmbeddingSearchFallsBackOnlyAtRerankerAndReturnsActualCitation() async throws { // Uses a fake real-vector boundary to exercise the production storage and orchestration path.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VectorRetrieval-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned store root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this isolated root.
        let store = ProjectMemoryStore(rootURL: root) // Creates the durable source and vector store.
        let project = try await store.createProject(name: "Retrieval") // Creates one isolated retrieval project.
        _ = try await store.addDocument(projectID: project.id, title: "Backend", sourceURL: URL(fileURLWithPath: "/tmp/backend.md"), text: "The backend remains offline.", chunker: MemoryChunker(maximumCharacters: 1_000, overlapCharacters: 0)) // Creates one backend chunk.
        _ = try await store.addDocument(projectID: project.id, title: "Colors", sourceURL: nil, text: "The accent color is blue.", chunker: MemoryChunker(maximumCharacters: 1_000, overlapCharacters: 0)) // Creates one unrelated chunk.
        let chunks = try await store.chunks(projectID: project.id) // Reads the two actual durable chunk identities.
        let records = [MemoryVectorRecord(projectID: project.id, chunkID: chunks[0].id, vector: [1, 0], modelID: "fake-embedding"), MemoryVectorRecord(projectID: project.id, chunkID: chunks[1].id, vector: [0, 1], modelID: "fake-embedding")] // Assigns deterministic orthogonal actual test vectors.
        try await ProjectVectorStore(memoryStore: store).replace(projectID: project.id, records: records) // Persists the validated JSON vector sidecar.
        let service = ProjectMemoryRetrievalService(memoryStore: store, embeddingRuntime: TestEmbeddingRuntime(), rerankerRuntime: nil) // Connects an available embedding boundary with no reranker.
        let result = try await service.retrieve(query: "What backend did we choose?", projectID: project.id, topK: 1) // Runs vector retrieval and optional-stage fallback.
        XCTAssertEqual(result.mode, .embedding) // Confirms actual cosine ranking executed.
        XCTAssertEqual(result.matches.first?.document.title, "Backend") // Confirms the vector-nearest document won.
        XCTAssertEqual(result.citations.first?.sourceFilename, "backend.md") // Confirms citation metadata comes from the real source URL.
        XCTAssertTrue(result.fallbackReason?.contains("No reranker") == true) // Confirms the optional reranker fallback is visible.
    } // Ends vector retrieval and reranker fallback test.

    func testUnavailableEmbeddingUsesLexicalFallbackWithoutCrossingProjects() async throws { // Proves foundation retrieval remains useful and honest before optional model installation.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexicalRetrieval-\(UUID().uuidString)", isDirectory: true) // Allocates one exact test-owned root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this isolated root.
        let store = ProjectMemoryStore(rootURL: root) // Creates the durable source store.
        let selected = try await store.createProject(name: "Selected") // Creates the queried project.
        let other = try await store.createProject(name: "Other") // Creates a project that must never leak results.
        _ = try await store.addDocument(projectID: selected.id, title: "Local backend", sourceURL: nil, text: "We decided the backend remains local and offline.") // Adds a lexically relevant selected-project document.
        _ = try await store.addDocument(projectID: other.id, title: "Remote backend", sourceURL: nil, text: "We decided the backend should use a remote cloud service.") // Adds a stronger-looking but isolated document.
        let unavailable = EmbeddingRuntimeAdapter(model: nil) // Creates the honest absent-model foundation adapter.
        let service = ProjectMemoryRetrievalService(memoryStore: store, embeddingRuntime: unavailable) // Connects the unavailable optional runtime.
        let result = try await service.retrieve(query: "What backend did we decide?", projectID: selected.id, topK: 3) // Runs deterministic lexical fallback.
        XCTAssertEqual(result.mode, .lexical) // Confirms no synthetic embeddings were claimed.
        XCTAssertEqual(result.matches.map(\.document.title), ["Local backend"]) // Confirms only the selected project contributes context.
        XCTAssertTrue(result.fallbackReason?.contains("not installed") == true) // Confirms actual optional-model status is traceable.
        XCTAssertEqual(ProjectMemoryRouter().decide(text: "What did we decide about the backend last week?", projectID: selected.id, manualPreference: nil), .recommended) // Confirms recall-oriented context routing is deterministic.
        XCTAssertEqual(ProjectMemoryRouter().decide(text: "Write a Swift for-loop", projectID: selected.id, manualPreference: nil), .notNeeded) // Confirms self-contained coding avoids unnecessary retrieval.
        XCTAssertEqual(ProjectMemoryRouter().decide(text: "Use memory", projectID: selected.id, manualPreference: false), .disabledByUser) // Confirms manual OFF overrides heuristics.
    } // Ends lexical fallback and isolation test.
} // Ends Project Memory retrieval tests.

private struct TestEmbeddingRuntime: EmbeddingRuntimeServing { // Supplies one deterministic actual-vector test boundary without MLX hardware.
    let modelID = "fake-embedding" // Matches the vector sidecar's explicit producing model identity.
    let availability = OptionalRetrievalRuntimeAvailability.available // Declares the test boundary executable.
    func embed(_ texts: [String]) async throws -> [[Float]] { texts.map { _ in [1, 0] } } // Returns one deterministic vector per requested text.
} // Ends fake embedding runtime.
