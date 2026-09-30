# V0.6 final validation

## V0.6.1 Model Evaluation / Benchmark Harness — 11 September 2026

V0.6.1 replaces the visible throughput-only Benchmark page with a backend-neutral correctness and reliability harness while retaining the legacy persistence API for compatibility. The built-in suite contains 33 original offline cases across eight categories. Exact, normalized, contains, regex, numeric, strict JSON, native/simulated tool-call, and closed-registry programmatic graders are deterministic and separately tested.

The sequential runner uses the shared `ModelBackendDispatcher` with fallback disabled, per-case timeouts, isolated failures, cooperative cancellation, and progress checkpoint persistence. The native UI includes Overview, New Run, Running, Results/case detail, History, Comparison, and Custom Suites. Scoring, truthful optional metrics, schema-versioned storage, import preview, JSON/Markdown export, fairness checks, and evidence-only best-model-by-role recommendations are documented in `PROJECT_V061_BENCHMARKS.md`.

Authoritative test, build, architecture, UI, demo-export, and manifest evidence is stored in `Validation/V061BenchmarkHarness-20260911/`. Physical Windows testing was not performed; the previous physical status remains **PARTIAL** and the current V0.6.1 physical status remains **PENDING**.

## V0.6.0.1 remote Chat integration — 11 September 2026

The focused V0.6.0.1 work adds ordinary Chat remote selection and dispatcher routing without changing the V0.6 Engineering authority boundary. Local and remote text now share `ModelBackendDispatcher`; image requests remain explicitly on the established local Vision workflow because remote attachment support is not verified. Model selection persists per conversation as the exact backend, server UUID, and model ID. Tokens remain exclusively in the Keychain-backed remote vault.

New deterministic validation covers local/remote dispatch, exact multi-turn order, collision-safe model identity, restart persistence, disabled/removed/missing server-model state, stale-response destination safety, cancellation, safe backend failure propagation, and non-execution of normal-Chat tool calls. Existing remote adapter tests continue to cover intercepted completion, timeout, connection loss, HTTP status, malformed API response, discovery, credentials, cancellation, and native tool parsing. Final V0.6.0.1 counts and build evidence are stored under `Validation/V0601RemoteChatIntegration-20260911/`.

Windows physical revalidation was not run because the host is offline. The current physical status is **PARTIAL / V0.6.0.1 DELTA PENDING**, with the exact focused procedure in `PHYSICAL_REVALIDATION.md`.

V0.6.0.1 software completion is **100%** and software status is **READY**. The authoritative 11 September results are:

| V0.6.0.1 verification | Executed | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Targeted final | 37 | 37 | 0 | 0 |
| Full suite final #1 | 209 | 203 | 6 | 0 |
| Full suite final #2 | 209 | 203 | 6 | 0 |

Debug arm64, Release arm64, and Release Universal builds all passed after the final test runs. `file` and `lipo` confirm the Universal executable contains `x86_64` and `arm64`. Native offscreen rendering validated normal and minimum window sizes plus local/remote selection, long names, empty, error, generating/Stop, disabled-control, scrolling, and long-message states. The authoritative details, logs, result bundles, screenshots, manifests, and binaries are in `Validation/V0601RemoteChatIntegration-20260911/FINAL_REPORT.md`.

The six skips are the same explicit hardware/external-model tests from V0.6; no failure was converted to a skip. Deterministic remote tests used intercepted HTTP or injected adapters and are software evidence only. No Windows connection, model download, Benchmark Harness, training, fine-tuning, LoRA, or Vision milestone work was performed.

## Preserved V0.6 baseline — 10 September 2026

Validated on 10 September 2026 in `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3`.

**Software complete: YES. Completion: 100% of the requested V0.6 software scope.** Physical Windows acceptance is separate and remains pending. The deterministic tests do not establish physical model quality, real LAN behavior, or Windows hardware compatibility.

## Test results

| Verification | Executed | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Final targeted verification, recovered completed run | 12 | 12 | 0 | 0 |
| Full Suite Final Run #1 | 197 | 191 | 6 | 0 |
| Full Suite Final Run #2 | 197 | 191 | 6 | 0 |

The targeted run completed successfully on 9 September at 23:56:16 Europe/Rome, after the final scrolling and approval-panel changes. Its original log and result bundle were recovered and inspected at resume. It was not repeated unnecessarily. Both final full suites are fresh, separate xcodebuild test executions on 10 September against the unchanged application and test sources. Counts were checked directly with `xcresulttool`, not inferred from a shell pipeline or a partial test log.

