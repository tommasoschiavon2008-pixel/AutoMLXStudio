# V0.6.1 architecture after implementation

## Implemented flow

```text
BenchmarkView
  → app-owned BenchmarkController
    → BenchmarkEvaluationEngine
      → exact ModelGenerationTarget
      → DispatcherBenchmarkGenerationClient
        → ModelRouter (one candidate, fallback disabled)
          → shared AppState.modelBackendDispatcher
            → LocalMLXBackend or RemoteInferenceBackend
      → isolated BenchmarkGradingStrategy
      → BenchmarkCaseResult checkpoint
      → BenchmarkSummaryCalculator
    → BenchmarkStore (one schema-v1 JSON file per record)
    → BenchmarkReportExporter (JSON + Markdown)
```

## Responsibility boundaries

| Layer | Owns | Does not own |
|---|---|---|
| Domain | Suite, case, configuration, result, summary, comparison values | Model execution or UI state |
| Built-in corpus | 33 stable original cases and safe validation | External datasets or downloads |
| Engine | Selection, sequential execution, deadline, cancellation, checkpoint construction | Persistence, UI, adaptive routing |
| Graders | One deterministic response contract each | Model calls or tool execution |
| Summary | Category/dimension scores and truthful aggregate metrics | Qualitative judge decisions |
| Store | Versioned isolated JSON records and import preview | Built-in mutation or executable import content |
| Controller | Active run, history, custom suites, comparison selection | Backend-specific HTTP/MLX logic |
| View | Native configuration, progress, results, history, compare, suite management | Inference or filesystem tool authority |

## Security boundary

- Tool calls are decoded and graded as data only.
- Imported suites are declarative Codable data, limited to 2 MiB.
- Programmatic graders resolve through a closed identifier registry.
- Benchmark never runs shell, arbitrary code, model downloads, training, or project edits.
- Dispatcher fallback is disabled for every run.
- Stored environment metadata excludes hostname, username, absolute local path, remote endpoint, credentials, prompts from unrelated app features, and hardware serial identity.
- Windows and external hosts were not contacted.

## Compatibility

The legacy `BenchmarkResult`, `AppState.benchmarkResults`, and `AppState.runBenchmark()` remain available for old application state and source compatibility. `RootView` now presents the V0.6.1 `BenchmarkView(controller:)`. Chat and Benchmark share one dispatcher instance; Engineering retains its existing builder and authority model.
