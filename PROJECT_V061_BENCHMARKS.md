# AutoMLXStudio V0.6.1 — Model Evaluation / Benchmark Harness

## Scope and status

V0.6.1 adds an offline, backend-neutral evaluation harness to the existing macOS SwiftUI application. It evaluates exact configured local MLX or remote OpenAI-compatible model targets through the existing typed routing and dispatcher layer. It does not select a model automatically, download models, train, fine-tune, distill, or execute benchmark-produced tools.

The previous throughput-only `BenchmarkResult` API remains source-compatible for older persisted application state. The visible Benchmark destination now uses the correctness-first V0.6.1 architecture.

Physical Windows validation was not performed. Its status remains **PARTIAL / PENDING**.

## Architecture

The implementation separates five responsibilities:

1. `BenchmarkSuite` and `BenchmarkCase` describe immutable inputs and declarative grading.
2. `BenchmarkEvaluationEngine` selects cases, runs them sequentially, applies deadlines, and isolates each failure.
3. Individual `BenchmarkGradingStrategy` implementations grade exact, normalized, contains, regex, numeric, JSON, tool-call, and registered programmatic cases.
4. `BenchmarkSummaryCalculator` derives category scores, five weighted dimensions, raw performance statistics, and usage efficiency.
5. `BenchmarkStore` persists each run and custom suite as a separate schema-versioned JSON record. `BenchmarkReportExporter` produces portable result JSON and Markdown.

`DispatcherBenchmarkGenerationClient` creates a single-target route whose fallback policy is disabled, then calls the shared `ModelBackendDispatcher`. The run therefore preserves the exact tuple `(backend ID, execution location/server ID, model ID)` from configuration through result evidence. Benchmark UI code never branches into HTTP or MLX implementation details.

`AppState` owns one `modelBackendDispatcher` shared by ordinary Chat and Benchmark. It also owns one `BenchmarkController`, so a run, progress, filters, result selection, and comparisons survive sidebar navigation.

## Built-in suite

`AutoMLXStudio Core Evaluation`, version 1, contains 33 original deterministic cases:

| Category | Cases |
|---|---:|
| General | 5 |
| Reasoning | 5 |
| Coding | 5 |
| Structured Output | 5 |
| Tool Use | 4 |
| Engineering | 3 |
| Reviewer | 3 |
| Long Context | 3 |

Quick mode selects eight explicitly tagged cases, one per category. Standard mode selects all 33. Category mode selects all cases from one category. Custom mode uses the selected custom suite or explicit case identities. Supported repetition counts are 1, 3, and 5. Execution is sequential by design.

The Long Context cases generate 240-record synthetic inputs locally. They contain no user documents or downloaded datasets. The UI warns that model context capacity may be unknown.

## Deterministic grading

- Exact: literal visible-text equality, tolerating only transport-added boundary newlines.
- Normalized: symmetric optional trim, whitespace collapse, and case folding.
- Contains: explicit all-or-any phrase presence.
- Regex: validated ICU-compatible expression matching.
- Numeric: complete-response finite `Double` parsing and absolute tolerance.
- JSON: strict decoding into typed `JSONValue`, root-type validation, object-only dot paths, and typed exact values.
- Tool calls: exact ordered native `ModelToolCall` values or a strict inert local JSON `tool_calls` envelope.
- Programmatic: a closed registry of safe in-process predicates. Imported identifiers outside that registry are rejected.

Optional LLM judging is a separate injected protocol. It is disabled by default, simulated in tests, stored as `BenchmarkJudgeAssessment`, and never changes deterministic case or aggregate scores.

## Tool and engineering safety

Tool-use cases evaluate only model-returned intent. Remote adapters may receive harmless native schemas; the local MLX adapter receives a strict JSON representation because it does not advertise native tool schemas. The harness parses names and arguments but never calls a tool executor.

Engineering cases operate on textual synthetic fixtures and expected workflow intent. They do not grant shell, arbitrary code, project write, or approval authority. Custom suite imports are limited to 2 MiB and Codable declarative values. They cannot carry closures, executable expressions, filesystem handles, or commands.

