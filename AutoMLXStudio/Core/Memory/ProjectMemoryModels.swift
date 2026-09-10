import CryptoKit // Supplies deterministic SHA-256 fingerprints for duplicate detection and incremental indexing.
import Foundation // Supplies durable identifiers, dates, URLs, Codable persistence, and Sendable value types.

enum ProjectMemorySchema { // Centralizes the durable snapshot format version used by migrations and validation.
    static let currentVersion = 2 // Identifies the integrated Project Memory schema with fingerprints and source metadata.
} // Ends Project Memory schema metadata.

enum MemoryFingerprint { // Provides one stable content identity implementation shared by ingestion, storage, and vector validation.
    static func sha256(_ normalizedText: String) -> String { // Hashes normalized UTF-8 contents without depending on a filename or source path.
        SHA256.hash(data: Data(normalizedText.utf8)).map { String(format: "%02x", $0) }.joined() // Produces a lowercase fixed-width hexadecimal digest.
    } // Ends deterministic content hashing.
} // Ends Project Memory fingerprint support.

struct Project: Identifiable, Codable, Equatable, Sendable { // Represents one lightweight local workspace independently from conversations and model state.
    let id: UUID // Stores the durable project identity used for strict memory isolation.
    var name: String // Stores the editable user-facing project name.
    let createdAt: Date // Records when the local project was created.
    var updatedAt: Date // Records the most recent project metadata or memory mutation.

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date? = nil) { // Creates a complete project with stable timestamps.
        self.id = id // Stores the supplied or generated project identity.
        self.name = name // Stores the normalized project name supplied by the store.
        self.createdAt = createdAt // Stores the durable creation time.
        self.updatedAt = updatedAt ?? createdAt // Uses creation time until the first mutation.
    } // Ends project construction.
} // Ends the lightweight Project entity.

struct MemoryDocument: Identifiable, Codable, Equatable, Sendable { // Stores durable project-specific source text separately from chat history.
    let id: UUID // Stores the durable document identity.
    var title: String // Stores the visible title derived from an import or explicit input.
    var sourceURL: URL? // Stores a known local source reference without claiming that the file remains available forever.
    var text: String // Stores normalized extracted text for deterministic rechunking and debugging.
    let createdAt: Date // Records when the document entered Project Memory.
    var updatedAt: Date // Records the latest content update.
    let projectID: UUID // Enforces project ownership in persistence and retrieval.
    var contentFingerprint: String // Stores a normalized-content SHA-256 digest for duplicate and incremental-index decisions.
    var sourceByteCount: UInt64? // Stores actual source size when a readable local file supplied it.
    var sourceModificationDate: Date? // Stores actual source modification time when the filesystem supplied it.
    var sourceFileExtension: String? // Stores the validated lowercase source extension when known.

    init(id: UUID = UUID(), title: String, sourceURL: URL?, text: String, createdAt: Date = Date(), updatedAt: Date? = nil, projectID: UUID, contentFingerprint: String? = nil, sourceByteCount: UInt64? = nil, sourceModificationDate: Date? = nil, sourceFileExtension: String? = nil) { // Creates one complete memory document while retaining source compatibility with V0.4 callers.
        self.id = id // Stores the supplied or generated document identity.
        self.title = title // Stores the normalized visible title.
        self.sourceURL = sourceURL // Stores actual source metadata only when known.
        self.text = text // Stores normalized source text.
        self.createdAt = createdAt // Stores the durable creation time.
        self.updatedAt = updatedAt ?? createdAt // Uses creation time until the document changes.
        self.projectID = projectID // Stores the owning project identity.
        self.contentFingerprint = contentFingerprint ?? MemoryFingerprint.sha256(text) // Derives a stable digest when an older caller does not supply one.
        self.sourceByteCount = sourceByteCount // Stores measured source size without inventing one for direct text.
        self.sourceModificationDate = sourceModificationDate // Stores measured source time without inventing one for direct text.
        self.sourceFileExtension = sourceFileExtension // Stores the validated source type when available.
    } // Ends memory-document construction.

