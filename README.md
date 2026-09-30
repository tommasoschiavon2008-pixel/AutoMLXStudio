# AutoMLX Studio

V0.6.1 adds a correctness-first Model Evaluation / Benchmark Harness for exact configured local MLX and remote OpenAI-compatible targets. It includes 33 original offline cases across eight categories, deterministic graders, per-case timeouts, cooperative cancellation, truthful performance/usage metrics, weighted scores, versioned history, comparison, best-model-by-role evidence, custom suite import/export, and JSON/Markdown result export. Benchmark tool calls are inert graded data and are never executed.

V0.6.0.1 added ordinary Chat for installed local MLX text models and explicitly configured remote OpenAI-compatible models. Chat and Benchmark now share one backend dispatcher; credentials remain in Keychain and optional token/TTFT metrics remain unavailable when a backend does not report them.

Windows software readiness and the still-pending focused physical revalidation are documented in `PROJECT6_VALIDATION.md`, `PROJECT6_WINDOWS_READINESS.md`, and `PHYSICAL_REVALIDATION.md`.

AutoMLX Studio is a native macOS SwiftUI application for offline MLX model control, chat, multimodal orchestration, optimization, and benchmarking.

The current **V0.6 Distributed Engineering** preserves the V0.1–V0.4 features and adds:

- app-owned Engineering and Remote Models sidebar destinations with persistent session state;
- a single EngineeringSessionBuilder using the existing ModelRouter and ModelBackendDispatcher;
- local MLX or manually configured OpenAI-compatible remote inference, with all tools remaining on the Mac;
- bounded native/strict-JSON multi-turn engineering, explicit edit/build approvals, diffs, and conflict-safe rollback;
- deterministic inspect → edit → test → verify integration tests, including the real local and remote backend adapters;
- cancellation, current-file verification evidence, live operational activity, and isolated opt-in Project Memory.

Previously implemented features remain available:

- deterministic multi-model agents with progressive fallback;
- real MLX VLM and MLX Audio process adapters with offline-only execution;
- screenshot → Vision → Swift/Coding → Reviewer → Composer workflows;
- press-to-record ASR, editable transcripts, opt-in auto-send, opt-in TTS, and controlled playback;
- host-derived resource budgets and exclusive large Text/Vision residency;
- durable project-scoped memory, text/source ingestion, overlapped chunks, JSON vector records, cosine search, reranker fallback metadata, and local citations;
- a six-state installation auditor that validates manifests, shards, processors, locks, and runtime dependencies.

The normal runtime never downloads a model. Missing files or optional runtimes produce explicit unavailable states. A local model path is preferred over repository metadata, and only child processes started and retained by this app may be terminated.

Engineering orchestration, workspace authority, edits, commands, and approvals always run on the Mac. In distributed mode, the server receives prompts, selected context, tool definitions, and bounded tool results, never a filesystem handle. This still transmits selected source content; use a trusted endpoint. Benchmark may evaluate an explicitly selected remote target, but it never executes returned tool intent.

The operational repository is `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3`. The old repository on Crucial X9 Pro is preserved; the external model/runtime paths below have not moved.

See [V0.6.1 Benchmark Harness](PROJECT_V061_BENCHMARKS.md), [Project 6 architecture](PROJECT6_ARCHITECTURE.md), [Engineering usage and safety](PROJECT6_ENGINEERING.md), [Windows readiness checklist](PROJECT6_WINDOWS_READINESS.md), and [validation evidence](PROJECT6_VALIDATION.md). Physical Windows validation is pending; deterministic software tests are not a claim of a tested Windows machine.

## Build and test

```sh
xcodegen generate
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Release -destination 'generic/platform=macOS' build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
```

The separately executable `AutoMLXStudioHardwareValidation` scheme enables real multi-model, Vision, ASR, and TTS tests. Each test still skips safely if its optional model or runtime is unavailable. The TTS test never autoplays audio.

Default paths:

```text
MLX environment: /Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main
Project 5 models: /Volumes/Crucial X9 Pro/app/Models/Project5
Project Memory:   ~/Library/Application Support/AutoMLXStudio/ProjectMemory
```

See [PROJECT5_ARCHITECTURE.md](PROJECT5_ARCHITECTURE.md), [PROJECT5_MODELS.md](PROJECT5_MODELS.md), [PROJECT5_VISION_VOICE.md](PROJECT5_VISION_VOICE.md), and [PROJECT5_RAG_MEMORY.md](PROJECT5_RAG_MEMORY.md) for implemented boundaries and current limitations.