The increase from the earlier 196-test baseline to 197 is the native Engineering layout rendering test added before this final-validation continuation. No tests were added, removed, weakened, or converted into skips during final validation.

Evidence is archived locally under `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3/Validation/V06Final-20260910/` with logs, `xcresult` bundles, summaries, the native layout image, and binary checksums. Those generated bundles and compiled apps are intentionally excluded from the GitHub source copy, so this report does not contain links that would be broken after a Windows clone.

## App builds

| Entire application build | Result | Confirmed binary architecture |
|---|---|---|
| Debug arm64 | PASS | arm64 |
| Release arm64 | PASS | arm64 |
| Release Universal | PASS | x86_64 and arm64 |

All three builds used separate fresh DerivedData directories and returned exit code 0 with `BUILD SUCCEEDED`. Universal compiled and linked both architectures; `lipo -info` and `file` confirmed both executable slices. No dependency or project-architecture workaround was required. The application integrates external MLX runtimes through adapters rather than linking an MLX package into the app target, so a Universal app build does not imply Intel MLX inference support. Tests ran on arm64; an Intel machine was not physically tested.

These are local validation builds with `CODE_SIGNING_ALLOWED=NO`, not signed/notarized distribution releases.

- Debug: [build log](Validation/V06Final-20260910/DebugArm64.log), [application](Validation/V06Final-20260910/Apps/DebugArm64/AutoMLXStudio.app).
- Release arm64: [build log](Validation/V06Final-20260910/ReleaseArm64.log), [application](Validation/V06Final-20260910/Apps/ReleaseArm64/AutoMLXStudio.app).
- Universal: [build log](Validation/V06Final-20260910/Universal.log), [architecture evidence](Validation/V06Final-20260910/UniversalArchitectures.txt), [application](Validation/V06Final-20260910/Apps/Universal/AutoMLXStudio.app).
- [Binary SHA-256 manifest](Validation/V06Final-20260910/Binaries.sha256).

## Engineering and remote software checks

| Required behavior | Result | Evidence |
|---|---|---|
| Local Engineering integration | PASS | `testLocalStrictJSONInspectEditTestVerify` traverses the real LocalMLXBackend, model adapter, dispatcher, builder, engine, and filesystem/process runtime; physical model preparation and inference are injected |
| Remote Engineering integration | PASS | `testRemoteHTTPInspectApproveEditTestVerifyThroughProductionBuilder` traverses the real RemoteInferenceBackend with intercepted HTTP and real Mac tools |
| Inspect → edit → test → verify | PASS | Both modes assert real file bytes, exact tool order, five model turns, successful test-process exit, final response, and termination |
| Edit/build approval | PASS | Exact edit and test-process decisions are separate; deny leaves original bytes unchanged; default deny and timeout are tested |
| Cancellation | PASS | Pending edit cancellation returns within the asserted two-second bound; late permission is refused; owned process cancellation preserves an unrelated process |
| UI/controller integration | PASS | Stable AppState controller identity, page re-entry, immutable submitted task/quality, live events, retained result/changes, and native rendering |
| Verification freshness | PASS | A later tracked mutation invalidates earlier successful checks |
| Negative scenarios | PASS | Denial, cancellation, tool failure, malformed output, repeated-action detection, and exact Fast iteration ceiling |

Server CRUD, profile persistence, health, `/models`, discovery, server/model selection, generation, native assistant/tool-result correlation, timeout, connection-loss handling, cancellation, and remote Engineering routing were checked against the implemented code and passing tests. The default `/v1` base path and user-entered host/port support `http://WINDOWS-IP:PORT/v1`. LM Studio is not a required provider: its optional response-header recognition only supplies a display label and does not alter endpoints or execution.

WINDOWS REMOTE SOFTWARE READINESS: READY

WINDOWS PHYSICAL VALIDATION:
PENDING PHYSICAL VALIDATION

The [physical acceptance checklist](PROJECT6_WINDOWS_READINESS.md) remains pending in every row. No Windows server, real network inference, model download, or external process termination was performed in this continuation.

## Security and documentation consistency

Security regression: PASS for the implemented and tested controls. Source inspection confirmed production Keychain APIs behind the token vault and authentication headers constructed only at the request boundary. Passing tests cover token exclusion from profile JSON, credential redaction, LAN HTTP warnings, canonical workspace containment, traversal and symlink rejection, default denial, exact approvals, cancellation, bounded output, and sanitized process environments. Deterministic token tests use injected vaults and do not manipulate the user's real secrets.