    private enum CodingKeys: String, CodingKey { // Defines stable snapshot keys and optional V0.4 migration fields.
        case id // Persists the durable document identity.
        case title // Persists the visible title.
        case sourceURL // Persists the actual source reference when known.
        case text // Persists normalized retrievable text.
        case createdAt // Persists the original ingestion time.
        case updatedAt // Persists the latest mutation time.
        case projectID // Persists strict project ownership.
        case contentFingerprint // Persists the integrated content digest.
        case sourceByteCount // Persists measured source size.
        case sourceModificationDate // Persists measured source modification time.
        case sourceFileExtension // Persists the validated source type.
    } // Ends MemoryDocument coding keys.

    init(from decoder: Decoder) throws { // Migrates V0.4 Foundation documents that predate fingerprints and source-change metadata.
        let container = try decoder.container(keyedBy: CodingKeys.self) // Opens the keyed document payload.
        id = try container.decode(UUID.self, forKey: .id) // Restores stable document identity.
        title = try container.decode(String.self, forKey: .title) // Restores visible title.
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL) // Restores a real source reference only when persisted.
        text = try container.decode(String.self, forKey: .text) // Restores normalized document text.
        createdAt = try container.decode(Date.self, forKey: .createdAt) // Restores the original ingestion timestamp.
        updatedAt = try container.decode(Date.self, forKey: .updatedAt) // Restores the latest mutation timestamp.
        projectID = try container.decode(UUID.self, forKey: .projectID) // Restores strict ownership.
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint) ?? MemoryFingerprint.sha256(text) // Migrates old snapshots with a deterministic digest.
        sourceByteCount = try container.decodeIfPresent(UInt64.self, forKey: .sourceByteCount) // Restores optional measured size.
        sourceModificationDate = try container.decodeIfPresent(Date.self, forKey: .sourceModificationDate) // Restores optional measured time.
        sourceFileExtension = try container.decodeIfPresent(String.self, forKey: .sourceFileExtension) // Restores optional validated type.
    } // Ends backward-compatible document decoding.
} // Ends durable memory-document metadata.

struct MemoryChunk: Identifiable, Codable, Equatable, Sendable { // Stores one deterministic text window with enough metadata for citations and vectors.
    let id: UUID // Stores the durable chunk identity referenced by vector records.
    let documentID: UUID // Links the chunk to its exact source document.
    let projectID: UUID // Duplicates project ownership deliberately for fast isolation checks.
    let text: String // Stores the non-empty normalized chunk text.
    let index: Int // Stores stable source order beginning at zero.
    let characterStart: Int // Stores the inclusive normalized-document character offset.
    let characterEnd: Int // Stores the exclusive normalized-document character offset.

    init(id: UUID = UUID(), documentID: UUID, projectID: UUID, text: String, index: Int, characterStart: Int, characterEnd: Int) { // Creates one complete chunk window.
        self.id = id // Stores the supplied or generated chunk identity.
        self.documentID = documentID // Stores exact source-document ownership.
        self.projectID = projectID // Stores exact project ownership.
        self.text = text // Stores normalized chunk contents.
        self.index = index // Stores deterministic source order.
        self.characterStart = characterStart // Stores the inclusive source offset.
        self.characterEnd = characterEnd // Stores the exclusive source offset.
    } // Ends deterministic chunk construction.

    var contentFingerprint: String { MemoryFingerprint.sha256(text) } // Provides stable chunk identity for incremental vector compatibility checks.
} // Ends deterministic memory-chunk metadata.

struct MemoryVectorRecord: Codable, Equatable, Sendable { // Stores one debuggable local embedding sidecar record.
    let projectID: UUID // Enforces project isolation before similarity work.
    let chunkID: UUID // Links the vector to one persisted chunk.
    let vector: [Float] // Stores actual embedding values only when a runtime produced them.
    let dimensions: Int // Stores and validates the expected vector width explicitly.
    let modelID: String // Records the exact embedding model identity used to create the vector.
    let chunkFingerprint: String? // Associates new vectors with exact chunk contents while decoding legacy records safely.
    let modelRevision: String? // Records a real model path or revision only when the runtime provides one.

