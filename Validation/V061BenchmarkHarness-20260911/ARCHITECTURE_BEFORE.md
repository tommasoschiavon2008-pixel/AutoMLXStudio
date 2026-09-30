# V0.6.1 targeted benchmark architecture audit

Audit scope: the existing Benchmark page and persistence, `AppState`, sidebar navigation, backend-neutral generation values, `ModelBackendDispatcher`, local and remote adapters, cancellation, usage/duration metadata, and the Engineering/Agents integration boundaries. No general project audit was performed.

## Reusable foundations

- `ModelGenerationTarget` already provides collision-safe backend, location/server, and model identity.
- `ModelGenerationRequest`, `ModelGenerationResult`, usage, finish reason, native tool calls, and duration are provider-neutral.
- `ModelBackendDispatcher` already executes a validated route through `LocalMLXBackend` or `RemoteInferenceBackend` with typed failure and cancellation traces.
- `AppState` owns stable local/remote adapters and navigation state.
- SwiftUI sidebar and native table/form patterns already exist.

## Root cause and missing data

The existing `BenchmarkView` calls `AppState.runBenchmark()`, which invokes `MLXService.runBenchmark` directly. Its single legacy `BenchmarkResult` stores only model name, prompt/generation throughput, peak RAM, profile, and date in the general application state file. It has no backend-neutral target, suite/case identity, grader, correctness, failure taxonomy, per-case usage/timing, run lifecycle, versioned benchmark store, comparison, custom suite, or export contract.

Current flow:

```text
BenchmarkView
  -> AppState.runBenchmark
  -> MLXService.runBenchmark
  -> local MLX benchmark process
  -> legacy BenchmarkResult[] in state.json
```

## Required additive correction

Keep the legacy performance entry points source-compatible, but replace the visible Benchmark experience with an additive controller and evaluation engine:

```text
BenchmarkView
  -> BenchmarkController
  -> BenchmarkEvaluationEngine
  -> ModelBackendDispatcher
     -> LocalMLXBackend
     -> RemoteInferenceBackend
```

New versioned benchmark storage must be independent from conversations and credentials. Generation, deterministic grading, aggregation, comparison, reporting, and custom-suite validation must remain separate. Imported suites may describe prompts and declarative graders only; they must never execute arbitrary code or shell commands.
