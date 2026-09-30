# AutoMLXStudio V0.6.0.1 final report

## Status

- Completion: **100% of requested V0.6.0.1 software scope**
- Software complete: **YES**
- Current software readiness: **READY for focused physical Windows revalidation**
- Previous physical validation: **PARTIAL — distributed integration confirmed**
- Physical revalidation: **PENDING**

No physical Windows validation was attempted. Windows was offline, and deterministic adapters/intercepted HTTP are reported only as software evidence.

## Root cause and architecture

Chat was local-only because `ChatView` called `AppState`, which always entered `WorkflowEngine`; that path selected a local `ModelProfile`, prepared `ModelResourceManager`, and called `LLMCompletionClient` directly. Unlike Engineering, ordinary Chat had no backend-qualified selected target and never reached `ModelBackendDispatcher`. `ARCHITECTURE_BEFORE.md` records this before source changes.

After integration, ordinary text Chat uses `ChatView → AppState → ChatGenerationSession → ModelBackendDispatcher → LocalMLXBackend or RemoteInferenceBackend`. `ARCHITECTURE_AFTER.md` documents identity, history, cancellation, result metadata, stale-response protection, and the explicit local-only attachment exception.

## Functional acceptance

| Requirement | Result | Evidence summary |
|---|---|---|
| Local Chat | PASS | Exact local target traverses the shared dispatcher |
| Remote Chat software validation | PASS | Exact remote server/model target traverses the shared dispatcher and intercepted OpenAI-compatible adapter |
| Local model selection | PASS | Grouped `On this Mac` choice and deterministic local default |
| Remote model selection | PASS | Grouped per configured server; collision-safe backend/server/model identity |
| Selection persistence | PASS | Conversation schema migration and restart test preserve exact target; invalid selections remain explicit |
| Multi-turn | PASS | System plus prior user/assistant plus current user is ordered correctly with no duplication |
| Local cancellation | PASS | Existing local cancellation suite remains green |
| Remote cancellation/recovery | PASS | Owned remote task cancels, UI unlocks, selection/history remain, next remote request succeeds |
| Local → Remote | PASS | New turn routes only to the newly selected remote adapter with history retained |
| Remote → Local | PASS | New turn routes back to local; no stale remote adapter remains pinned |
| Remote unavailable handling | PASS | Timeout, connection loss, HTTP error, malformed response, missing/disabled/removed server-model, and unavailable credentials are bounded; no silent fallback |
| Stale response protection | PASS | Response persistence is tied to immutable originating conversation identity |
| Usage and latency metadata | PASS | Provider usage and total duration persist; TTFT remains absent when non-streaming |
| Normal Chat tool-call safety | PASS | Tool calls are rejected explicitly and never executed |

Remote delivery is currently non-streaming and is labeled honestly. Image attachments remain on the existing local Vision workflow; remote multimodal support is not claimed.

## Engineering hardening

The centralized Engineering prompt now requires the smallest correct change, observable requested behavior, no substitution of merely equivalent-looking output, verification after edits, inspection of failures before retry, and avoidance of unnecessary changes. The guidance is general and contains no Qwen-, calculator-, or fixture-specific workaround.

The prior physical safe-command denial was diagnosed as a harness mismatch: it required the literal `/usr/bin/make test` while the model emitted semantically valid `make test`. Production already resolves allowlisted `make` and requires explicit process approval, so no containment, allowlist, default-deny, or approval policy was weakened.

## Physical revalidation fixture

Path: `Validation/Fixtures/RemoteEngineering/`

The permanent baseline contains an intentional one-line `subtotal - fee` bug, a standard-library Python verifier, `make test`, task instructions, and the physical procedure. It uses no network, dependency installation, package manager, or privilege and completes in about 0.03 seconds. Baseline evidence records the expected exit code 2 and expected `9` versus `15`; physical work must use a disposable copy and change the implementation to `subtotal + fee`.

## Tests

| Run | Executed | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Targeted final verified | 37 | 37 | 0 | 0 |
| Full suite final verified #1 | 209 | 203 | 6 | 0 |
| Full suite final verified #2 | 209 | 203 | 6 | 0 |

Counts were read from the final `.xcresult` summaries. The six skips are unchanged explicit hardware/external-model tests: two MLX Audio, one real local MLX workflow, one physical multi-model switch, and two Vision hardware/inference tests. Windows physical acceptance is separate and is not counted as a skip. No failure was weakened or converted to skip.

## Builds

| Build | Result | Verified architecture |
|---|---|---|
| Debug arm64 | PASS | arm64 |
| Release arm64 | PASS | arm64 |
| Release Universal | PASS | x86_64 + arm64 |