    init(projectID: UUID, chunkID: UUID, vector: [Float], modelID: String, chunkFingerprint: String? = nil, modelRevision: String? = nil) { // Creates a vector record whose dimension comes only from actual data.
        self.projectID = projectID // Stores owning project identity.
        self.chunkID = chunkID // Stores referenced chunk identity.
        self.vector = vector // Stores actual vector values.
        self.dimensions = vector.count // Derives dimension instead of accepting contradictory metadata.
        self.modelID = modelID // Stores actual producing model identity.
        self.chunkFingerprint = chunkFingerprint // Stores exact source compatibility when known.
        self.modelRevision = modelRevision // Stores actual runtime revision metadata when known.
    } // Ends vector-record construction.
} // Ends local vector sidecar metadata.

struct MemorySearchResult: Equatable, Sendable { // Returns one ranked chunk with its actual document metadata.
    let chunk: MemoryChunk // Stores the matched text window.
    let document: MemoryDocument // Stores the exact source document used for citation.
    let score: Float // Stores cosine, lexical, hybrid, or reranker score supplied by the selected retrieval mode.
} // Ends ranked memory-search output.

struct LocalMemoryCitation: Identifiable, Codable, Equatable, Sendable { // Exposes only known local source and chunk metadata to final-response UI or traces.
    let id: UUID // Reuses the chunk identity for stable expandable source rows.
    let documentID: UUID // Identifies the durable source document.
    let documentTitle: String // Shows the actual persisted document title.
    let sourceFilename: String? // Shows the actual filename when a source URL exists without inventing pages.
    let sourceURL: URL? // Preserves an actual local source reference only when retained.
    let chunkIndex: Int // Identifies the actual zero-based chunk within the document.
    let score: Float // Records the retrieval score associated with this citation.
    let excerpt: String // Stores only the exact injected chunk excerpt shown by the Sources UI.

    init(id: UUID, documentID: UUID, documentTitle: String, sourceFilename: String?, sourceURL: URL? = nil, chunkIndex: Int, score: Float, excerpt: String = "") { // Creates display-safe citation metadata while preserving older call sites.
        self.id = id // Stores the exact cited chunk identity.
        self.documentID = documentID // Stores the exact source document identity.
        self.documentTitle = documentTitle // Stores the actual document title.
        self.sourceFilename = sourceFilename // Stores a real filename only when known.
        self.sourceURL = sourceURL // Stores a real source URL only when known.
        self.chunkIndex = chunkIndex // Stores the actual chunk position.
        self.score = score // Stores the meaningful retrieval score.
        self.excerpt = excerpt // Stores the exact bounded source text supplied to the agent.
    } // Ends citation construction.
} // Ends real local-memory citation metadata.

enum MemoryRetrievalMode: String, Codable, Equatable, Sendable { // Identifies which real retrieval path produced context.
    case lexical // Uses deterministic local term overlap when no embedding runtime exists.
    case embedding // Uses stored vector cosine ranking without a reranker.
    case hybrid // Combines lexical and actual vector evidence deterministically.
    case embeddingAndReranker // Uses vector or hybrid candidates followed by an actual reranker.
    case fallbackLexical // Uses lexical search because an attempted embedding path could not produce usable candidates.

    var displayName: String { // Produces concise strategy labels for trace and debug UI.
        switch self { // Selects a visible retrieval label.
        case .lexical: return "Lexical" // Labels normal zero-model retrieval.
        case .embedding: return "Embedding" // Labels vector-only retrieval.
        case .hybrid: return "Hybrid" // Labels combined lexical and vector ranking.
        case .embeddingAndReranker: return "Embedding + reranker" // Labels actual second-stage ranking.
        case .fallbackLexical: return "Lexical fallback" // Labels recovery after a failed vector path.
        } // Ends retrieval label selection.
    } // Ends retrieval display name.
} // Ends retrieval-mode definitions.

