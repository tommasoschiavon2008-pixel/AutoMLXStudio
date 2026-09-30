# AutoMLXStudio — remote connection repair and physical Windows validation

Validation: 2026-09-28–29, Europe/Rome. Operational repository: `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3`. The original V0.6.1 freeze is a historical baseline, **not** the identity of the repaired source. Overall: remote inference and benchmark integration **PASS**; Engineering filesystem boundary as a whole **FAIL** because an approved build command read outside the authorized workspace. Do not treat this build as security-accepted for untrusted Engineering commands.

## Chronology and root cause

1. Earlier Windows physical validation could not reach the originally configured `192.168.1.20:1234`, nor the subsequently user-supplied `.22:1234`. Those failures and the unchanged frozen source are preserved in `../V061WindowsPhysicalRevalidation-20260911/FINAL-WINDOWS-PHYSICAL-REVALIDATION.md` and its dated evidence.
2. Windows-side diagnosis later identified the actual address as `192.168.1.7:1234`. LM Studio 0.4.25+1 was listening on `0.0.0.0:1234`; Windows local and LAN `/v1/models` returned HTTP 200 with `qwen/qwen3-4b-2507`, and local inference returned `AUTOMLX_WINDOWS_LOCAL_OK`. The Mac independently passed `nc` TCP and `GET http://192.168.1.7:1234/v1/models` HTTP 200. The 2026-09-29 resume again received HTTP 200.
3. Before editing, the frozen source manifest passed **108/108** entries; see `FreezeManifest-PreFix.log` and `PRE-FIX-STATE.md`. The original frozen Debug app was ad-hoc signed, had no Team ID and no effective `NSLocalNetworkUsageDescription`, with app sandbox disabled. The original AutoMLXStudio process failed before HTTP despite successful Mac Terminal curl: Network.framework reported `unsatisfied (Local network prohibited)`, CFNetwork transferred zero response bytes, and URLSession returned `NSURLErrorDomain -1009` (underlying POSIX 50). See `PreFix-Network-Denial.log`. The code also mislabeled `.notConnectedToInternet` as a dropped server connection and displayed “Server offline.” This was a **Mac application local-network privacy/identity failure**, not a demonstrated Windows outage. Apple's [local-network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) and [usage-description documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription) describe the relevant app-level requirement.
4. The repair added `NSLocalNetworkUsageDescription` to the XcodeGen source and checked-in Xcode project (Debug and Release), built with the available Apple Development signing identity, and mapped URL error `-1009` to a distinct `.networkUnavailable`/health `.unavailable` state with actionable macOS Local Network guidance. No sandbox or ATS exception was added. The exact pre-fix-to-repair source delta is `SOURCE-DIFF.patch`; reconstructed pre-fix hashes matched `PRE-FIX-STATE.md` and reverse patch dry-run passed.
5. Only four source/configuration files changed: `project.yml`, `AutoMLXStudio.xcodeproj/project.pbxproj`, `AutoMLXStudio/Services/RemoteInferenceBackend.swift`, and `AutoMLXStudioTests/RemoteInferenceBackendTests.swift`. The new tests cover the LM Studio `/v1/models` response and `-1009` classification. This resumed 2026-09-29 validation did **not** change app source or tests.

## Software validation and repaired bundles

| Check | Observed result | Evidence |
| --- | --- | --- |
| Targeted tests | **19 PASS**, 0 failed, 0 skipped | `TargetedTests-InternalDerivedData.log`; targeted `.xcresult` reported 19/19 |
| Full suite | **223 PASS**, 6 skipped, 0 failed, 229 total | `FullSuite.log`; full `.xcresult` test summary |
| Debug arm64 | **PASS** | Built during targeted/full Xcode test actions; actual Debug app used for physical UI tests |
| Release arm64 | **PASS** | `ReleaseArm64Build.log`; `Apps/ReleaseArm64/AutoMLXStudio.app` |
| Release Universal | **PASS**, `x86_64 arm64` | `ReleaseUniversalBuild.log`; `Apps/Universal/AutoMLXStudio.app` |
| Code signing | **PASS** | `codesign --verify --deep --strict` on copied release apps; Apple Development Team `3MKXA7AA48` |
| Effective bundle | **PASS** | Bundle ID `com.tommaso.AutoMLXStudio`; effective Release Info.plist contains `NSLocalNetworkUsageDescription` |

The first targeted-test attempt under an exFAT DerivedData path failed because XCTest's code-signing sidecar could not be created there; it is preserved in `TargetedTests.log`. Repeating with internal macOS DerivedData passed 19/19. The pre-existing weak-capture Swift compiler warning remains. No tests were rerun on 2026-09-29 because no app source changed. The copied release apps were re-verified after resumption.