All final builds ran after the final test suites with separate DerivedData and `CODE_SIGNING_ALLOWED=NO`. The retained apps are local validation artifacts, not signed/notarized distribution releases. `file`, `lipo`, and SHA-256 manifests verify the saved executables. Universal app build does not by itself prove Intel MLX runtime/model compatibility.

## UI validation

Result: **PASS.** Native offscreen rendering covers normal and minimum sizes, local/remote selection, server and model long names, empty conversation, long transcript/scroll, error, generating/Stop, disabled controls, metadata, and core accessibility descriptions. Five Retina PNGs and two passing render result bundles are retained under `UI/`; see `UI_VALIDATION.md`.

## Security

Result: **PASS** for implemented and tested controls. Tokens remain in Keychain; application persistence contains no credentials; exact routing has no silent fallback; normal Chat cannot execute tools; Engineering authority and approvals remain Mac-owned and unchanged. See `SECURITY_AUDIT.md`.

## Files created

- `AutoMLXStudio/Services/ChatGenerationSession.swift`
- `AutoMLXStudioTests/ChatGenerationSessionTests.swift`
- `Validation/Fixtures/RemoteEngineering/README.md`
- `Validation/Fixtures/RemoteEngineering/PHYSICAL_REVALIDATION.md`
- `Validation/Fixtures/RemoteEngineering/Makefile`
- `Validation/Fixtures/RemoteEngineering/shipping.py`
- `Validation/Fixtures/RemoteEngineering/test_shipping.py`
- `PHYSICAL_REVALIDATION.md`
- `Validation/V0601RemoteChatIntegration-20260911/` evidence, architecture notes, reports, logs, result bundles, screenshots, manifests, and retained apps

## Files modified

- `AutoMLXStudio.xcodeproj/project.pbxproj`
- `AutoMLXStudio/AppState.swift`
- `AutoMLXStudio/Core/Conversations/ConversationModels.swift`
- `AutoMLXStudio/Core/Registry/AgentRegistry.swift`
- `AutoMLXStudio/Models/AppModels.swift`
- `AutoMLXStudio/Services/ConversationStore.swift`
- `AutoMLXStudio/Services/WorkspaceController.swift`
- `AutoMLXStudio/Views/ChatView.swift`
- `README.md`
- `PROJECT6_VALIDATION.md`
- `PROJECT6_WINDOWS_READINESS.md`

## Evidence

Authoritative evidence root: `Validation/V0601RemoteChatIntegration-20260911/`

- Targeted: `TargetedFinalVerified.log`, `.xcresult`, and summary JSON
- Full #1/#2: `FullFinalVerified1.*` and `FullFinalVerified2.*`
- Builds: `DebugFinalVerified.log`, `ReleaseFinalVerified.log`, `UniversalFinalVerified.log`
- Apps: `Apps/DebugFinalVerified/`, `Apps/ReleaseFinalVerified/`, `Apps/UniversalFinalVerified/`
- Architecture: `ARCHITECTURE_BEFORE.md`, `ARCHITECTURE_AFTER.md`
- UI: `UI_VALIDATION.md`, `UI/`, `UI.sha256`
- Security/integrity: `SECURITY_AUDIT.md`, `SourceManifest-before.sha256`, `SourceManifest-final.sha256`, `SourceChanges.txt`, `HistoricalEvidence-current.sha256`, `BinariesFinalVerified.sha256`
- Fixture: `FixtureBaseline.log`

Generated DerivedData caches were moved to Trash after validated apps/logs/result bundles were retained. They are recoverable until Trash is emptied and otherwise reproducible from the recorded commands.

## Windows status and remaining blockers

The previous physical result remains **PARTIAL — distributed integration confirmed**. It physically confirmed TCP, `/v1/models`, Remote Models persistence/health/discovery, real backend inference, multi-turn, cancellation, remote Engineering read/write round-trip, approvals, Stop recovery, and Mac tool locality.

V0.6.0.1 current software readiness is **READY**. The only remaining acceptance blocker is external: run the short real Windows delta through ordinary Chat and the disposable Engineering fixture. Until then, physical revalidation remains **PENDING**. This is not a software blocker and no physical pass is claimed.

## Final verdict

AutoMLXStudio V0.6.0.1 is software-ready for complete focused Windows revalidation. There are no known remaining software blockers in the requested scope. The next action is to restore the physical Windows host and run the documented delta; only a real successful run may change the physical status from PARTIAL/PENDING. V0.6.1 Benchmark Harness, downloads, training/fine-tuning/LoRA, and new Vision work were not started.