## Timeouts, cancellation, and failures

Each repetition races generation against its validated 0–600 second deadline in a structured task group. A timeout, malformed response, wrong answer, tool error, backend error, protocol error, or grading error becomes one classified `BenchmarkCaseResult`; the next case is still scheduled.

Stop uses cooperative task cancellation. No new case is scheduled after cancellation. Already completed results remain in the run and are checkpointed to disk. An in-flight cancellation is classified explicitly rather than treated as model degradation.

The standard runner does not retry, so retry counts remain truthful at zero.

## Metrics and scoring

Every non-cancelled terminal case contributes measured end-to-end latency. Mean, median, minimum, and maximum are reported when samples exist. P95 is reported only for 20 or more samples. Backend-reported generation duration is retained separately.

TTFT is `nil` because the current dispatcher contract returns complete non-streaming responses. Token usage is stored only when supplied by the backend. Tokens/second requires reported output tokens and a positive generation duration. Total tokens, tokens per correct answer, and tokens per score point remain unavailable when their inputs are unavailable.

The initial weights are:

| Dimension | Weight |
|---|---:|
| Quality | 35% |
| Reliability | 25% |
| Tool Use | 20% |
| Engineering | 15% |
| Performance | 5% |

The UI exposes all weights and requires a 100% total. Missing dimensions are omitted and available weights are normalized, so a Category run is not penalized for cases it did not execute. Performance has deliberately modest influence. The transparent absolute performance rule awards 100 at 250 ms or faster, then subtracts `50 × log10(latency / 250 ms)`, bounded to 0–100.

Reliability measures valid response contracts; repeated runs add a 25% consistency component. A valid wrong answer can therefore be reliable but have low Quality, avoiding double-counting the same failure.

## Persistence and portability

Production records live under:

```text
~/Library/Application Support/AutoMLXStudio/Benchmarks/v1/
  runs/<run-uuid>.json
  suites/<suite-uuid>.json
```

Every file has `schemaVersion: 1`. Loading is record-isolated: a corrupt or unsupported file is skipped and reported while valid records remain usable. Built-in suites cannot be overwritten; duplication creates a new editable suite and new case identities.

Suite import first creates a validated preview, then requires an explicit Save action. Suite export is versioned JSON. Result export writes both versioned JSON and Markdown to the user-selected directory.

Run comparison requires equal suite identity/version, ordered case set, mode/category, repetitions, temperature, output/context/seed/streaming/quality/warmup settings, score weights, and architecture. Model/backend identity may differ because that is the comparison subject. Every mismatch is shown.

Best-model-by-role recommendations use completed category evidence only and never alter assignments or routing.

## Native UI

The Benchmark workspace provides:

- Overview and first-run empty state;
- New Run configuration;
- cancellable Running state with preserved completed cases;
- Results summary and case detail;
- searchable/filterable History with Run Again, baseline, export, and confirmed deletion;
- two-run Comparison with fairness diagnostics;
- Custom Suite creation, validated import preview, save, export, duplicate, and delete.

The UI uses native SwiftUI `Form`, `Table`, `List`, `Picker`, `ProgressView`, `HSplitView`, alerts, confirmation dialogs, and macOS file panels. Status always has textual or symbolic meaning in addition to color.

## Reproduction

Run the V0.6.1 deterministic tests without models or network access:

```sh
xcodegen generate
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS,arch=arm64' test -only-testing:AutoMLXStudioTests/BenchmarkHarnessTests CODE_SIGNING_ALLOWED=NO
```

Run the complete regression suite twice and the three application builds using the commands recorded in `Validation/V061BenchmarkHarness-20260911/VALIDATION_SUMMARY.md`.

## Explicit non-goals

V0.6.2 Model Role Selection, Adaptive Model Routing, Specialized Agents, Dataset Generation, LoRA/fine-tuning, model distillation, new Vision work, model download, and physical Windows testing are not part of this milestone and were not implemented.