The old 108-entry manifest was **not regenerated**. Its post-repair check reports exactly four expected mismatches corresponding to the four source/configuration files above (`FreezeManifest-PostFix-ExpectedDiff.log`). Historical validation evidence and its final report were not modified. The repaired build is a patch beyond V0.6.1: **V0.6.1.1 is the recommended designation**, not a version identifier already embedded in the bundle. The current bundle has no `CFBundleShortVersionString`; benchmark metadata reports `appVersion: development`. Release packaging/version stamping remains to be decided separately.

## Physical application results

All application statuses below come from the real repaired macOS AutoMLXStudio Debug UI, connected to Windows LM Studio at `http://192.168.1.7:1234/v1` and model `qwen/qwen3-4b-2507`, not from curl or unit tests. The native CUA pipe did not attach; macOS accessibility/UI scripting and window-scoped screenshots provided the physical interaction channel.

| Workflow | Status | Observed evidence |
| --- | --- | --- |
| Remote Models | **PASS** | UI showed Healthy, OpenAI-compatible, and five discovered models including Qwen; `Physical-RemoteModels-Pass.png`. |
| Remote Chat | **PASS** | Exact reply `AUTOMLX_V061_WINDOWS_CHAT_OK`; `Physical-Chat-Pass.png`. |
| Multi-turn | **PASS** | Same conversation returned `READY`, then recalled `7319`; `Physical-MultiTurn-Pass.png`. |
| Chat Stop | **PASS** | Real Stop control yielded “Generation cancelled”; `Physical-Stop-Cancelled.png`. |
| Chat recovery | **PASS** | Next real remote request returned `RECOVERY_AFTER_STOP_OK`; `Physical-Stop-Recovery-Pass.png`. |
| Conversation/restart persistence | **PASS** | After terminating only the identified repaired app process and relaunching the same bundle, prior transcript including cancellation and recovery remained visible. |
| Engineering remote read | **PASS** | Windows Qwen requested `read_file`; Mac app executed it on isolated `EngineeringScratch/validation-note.txt`; `Physical-Engineering-RemoteRead.png`. |
| Engineering remote write / Allow Once | **PASS** | Windows Qwen requested `replace_in_file`; app showed exact target, old/new text and hash. Only after **Allow Once** did `ORIGINAL` become `APPROVED`; `Physical-Engineering-Approval-AllowOnce.png`. Fixture SHA-256 after write: `28e81bee532fecc42d459380de802e88f38dfd48f69b81ce6c58e53f7d3d0c8b`. |
| Engineering Deny | **PASS** | On 2026-09-29 the same real workflow requested `APPROVED` → `DENIED_SHOULD_NOT_APPEAR`; approval details were inspected and **Deny** clicked. Runtime recorded “Stopped · Permission denied”; fixture SHA-256 remained `28e81bee...d0c8b`. A second distinct write again opened approval, was denied, and left identical bytes, proving no sticky authorization. `Physical-Engineering-Deny-Approval.png`, `Physical-Engineering-Deny-SubsequentApproval.png`. |