The model backend proposes calls; only the Mac runtime executes them after validation and approval. Remote inference receives selected text and results, not a Mac filesystem handle. Approved project build scripts are not constrained by an OS sandbox; this existing limitation is explicitly documented in [Engineering safety](PROJECT6_ENGINEERING.md). A passing security regression is not a claim that arbitrary untrusted build scripts are safe.

Documentation consistency: PASS. `PROJECT6_ARCHITECTURE.md`, `PROJECT6_ENGINEERING.md`, `PROJECT6_WINDOWS_READINESS.md`, and `README.md` were checked against the final implementation. This report completes the previously referenced validation-document link. No document claims physical Windows verification.

## Known skips

The same six hardware/external-model-dependent tests were skipped in both final suites:

1. `AudioHardwareTests.testRealASRWithDeterministicSynthesizedWAV`: real ASR requires the explicit `RUN_MLX_AUDIO_HARDWARE_TESTS=1` opt-in.
2. `AudioHardwareTests.testRealTTSGeneratesReadableAudioWithoutPlayback`: real TTS requires the same audio hardware opt-in.
3. `MLXIntegrationTests.testRealServerAutoPortFullWorkflowAndStop`: physical local inference requires `RUN_MLX_INTEGRATION_TESTS=1`.
4. `MultiModelIntegrationTests.testInstalledGeneralCodingAndReasoningModelsSwitchPhysically`: physical model switching requires `RUN_MLX_MULTI_MODEL_TESTS=1`.
5. `VisionHardwareTests.testInstalledVisionBackendHardwarePreflight`: all four indexed weight shards remain missing; download lock files were detected, which alone do not prove an active transfer.
6. `VisionHardwareTests.testRealVisionInferenceWithGeneratedProjectFiveImage`: physical Vision inference requires `RUN_MLX_VISION_HARDWARE_TESTS=1`; the external model remains incomplete.

No hardware opt-in was forced and no failure was hidden as a skip. Windows physical validation is a separate pending acceptance activity, not a seventh XCTest skip.

## Environment and non-blocking diagnostics

- Xcode 26.6, build 17F113; macOS 26.6.2, build 25G83; arm64 MacBook Pro.
- Deployment target remains macOS 14.0; Swift project setting remains 5.10.
- AppIntents metadata extraction warns that there is no AppIntents.framework dependency. This does not cause a compiler/linker/test failure.
- The hosted XCTest app emits system `com.apple.linkd.autoShortcut` connection messages. Both complete runs still return success with no test failures.

## Changes since the checkpoint

- Added `PROJECT6_VALIDATION.md` (this report).
- Added `Validation/V06Final-20260910/` containing logs, three result bundles, summaries, the native rendering, source/binary manifests, integrity evidence, and the three compiled apps.
- No application source, test source, routing, UI, generated Xcode project, model, or existing Project 6 documentation was changed during this continuation. The folder is not a Git repository, so `git diff`/`git status` could not provide a historical diff. [SHA-256 verification](Validation/V06Final-20260910/SourceIntegrity.log) confirms all 98 recorded source/project files remained unchanged throughout final validation.
- Newly generated DerivedData/cache directories were removed after successful builds; the apps, logs, and result bundles were retained. These caches are reproducible by rebuilding. ExFAT removed AppleDouble `._` sidecars alongside their parent files, producing harmless missing-sidecar cleanup messages; subsequent directory checks confirmed all four cache directories were gone. The retained evidence and apps occupy approximately 280 MB, down from approximately 29 GB with caches, and every saved executable passed its SHA-256 check.

The old repository on Crucial X9 Pro and the external model/runtime paths were preserved.

## Reproduction

From the operational repository, choose new result-bundle/output directory names when rerunning; xcodebuild will not overwrite an existing result bundle.

```sh
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath Validation/Recheck/DerivedData -resultBundlePath Validation/Recheck/Run1.xcresult CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath Validation/Recheck/DerivedData -resultBundlePath Validation/Recheck/Run2.xcresult CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath Validation/Recheck/Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath Validation/Recheck/Release CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
xcodebuild -project AutoMLXStudio.xcodeproj -scheme AutoMLXStudio -configuration Release -destination 'generic/platform=macOS' -derivedDataPath Validation/Recheck/Universal CODE_SIGNING_ALLOWED=NO 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

## Final verdict

Remaining V0.6 software blockers: **NONE**. V0.6 remains complete for its requested software scope. V0.6.1 Benchmark Harness validation is recorded above and in its dedicated evidence directory. Physical Windows validation remains **PENDING PHYSICAL VALIDATION**.