struct MemoryRetrievalResult: Equatable, Sendable { // Returns bounded project candidates plus honest retrieval and fallback metadata.
    let projectID: UUID // Records the exact isolated project searched.
    let query: String // Records the visible bounded user query used for retrieval.
    let mode: MemoryRetrievalMode // Records the actual retrieval algorithm applied.
    let matches: [MemorySearchResult] // Stores ranked chunks with source documents.
    let citations: [LocalMemoryCitation] // Stores display-safe real source metadata for current matches.
    let fallbackReason: String? // Explains why an optional embedding or reranker stage was skipped.
    let durationMilliseconds: Int // Stores measured retrieval orchestration duration.
    let candidateCount: Int // Stores the number of ranked candidates considered before context assembly.

    init(projectID: UUID, query: String, mode: MemoryRetrievalMode, matches: [MemorySearchResult], citations: [LocalMemoryCitation], fallbackReason: String?, durationMilliseconds: Int = 0, candidateCount: Int? = nil) { // Preserves foundation construction while adding measured metadata.
        self.projectID = projectID // Stores the exact searched project.
        self.query = query // Stores the bounded retrieval query.
        self.mode = mode // Stores the strategy that actually produced results.
        self.matches = matches // Stores ranked real chunks.
        self.citations = citations // Stores citations corresponding to current matches.
        self.fallbackReason = fallbackReason // Stores optional recovery evidence.
        self.durationMilliseconds = durationMilliseconds // Stores measured local retrieval time.
        self.candidateCount = candidateCount ?? matches.count // Defaults candidate count to returned matches for older callers.
    } // Ends retrieval-result construction.
} // Ends Project Memory retrieval output.

enum MemoryIndexStatus: String, Codable, Equatable, Sendable { // Describes actual per-project retrieval readiness without claiming unavailable models ran.
    case empty // Indicates the project contains no retrievable chunks.
    case lexicalReady // Indicates local lexical retrieval can execute.
    case embeddingReady // Indicates every current chunk has a compatible persisted vector.
    case stale // Indicates vectors exist but no longer match every current chunk.
    case degraded // Indicates storage or index validation found a recoverable problem.

    var displayName: String { // Produces native UI status copy.
        switch self { // Selects a concise truthful label.
        case .empty: return "No memory" // Labels an empty project.
        case .lexicalReady: return "Lexical ready" // Labels useful zero-model search.
        case .embeddingReady: return "Embedding ready" // Labels a complete physical vector index.
        case .stale: return "Reindex needed" // Labels incompatible or incomplete vectors.
        case .degraded: return "Index degraded" // Labels recoverable validation problems.
        } // Ends index-status label selection.
    } // Ends index-status display name.
} // Ends memory index states.

enum MemorySourceStatus: Equatable, Sendable { // Describes whether a retained external source still resembles the imported file.
    case current // Indicates known size and modification metadata still match.
    case modifiedExternally // Indicates size or modification time changed after ingestion.
    case unavailable // Indicates a retained source cannot currently be read.
    case untracked // Indicates a migrated source exists but no historical filesystem metadata was recorded.
    case internalOnly // Indicates the durable normalized text has no retained external source.
} // Ends external source states.

struct MemoryDocumentStatus: Equatable, Sendable { // Combines durable document identity with computed source and indexing state.
    let documentID: UUID // Identifies the inspected document.
    let sourceStatus: MemorySourceStatus // Reports actual source availability or likely external modification.
    let chunkCount: Int // Reports current retrievable windows for the document.
    let vectorCount: Int // Reports current vector records referencing the document.
} // Ends document status metadata.

struct ProjectMemorySummary: Identifiable, Equatable, Sendable { // Supplies bounded project-list metrics without exposing complete contents.
    var id: UUID { project.id } // Reuses durable project identity for SwiftUI lists.
    let project: Project // Stores actual project metadata.
    let documentCount: Int // Stores the number of durable project documents.
    let chunkCount: Int // Stores the number of retrievable chunks.
    let vectorCount: Int // Stores the number of validated vector records.
    let indexStatus: MemoryIndexStatus // Stores actual lexical, embedding, stale, empty, or degraded state.
} // Ends project summary metadata.