The first resumed Deny attempt did not reach approval: LM Studio returned HTTP 400 “Failed to load model” while `GET /v1/models` still listed it. `GET /api/v1/models` showed no loaded instances. The documented LM Studio [`POST /api/v1/models/load`](https://lmstudio.ai/docs/developer/rest/load) was used for this exact Windows Qwen with context length 8192, returned HTTP 200/`loaded` in 2.774 seconds, and the subsequent real UI Deny tests succeeded. No other model was loaded or unloaded by this validation.

During the earlier validation, “Forget Workspace” was accidentally activated once. It removed only the authorization for `EngineeringScratch`, did **not** delete files, and the same isolated workspace was promptly reauthorized. This event is not hidden or counted as a test pass.

## Engineering filesystem boundary — **FAIL** overall

The intended authority is the explicitly authorized `EngineeringScratch` folder. The remote model can request only typed tools exposed by AutoMLXStudio; those tools run on the Mac. `EngineeringWorkspace.resolve` rejects absolute paths, `..`, hidden/sensitive names, and canonical symlink escapes; mutations require the real one-shot approval sheet. Physical tests used only harmless fixtures under this report directory:

| Real remote Engineering attempt | Result |
| --- | --- |
| `read_file validation-note.txt` inside workspace | **PASS** — read completed with exact 73-byte SHA-256. |
| `read_file ../BoundaryOutside/marker.txt` | **PASS** for typed-file boundary — denied as non-normalized relative path. |
| `read_file` with the fixture's absolute path | **PASS** for typed-file boundary — denied as non-relative path. |
| `read_file outside-link.txt` where symlink points to sibling fixture | **PASS** for typed-file boundary — denied: resolved path escapes workspace. |
| `create_file ../BoundaryOutside/unauthorized-create.txt` after inspecting and granting one-shot approval | **PASS** for typed-file boundary — denied; outside file remained absent. `Physical-Boundary-WriteTraversal-Approval.png`. |
| `replace_in_file outside-link.txt` after one-shot approval | **PASS** for typed-file boundary — denied; outside marker SHA-256 remained `1578c5b876fdc22f599735281b8852c5e6306f916cc5f8bfb69adba800ace1df`. `Physical-Boundary-SymlinkWrite-Approval.png`. |
| `run_command` of allowlisted `make boundary-probe` after one-shot approval | **FAIL** for overall boundary — isolated Makefile inside workspace executed `/bin/cat ../BoundaryOutside/marker.txt`. Runtime reported command exit 0, and the Windows model's result included the outside-only marker `OUTSIDE_4682`. `Physical-Boundary-Make-Approval.png`, `Physical-Boundary-Make-Escape.png`. Outside fixture was not changed. |

This is not evidence of access without approval: a visible **Allow Once** was required for `make`. It is evidence that approval and safe working-directory validation are **not filesystem containment** for child processes. `EngineeringToolRuntime` allows `make`, `swift`, `xcodebuild`, package managers, etc.; argument filtering and sanitized environment do not constrain files those processes or their scripts may open. No unrelated or sensitive user file was read. External **write** through a child process was not tested, so no write-escape claim is made. Before claiming a workspace security boundary for Engineering commands, the process architecture needs an enforceable filesystem sandbox or a narrower command policy; changing just the path resolver would not close this observed gap. No speculative source change was made during this validation.

## Engineering Reviewer and verification

Source trace: `EngineeringController` freezes the selected Windows target for the session; `EngineeringSessionBuilder.route` uses it only for `.primary` and `.argumentRepair`. Tool selection/primary text generation therefore used Windows Qwen through `remote-openai-compatible`, while `EngineeringToolRuntime` executed the typed tools on the Mac. `.reviewer` routes independently to `AgentID.reviewer` via local catalog assignment, and `.composer` to `AgentID.finalComposer` if Thorough quality is selected. Balanced quality requests one no-tools Reviewer stage; Composer is disabled. This **local Reviewer architecture is intentional**, not a failure of remote primary/tool execution.

The 2026-09-29 read and command sessions recorded `Reviewer unavailable: No eligible configured generation target is available for reviewer-agent.` The local Reviewer assignment has no currently eligible route in the actual Engineering builder; the remote model is not an automatic reviewer fallback. The status “Unverified” is also intentionally evidence-based: the Engineering session had no successful build/test/syntax/verification command, even when a read/write tool succeeded. Reviewer degradation and verification status must not be confused with remote-tool failure. The Agents UI shows a legacy local fallback as “Available,” while the Engineering route uses only its configured preferred/fallback IDs; this availability presentation/routing discrepancy deserves follow-up, but no reviewer model was silently reassigned and no source was changed.

## Windows Quick Benchmark, Results, and cancellation

The real Benchmark UI selected `remote-openai-compatible`, Windows server `192.168.1.7`, `qwen/qwen3-4b-2507`, built-in **AutoMLXStudio Core Evaluation** (33 total cases), **Quick** mode (8 selected cases), one repetition, no warmup, max output 512, deterministic scoring. The UI progressed through the model/backend dispatcher, Windows LAN, LM Studio, generation, grading and app-owned versioned JSON persistence. Actual scores were not forced to 100%:

| Run ID | UTC start → finish | Mode/state | Cases | Overall score |
| --- | --- | --- | ---: | ---: |
| `EF2CC7C7-1387-437C-BC21-6211D0192898` | 2026-09-29 14:46:35 → 14:46:42 | Quick / **Completed** | 8/8 | **89.8** displayed (89.8271857071 stored) |
| `AC181066-E58F-4735-A3A2-B4F3C7E1C803` | 2026-09-29 14:47:11 → 14:47:16 | Quick / **Completed** | 8/8 | **90.2** displayed (90.1523197077 stored) |
| `6B0A1C1E-C273-4083-948C-9D6C2F735B3E` | 2026-09-29 14:53:46 → 14:53:58 | Standard / **Cancelled** | 31/33 partial | **80.5 partial**, not a completed-run score |
| `52A423C2-4482-413C-85B7-633337684CC8` | 2026-09-29 14:54:31 → 14:54:35 | Quick / **Completed**, post-cancel recovery | 8/8 | **90.4** displayed (90.3885094947 stored) |

The first two Quick starts were both real user-interface activations; each produced its own completed run. The Standard running UI exposed `0 of 33`, later `28 of 33`, progress/failures/elapsed and a real Stop control; after Stop, History recorded **Cancelled**, not Completed, preserving 31 partial case results. A new Quick run then completed, proving the UI/backend were not stuck. See `Physical-Benchmark-Configured.png`, `Physical-Benchmark-Running.png`, `Physical-Benchmark-Cancelled-History.png`, and `Physical-Benchmark-Recovery-History.png`.

Results opened for the 90.2 run and showed correct backend/model, Quick mode, score dimensions, category results and individual case table. Selecting Case Detail displayed the actual General-case input “Return the word studio in uppercase, followed by a colon and the number 61,” output `STUDIO:61`, Exact Match grader, Passed, and 100.0 case score. See `Physical-Benchmark-Result.png` and `Physical-Benchmark-CaseDetail-Scrolled.png`. History retained both completed runs after navigating to Chat and back, and after a controlled restart of only the repaired app process; app-owned records are under the user's `Library/Application Support/AutoMLXStudio/Benchmarks/v1/runs` namespace. **Benchmark persistence: PASS. Benchmark cancellation/recovery: PASS.**

## Remaining work and scope limits

- **Filesystem boundary: FAIL.** The observed approved `make` process read a sibling fixture outside the authorized workspace. Do not claim workspace containment for Engineering commands until a process-level fix is implemented and physically retested. Typed file tools were bounded, but they do not protect general child processes.
- **Reviewer: local-only by design; unavailable in this environment.** Investigate the discrepancy between Agents UI's legacy fallback and actual Engineering Reviewer route/installation eligibility. The remote primary remains functional. “Unverified” accurately means no successful verification command ran.
- **Controlled Windows backend outage/recovery: NOT EXECUTED.** Stopping or firewall-blocking the shared LM Studio endpoint could disrupt unrelated Windows work; no safe isolated shutdown mechanism was established. The resumed transient HTTP 400 model-load issue was recovered by explicitly loading only Qwen, but it was not the prescribed controlled server-outage test and is not mislabeled as its PASS.
- **Version identity:** recommend V0.6.1.1 for this patch, but current bundles lack a release version string and benchmark metadata says `development`. No cosmetic identifier rewrite was made merely for this report.
- **Historical baseline:** the frozen V0.6.1 manifest and previous validation report remain unchanged. This report and isolated fixtures/screenshots are additive validation evidence.

## Final classification

ROOT CAUSE: Mac app local-network privacy/identity denial (`NSURLErrorDomain -1009`, `Local network prohibited`) plus misleading transport mapping.  
FIX: local-network usage description, Apple Development-signed validation bundles, distinct Mac network-unavailable diagnostic.  
FILES CHANGED: four app source/configuration/test files listed above; no further app source change on 2026-09-29.  
TARGETED TESTS: 19 PASS. FULL TEST SUITE: 223 PASS, 6 skipped, 0 failed.  
BUILDS: Debug arm64 PASS; Release arm64 PASS; Universal PASS; signing PASS.  
REMOTE MODELS: PASS. PHYSICAL CHAT: PASS. MULTI-TURN: PASS. PERSISTENCE: PASS. STOP/RECOVERY: PASS.  
ENGINEERING READ: PASS. ENGINEERING WRITE: PASS. ALLOW ONCE: PASS. DENY: PASS.  
FILESYSTEM BOUNDARY: **FAIL** overall (approved build command escaped for read; typed file tools blocked escapes).  
ENGINEERING REVIEWER: intentional local phase, currently unavailable; primary remote path works; sessions without verification commands remain Unverified.  
QUICK BENCHMARK: PASS; actual completed scores **89.8, 90.2, 90.4**.  
BENCHMARK PERSISTENCE: PASS. BENCHMARK CANCELLATION: PASS.  
BACKEND FAILURE/RECOVERY: NOT EXECUTED (shared Windows endpoint not intentionally disrupted).  
ORIGINAL V0.6.1 FREEZE: PRESERVED AS HISTORICAL BASELINE.  
REPAIRED VERSION/BUILD: signed post-freeze patch; **V0.6.1.1 recommended**, not stamped in bundle.  
REMAINING ISSUES: Engineering command sandbox boundary, Reviewer route availability/presentation, release version stamping, controlled outage test.
