# Project 5 RAG and Project Memory

## V0.4 Foundation scope

Project Memory is durable, local, and separate from chat history. It does not claim that optional embedding or reranker models currently execute.

Implemented entities and services:

- `Project`: durable ID, editable name, creation and update timestamps;
- `MemoryDocument`: project ownership, title, optional real source URL, normalized text, timestamps;
- `MemoryChunk`: project/document ownership, stable order, text, and actual character offsets;
- `ProjectMemoryStore`: actor-isolated, one atomic JSON snapshot per UUID-named project under Application Support;
- `MemoryDocumentIngestor`: bounded UTF-8 extraction for txt, Markdown, Swift, Python, JavaScript/TypeScript, C-family, Java, JSON, YAML, XML, HTML, and CSS;
- `MemoryChunker`: deterministic character approximation with natural boundary preference and configurable overlap;
- `MemoryVectorRecord` and `ProjectVectorStore`: debuggable JSON vectors with project/chunk/model/dimension validation;
- `VectorSimilarity.cosine`: finite, equal-dimension, non-zero vector validation and local ranking;
- `EmbeddingRuntimeAdapter` and `RerankerRuntimeAdapter`: honest unavailable foundations until compatible installed MLX entrypoints are inspected;
- `ProjectMemoryRetrievalService`: embedding → top-N → optional reranker → top-K when real runtimes exist, with deterministic project-isolated lexical fallback otherwise;
- `LocalMemoryCitation`: actual document, source filename when known, chunk index, and retrieval score—never invented page numbers;
- `ProjectMemoryRouter`: deterministic recall heuristics plus explicit ON/OFF preference input.

## Persistence and isolation

Each project is stored as a complete atomic JSON transaction containing its metadata, documents, chunks, and optional vectors. Filenames contain only the lowercased project UUID. Cross-project document, chunk, and vector references are rejected. The store creates no cloud state and never reads outside an explicitly imported file or its app-owned persistence directory.

Ingestion is:

```text
selected regular file → extension/size/UTF-8 validation → line-ending normalization
→ deterministic overlapped chunks → atomic project snapshot
```

The initial file limit is 8 MiB. PDF is explicitly unsupported until reliable text extraction is added; no OCR is performed.

## Retrieval behavior

If a real embedding runtime explicitly reports available, query vectors are compared only with vectors produced by the same model ID. Candidates may then pass through a real reranker. If reranking fails or is unavailable, embedding order is retained and the fallback reason is returned.

If embeddings are unavailable, retrieval uses transparent unique-term overlap and an exact-phrase bonus. The result mode is `lexical`, and the unavailable model reason is retained. This provides useful foundation behavior without synthetic vectors or fake model success.

## Not yet wired to Chat

Projects UI, conversation-to-project assignment, the visible **Use Project Memory** toggle, retrieval panels, and injection into the production WorkflowEngine remain the next integration milestone. The models, persistence, ingestion, search, routing decision, and citations are implemented and covered by permanent tests; the optional Qwen3 Embedding and Reranker physical models are not installed and their runtime calls remain deliberately unavailable.
