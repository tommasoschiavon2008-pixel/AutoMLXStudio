# Project 5 Architecture

## V0.2 architecture

Project 5 V0.2 keeps the V0.1 agent workflow and adds deterministic physical-model routing plus serialized runtime management.

```text
User
  -> Fast Router
  -> Director
  -> Model Router
  -> Selected Specialist
  -> Model Resource Manager
  -> Selected Local Model
  -> Reviewer + Reviewer Model
  -> Final Composer + Final Model
  -> User
```

The primary boundaries are:

- `AgentDefinition`: responsibility, prompt, orchestration kind, and required capabilities.
- `ModelProfile`: repository/path, backend, capabilities, installation facts, estimates, and runtime state.
- `ModelAssignment`: preferred model, primary capability, ordered fallback models/capabilities, and runtime-reuse permission for one agent.
- `ModelRegistry`: persisted catalog, assignment, capability preference, installation detection, and V0.1 migration.
- `ModelRouter`: deterministic selection from installed and enabled models.
- `ModelResourceManager`: actor that serializes stop/load operations and owns the one-active-text-model invariant.
- `ModelRuntimeAdapterRegistry`: central backend lookup for MLX LM, MLX VLM, and MLX Audio dependency and installation validation.
- `WorkflowEngine`: preserves the V0.1 entry point and adds a V0.2 entry point using the registry, router, resource manager, and switching policy.
- `MLXCompletionClient`: remains the single agent-facing completion transport.
- `MLXService`: remains the one process/network implementation for server, Chat, Optimize, and Benchmark.
- `AppState`: publishes UI state, persisted configuration, workflow history, test results, and resource snapshots without implementing orchestration.

No model is downloaded automatically and no second permanent text server is created.

## Request lifecycle

Fast Router and Director remain deterministic. The specialist receives at most eight recent messages. Reviewer receives only the original request and specialist candidate. Final Composer receives only the original request and best reviewed candidate.

For every LLM-backed stage, V0.2 performs:

1. resolve the agent's `ModelAssignment`;
2. run `ModelRouter` with the current installation and runtime snapshot;
3. ask `ModelResourceManager` to reuse or load the selected model;
4. execute the inference through `LLMCompleting`;
5. on load or inference failure, exclude that model and repeat deterministic fallback selection;
6. record selection, switching, loading, inference, and total attempt timing.

The V0.1 `execute(userInput:conversationHistory:model:serverPort:)` interface remains available. It retains the original five-step trace shape, which keeps existing tests and integrations source-compatible. Chat uses the V0.2 registry-based entry point.

The existing direct-answer quality policy still skips Reviewer and Final Composer for short, single-line general definition requests. Skipped stages remain visible in the trace.

## Agent, skill, and service distinction

An **Agent** is an LLM-backed role. It defines responsibility, a central system prompt, workflow role, and required capabilities. It does not contain a physical repository path.

A **Skill** is a future reusable capability invoked by an agent, such as code inspection or document retrieval. V0.2 does not add fake skills because those tools do not exist yet.

A **Deterministic Service** performs predictable infrastructure work. Fast Router, Director, Model Router, Model Registry persistence, installation detection, Model Resource Manager, MLX process control, networking, trace storage, settings, logging, hardware detection, quantization, and benchmarking remain deterministic services.

## Agent registry

`AgentRegistry` remains the only location containing system prompts.

| Agent ID | Name | Kind | Required capabilities |
|---|---|---|---|
| `general-agent` | General Agent | Specialist | General |
| `coding-agent` | Coding Agent | Specialist | Coding, Reasoning |
| `swift-agent` | Swift Agent | Specialist | Coding, Reasoning, Swift |
| `research-agent` | Research Agent | Specialist | General, Research |
| `vision-agent` | Vision Agent | Specialist | Vision |
| `reviewer-agent` | Reviewer Agent | Reviewer | Reasoning |
| `final-composer` | Final Composer | Output | General, Reasoning |

Research Agent still has no web-search tool and must not claim searches or fabricate citations.

## Model registry and migration

`ModelRegistry` stores multiple `ModelProfile` values and supports register, update, remove, lookup by ID, lookup by capability, enabled state, installation state, per-capability preference, agent assignments, explicit fallbacks, and the final legacy fallback.

On first V0.2 launch, the persisted V0.1 `modelIdentifier` is inserted or marked as `isLegacyFallback`. Existing repository, output path, port, and automatic free-port settings remain unchanged. The legacy field remains visible in Settings as **Legacy / Fallback Model** and continues to drive Optimize and Benchmark.