struct ProjectStorageIssue: Identifiable, Equatable, Sendable { // Reports one unreadable app-owned snapshot without blocking healthy projects.
    let id: UUID // Provides stable UI identity independent from a corrupt embedded project ID.
    let filename: String // Identifies only the app-owned snapshot filename.
    let detail: String // Stores a bounded decoding or validation diagnostic.
} // Ends recoverable project-catalog issue metadata.

struct ProjectMemoryCatalog: Equatable, Sendable { // Returns readable project summaries and isolated snapshot problems together.
    let projects: [ProjectMemorySummary] // Stores every validated project in deterministic order.
    let issues: [ProjectStorageIssue] // Stores bounded problems that did not prevent healthy projects from loading.
} // Ends resilient Project Memory catalog output.

enum ProjectMemoryError: LocalizedError, Equatable, Sendable { // Defines bounded validation, persistence, and unavailable-runtime failures.
    case emptyProjectName // Reports a project name containing no visible characters.
    case projectNameTooLong(Int) // Reports a project name exceeding the explicit limit.
    case projectNotFound(UUID) // Reports a missing isolated project snapshot.
    case documentNotFound(UUID) // Reports a missing document inside the selected project.
    case duplicateDocument(UUID, String) // Reports same-content ingestion without duplicate chunks.
    case emptyDocument // Reports extracted or supplied text with no usable contents.
    case unsupportedFileType(String) // Reports an extension outside the explicit ingestion allowlist.
    case fileUnavailable(String) // Reports a missing, unreadable, oversized, or non-regular source.
    case invalidVector(String) // Reports empty, non-finite, inconsistent, stale, or cross-project vector data.
    case embeddingUnavailable(String) // Reports that no real embedding runtime can execute.
    case rerankerUnavailable(String) // Reports that no real reranker runtime can execute.
    case indexCorrupt(String) // Reports a snapshot whose ownership or schema invariants cannot be trusted.
    case unsupportedSchema(Int) // Reports a future snapshot version that cannot be reinterpreted safely.
    case unsafeStorageTarget(String) // Reports a deletion target that failed containment validation.
    case persistenceFailed(String) // Reports bounded local JSON persistence failures.

    var errorDescription: String? { // Produces concise actionable errors for UI, tests, and trace metadata.
        switch self { // Selects the concrete user-facing diagnostic.
        case .emptyProjectName: return "Project name cannot be empty." // Explains invalid project metadata.
        case let .projectNameTooLong(limit): return "Project name must be \(limit) characters or fewer." // Explains the explicit name bound.
        case let .projectNotFound(id): return "Project Memory project was not found: \(id.uuidString)." // Identifies the missing project.
        case let .documentNotFound(id): return "Project Memory document was not found: \(id.uuidString)." // Identifies the missing document.
        case let .duplicateDocument(_, title): return "This content is already indexed as \"\(title)\"." // Explains deterministic duplicate rejection.
        case .emptyDocument: return "The document contains no usable text." // Explains empty ingestion.
        case let .unsupportedFileType(value): return "Unsupported Project Memory file type: \(value)." // Identifies the rejected extension.
        case let .fileUnavailable(detail): return "Project Memory file is unavailable: \(detail)" // Preserves bounded filesystem context.
        case let .invalidVector(detail): return "Invalid embedding vector: \(detail)" // Explains vector validation failure.
        case let .embeddingUnavailable(detail): return "Embedding runtime unavailable: \(detail)" // Distinguishes absent runtime from empty results.
        case let .rerankerUnavailable(detail): return "Reranker runtime unavailable: \(detail)" // Distinguishes fallback from reranking.
        case let .indexCorrupt(detail): return "Project Memory index is degraded: \(detail)" // Explains recoverable corruption.
        case let .unsupportedSchema(version): return "Project Memory schema version \(version) is newer than this application supports." // Refuses future reinterpretation.
        case let .unsafeStorageTarget(detail): return "Project Memory refused an unsafe storage operation: \(detail)" // Explains containment protection.
        case let .persistenceFailed(detail): return "Project Memory persistence failed: \(detail)" // Reports bounded storage failure.
        } // Ends error-description selection.
    } // Ends localized Project Memory error access.
} // Ends Project Memory errors.