Known models are inspected offline under:

```text
/Volumes/Crucial X9 Pro/app/Models/Project5
```

The expected folder is derived from the repository's final component. A catalog model is installed only when structured validation confirms its directory, `config.json`, tokenizer metadata for MLX text/VLM/audio, model weights, valid safetensors headers, and every shard named by every `*.safetensors.index.json`. Explicit `.part`, `.download`, or `.incomplete` markers block launch. A present but incomplete folder is **Downloading / incomplete**, while a missing folder is **Not installed**. Lock files are warnings only because stale locks do not prove an active transfer. Repository resolution without a local folder is allowed only for the explicitly migrated V0.1 fallback.

Runtime state is reset and re-inspected on launch. Persisted configuration never claims that a process survived an application restart.

## Model assignments and fallback behavior

Assignments are persisted independently from `AgentDefinition`.

| Agent | Preferred model |
|---|---|
| General Agent | Qwen3 8B 4-bit |
| Coding Agent | Qwen2.5 Coder 7B 4-bit |
| Swift Agent | Qwen2.5 Coder 7B 4-bit |
| Research Agent | Qwen3 8B 4-bit |
| Vision Agent | Qwen3 VL 8B Instruct 4-bit |
| Reviewer Agent | DeepSeek R1 Qwen3 8B 4-bit |
| Final Composer | Qwen3 8B 4-bit |

`ModelRouter` uses this exact order:

1. allowed active-model reuse according to `ModelSwitchPolicy`;
2. assigned preferred model;
3. declared fallback models in order;
4. user preference for the assignment's primary capability;
5. another enabled installed text model satisfying every required capability;
6. migrated V0.1 legacy fallback;
7. graceful failure when no usable model exists.

Disabled, missing, invalid, excluded-after-failure, wrong-backend, and capability-incompatible models are ignored. Each decision returns a `ModelSelection` containing preferred ID, actual ID, reason, and fallback state.

## Model resource manager and memory strategy

`ModelResourceManager` is an actor and the authoritative owner of backend validation and text-model process transitions. It tracks active model, active port, per-model runtime state, adapter availability, and a hard shutdown safety block.

Before loading, it validates:

- the model is enabled;
- the backend is `mlxLM` for V0.2 Chat;
- the existing `mlx_lm.server` executable is present;
- a non-legacy local model folder passes required-file validation;
- the existing MLX service can use the requested or automatically selected free port.

Only one large Text or Vision model may be resident. `ResourceBudget.current()` derives physical memory and reserves the greater of 4 GiB or 25% for the system; the validation host exposes 12 GiB for models from 16 GiB physical memory. Small Audio, embedding, or reranker work may coexist only when conservative estimates fit. `ResidencyDecision` returns reuse, load, switch-from, or reject explicitly. A change performs an awaited, configurable graceful stop before loading the next model. Only the exact `Process` retained by `MLXService` can receive termination signals. `SIGKILL` is allowed only after the grace deadline and only for that owned PID. Replacement startup is blocked unless process exit is confirmed; a failed inference cleanup that cannot confirm exit also blocks every fallback load. Actor isolation plus an in-flight task prevents competing starts from racing. Concurrent requests for the same target share one physical load. A request for the already active model returns warm-reuse metadata without restarting the server.

V0.2.1 records exact launch reference, verified stop time, cold startup/readiness time, warm reuse time, coordinator overhead, force-termination use, and memory snapshots before stop, after stop, and after load. Process memory uses `proc_pidinfo` only for the PID explicitly supplied by the owning controller; it never enumerates or signals unrelated Python processes.

`MLXService` still owns actual process launch, port ownership checks, automatic next-free-port selection, readiness polling, completion HTTP, dynamic quantization, and benchmark execution. V0.2 adds async lifecycle bridges around that implementation rather than duplicating it.

## Switching policy

Settings exposes three deterministic policies:

- `qualityPreferred`: try the assignment's preferred model even when another compatible model is active;
- `balanced` (default): reuse the active model only when it is the preferred or an explicitly declared fallback for that agent;
- `minimizeSwitches`: reuse any active, installed, enabled text model satisfying all agent capabilities.

The policy never overrides backend, installation, enabled-state, or capability validation.

## Workflow trace V0.2

`WorkflowTrace` retains intent, specialist, actual specialist model, total duration, outcome, and ordered steps. It adds `WorkflowModelExecution` records containing:

- agent ID and name;
- preferred and actual model IDs;
- selection reason;
- fallback used;
- whether the model changed;
- model loading/switching milliseconds;
- inference milliseconds;
- total attempt milliseconds;
- succeeded or failed status;
- bounded operational detail;
- exact local launch reference or repository reference;
- stop, cold-load, warm-reuse, and switching-overhead milliseconds;
- whether the prior owned process required forced termination;
- optional exact-PID memory snapshots before stop and after load, plus a host snapshot after stop.

The ordered UI trace adds repeatable Model Router and Model Resource steps before each model-backed stage. It distinguishes initial load, switch, reuse, failed load, failed inference, and skipped stages. `WorkflowStageKind` groups every concrete stage as routing, validation, model resource, agent, service, or output for visualization. No prompt, hidden reasoning, or chain-of-thought is stored.

## Error recovery

A failed preferred model is excluded for the current agent stage and selection continues through declared, compatible, and legacy fallbacks. A failed active inference model is marked failed and stopped before another model is loaded.

If every specialist model fails, Chat returns actionable Models/Settings guidance. If every Reviewer model fails, the specialist candidate is preserved and Final Composer is still attempted. If every Final Composer model fails, the reviewed or specialist candidate is returned. These preserve the V0.1 progressive recovery contract.

## User interface

The sidebar order is Dashboard, Chat, Agents, Models, Optimize, Benchmark, Settings.

Models displays every registry profile with repository, backend, capabilities, expected or selected local path, six-state audited installation, enabled state, runtime state, loaded badge, disk size, memory estimate, host model budget, and legacy role. It supports Enable/Disable, Select Folder, Set Preferred for Capability, backend-specific Test labels, Refresh Catalog, and Reveal in Finder. Recursive audits run off the SwiftUI interaction path.

Agents displays required capabilities, editable compatible preferred models, explicit and legacy fallbacks, and the model currently resolved by the production policy. Latest Workflow and Chat disclosures use the real executed trace.

## V0.3 Vision and Voice runtime

`UserRequest` carries text plus typed URL-backed attachments. Chat supports native multi-image selection, Finder drag-and-drop, preview, removal, and image-only submission. `AttachmentValidationService` accepts content-validated PNG, JPEG, and HEIC regular files up to 25 MiB, performs a bounded thumbnail decode, and records only privacy-safe type, byte, and dimension metadata in traces.

An image deterministically requires the single Vision Agent. Pure description stays Vision-only; image plus Swift, coding, or research text runs Vision first and hands `VisualAnalysis` to the matching specialist, Reviewer, and Composer. Vision remains on `mlxVLM`; a text legacy model is never used as a visual approximation. The real adapter invokes the inspected `mlx_vlm.generate` entrypoint with offline flags, bounded output, timeout, exact local paths, central residency, and no download fallback.

Voice is a service pipeline, not an agent: microphone permission → press-record mono WAV capture → real MLX Audio ASR → editable composer draft. Permission is requested only after the microphone action. The state machine is `idle → requestingPermission → recording → transcribing → ready`, with a controlled `failed` state. The persisted auto-send preference is OFF by default. Real TTS runs only after text is stored and its persisted preference is also OFF by default, so synthesis or playback failure cannot remove an answer. Capture, ASR, TTS, and playback appear as service stages in the workflow trace.

See `PROJECT5_VISION_VOICE.md` for actual command boundaries, measured Audio hardware results, Vision shard status, and reproducible opt-in tests.

## V0.4 Project Memory foundation

`ProjectMemoryStore` persists one atomic JSON snapshot per UUID-named project, independently from chat history. Documents retain actual optional source URLs, deterministic normalized text, and overlapped character chunks with source offsets. The ingestion allowlist covers bounded UTF-8 text, Markdown, and source code; PDF/OCR remains explicitly unsupported.

`ProjectVectorStore` validates project/chunk references, model ID, dimensions, and finite values before storing vectors in the same debuggable snapshot. Cosine search is implemented and unit-tested. Retrieval is a service, not an agent: actual embeddings → cosine top-N → optional actual reranker → top-K. When optional models are absent, transparent lexical ranking is used and the fallback reason is returned. Citations contain only actual document title, source filename when known, chunk index, and score.

The catalog embedding/reranker profiles and model-agnostic runtime protocols exist, but the optional physical models are absent and no compatible MLX entrypoints have been validated. The concrete foundation adapters therefore throw explicit unavailable errors rather than producing synthetic vectors or scores. Projects UI, Chat project assignment/toggle, context injection, and source disclosure remain the next milestone. See `PROJECT5_RAG_MEMORY.md`.
