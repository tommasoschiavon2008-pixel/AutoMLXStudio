# AutoMLXStudio V0.6.1 — Final Windows Physical Revalidation

**Validation date:** 2026-09-20  
**Overall result:** `PARTIALLY VERIFIED`

**Resumed-validation timestamp:** 2026-09-20T19:46:24Z

## Scope and preservation

This was a physical revalidation only. No Swift source, Xcode project configuration, dependencies, tests, previous validation evidence, source manifest, or external Git state was modified. New files in this validation-evidence directory are the only artifacts created.

## Environment observed

| Item | Observed state |
| --- | --- |
| Validation host | macOS repository at `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3` |
| Windows inference target | `192.168.1.20:1234` |
| Expected remote model | `qwen/qwen3-4b-2507` |
| TCP check | Connection failed: `Host is down` |
| `/v1/models` check | Connection failed: curl exit `7` |
| Native UI target | The previous temporary Debug bundle path under `/tmp/AutoMLXStudio-V061-DebugFreezeFinal/...` no longer exists; no running `AutoMLXStudio` process was observed |

## Source-integrity verification

The frozen manifest was checked immediately before and after all validation actions:

| Check | Result | Evidence |
| --- | --- | --- |
| Pre-validation manifest | `PASS` — 108/108 entries `OK` | `20260920-Preflight/SourceIntegrity-Before.log` |
| Post-validation manifest | `PASS` — 108/108 entries `OK` | `20260920-Preflight/SourceIntegrity-After.log` |
| Count reconciliation | `PASS` — pre 108, post 108 | `20260920-AutomationBlocker/Process-And-Integrity-Summary-Corrected.log` |

The source freeze remained intact.

## Current physical revalidation matrix

`FAIL` here means the executed environmental prerequisite did not meet its expected condition; it does not identify a source-code regression. `BLOCKED` means the test could not be completed because its prerequisite was unavailable. `NOT EXECUTED` means no safe, meaningful attempt was made.

| Phase | Physical check | Status | Result / reason |
| --- | --- | --- | --- |
| P1 | TCP connectivity to `192.168.1.20:1234` | `FAIL` | `nc` returned `Host is down` (exit 1). |
| P1 | `GET /v1/models` and discovery of `qwen/qwen3-4b-2507` | `FAIL` | curl could not connect (exit 7); model discovery could not occur. |
| P2 | Normal Chat through the real remote backend | `BLOCKED` | The required Windows endpoint is unavailable and no current native app bundle could be attached. |
| P3 | Multi-turn Chat | `BLOCKED` | Depends on successful P2. |
| P4 | Conversation persistence / reload | `BLOCKED` | No physical remote conversation could be created. |
| P5 | Chat cancellation and post-cancel recovery | `BLOCKED` | No active remote generation could be started. |
| P6 | Controlled server-failure handling and recovery | `NOT EXECUTED` | The server was already unavailable; an additional induced failure would not be a controlled, safe test. |
| P7 | Engineering workflow with an out-of-source fixture | `BLOCKED` | Requires the remote service and a usable current native app session. |
| P8 | Engineering approval: Allow Once and Deny | `BLOCKED` | Requires P7. |
| P9 | Engineering filesystem-boundary validation | `NOT EXECUTED` | No physical Engineering session was available; no substitute static result is presented as a physical pass. |
| P10 | Quick Benchmark through the real UI | `BLOCKED` | Requires remote inference and a usable native UI session. |
| P10 | Benchmark result persistence | `BLOCKED` | No benchmark run could be started. |
| P11 | Benchmark cancellation from the UI | `BLOCKED` | No benchmark run could be started. |
| P12 | Single controlled native UI automation attach | `BLOCKED` | The specified temporary Debug bundle was absent, so CUA returned `Invalid app`; no retry was performed. |

## Resumed validation — 2026-09-20T19:46:24Z

### Chronology

1. The initial physical attempt found `192.168.1.20:1234` unavailable (`Host is down`; curl exit `7`).
2. The user reported that the Windows inference server had been started.
3. Validation resumed after a new `PASS` source-manifest check (108/108 entries valid).
4. The configured endpoint remained unusable from the Mac: TCP timed out and `/v1/models` timed out. A current stable V0.6.1 Debug app was then launched, but the single allowed CUA attach failed with `Sky Computer Use native pipe closed before response`.

### Resumed validation matrix

| Phase | Physical check | Status | Result / reason |
| --- | --- | --- | --- |
| Preflight | Source manifest before resumed actions | `PASS` | 108/108 frozen entries `OK`. |
| P2 | TCP connectivity to `192.168.1.20:1234` | `FAIL` | `nc` timed out (exit 1). |
| P2 | `GET /v1/models` | `FAIL` | curl timed out (exit 28); no HTTP response or model list was received. |
| P2 | Discovery of `qwen/qwen3-4b-2507` | `BLOCKED` | The model endpoint did not respond. |
| P3 | Stable validation build | `PASS` | Existing frozen Debug bundle launched and process `22824` was observed running. |
| P4 | Normal remote Chat with exact response | `BLOCKED` | Requires a reachable Windows endpoint and a functioning UI interaction channel. |
| P5 | Multi-turn Chat context | `BLOCKED` | Depends on P4. |
| P6 | Conversation persistence | `BLOCKED` | No physical remote conversation could be created. |
| P7 | Chat Stop and recovery | `BLOCKED` | No physical remote generation could be started. |
| P8 | Engineering remote read/write fixture | `BLOCKED` | Requires normal remote operation and a working application interaction channel. No fixture was created or represented as a physical pass. |
| P9 | Approval security: Allow Once / Deny | `BLOCKED` | Depends on P8. |
| P10 | Filesystem-boundary behavior | `NOT EXECUTED` | No physical Engineering workflow was available; no static substitute is presented as a physical result. |
| P11 | Quick Benchmark through real UI | `BLOCKED` | Requires reachable remote inference and a working UI interaction channel. |
| P12 | Benchmark cancellation | `BLOCKED` | No benchmark run could be started. |
| P13 | Single controlled native UI automation attach | `BLOCKED` | Actual current bundle used; CUA returned `Sky Computer Use native pipe closed before response`. No retry followed. |
| P14 | Controlled server-failure and recovery | `NOT EXECUTED` | Normal remote operation did not succeed; an induced outage would not be a controlled test. |
| Postflight | Source manifest after resumed actions | `PASS` | 108/108 frozen entries `OK`. |

### Stable app used

The existing build was used instead of recompiling the frozen source:

| Property | Observed value |
| --- | --- |
| Bundle | `Validation/V061BenchmarkHarness-20260911/DerivedData-Debug/Build/Products/Debug/AutoMLXStudio.app` |
| Configuration | Debug, from the build-product path |
| Bundle identifier | `com.tommaso.AutoMLXStudio` |
| Architecture | Thin `arm64`, reported by code-signing inspection |
| Signing | Ad-hoc, linker-signed; no team identifier |
| Executable SHA-256 | `de235f3adf28482aa3911758fe77b17a272505f565413b8202348f430c43e9f8` |
| Process state | Running after launch and still running after the CUA pipe failure |

No build was necessary. A read-only `xcodebuild -list` command reported that the local Xcode licence is not accepted; this did not affect use of the existing validation bundle and no source or project configuration was changed.

### Resumed findings

1. **The user-reported server start did not yield a reachable service at the configured address.** The failure changed from the earlier immediate reachability error to a five-second TCP/API timeout. The Mac also reported a rejected host route after the attempt. These observations identify a host-path, server-binding, or firewall-layer issue; they do not establish an AutoMLXStudio source defect.
2. **No alternate Windows IPv4 address was safely identifiable.** Existing local ARP/route evidence did not establish ownership of any alternate address, so no devices or networks were scanned and no speculative endpoint was tested.
3. **A current, non-temporary application bundle is available and launches.** This removes the prior missing-`/tmp` bundle blocker, but it does not enable remote-workflow validation while the server is unreachable.
4. **UI automation infrastructure is blocked independently of process liveness.** The application process remained running after the one CUA call failed, but visual/UI responsiveness could not be inferred and is not classified as a pass.

## Resumed validation — user-provided endpoint `192.168.1.22:1234` — 2026-09-20T20:02:24Z

### Chronology extension

5. The user explicitly identified `192.168.1.22:1234` as the current Windows server address, superseding the historical `.20` address for this attempt.
6. A new preflight source-manifest check passed with 108/108 entries valid.
7. TCP and `/v1/models` both timed out at the new address. Local ARP and routing evidence resolved `192.168.1.22` on `en0`, so the Mac has a Layer-2/route path to the host but received no service response on TCP port `1234`.
8. The post-validation source-manifest check also passed with 108/108 entries valid. No new native UI attach was attempted: the prior one-attach limit for the already verified current stable bundle remains in force.

### New-endpoint validation matrix

| Phase | Physical check | Status | Result / reason |
| --- | --- | --- | --- |
| P1 | Source manifest before endpoint check | `PASS` | 108/108 frozen entries `OK`. |
| P2 | TCP connectivity to `192.168.1.22:1234` | `FAIL` | `nc` timed out after five seconds (exit 1). |
| P2 | `GET http://192.168.1.22:1234/v1/models` | `FAIL` | curl timed out after five seconds (exit 28); no HTTP response was received. |
| P2 | Discovery of `qwen/qwen3-4b-2507` | `BLOCKED` | `/v1/models` did not respond. |
| P4–P12 | Chat, multi-turn, persistence, Stop/recovery, Engineering, approvals, filesystem boundary, Quick Benchmark, and benchmark cancellation | `BLOCKED` | Physical workflows require a reachable Windows inference service; no substituted API or static test is counted as application evidence. |
| P13 | Native UI automation | `BLOCKED` | The single allowed attach to the current stable bundle already failed with `native pipe closed`; it was not retried. |
| P14 | Controlled backend failure/recovery | `NOT EXECUTED` | Successful normal remote operation is a prerequisite. |
| Final source check | Source manifest after endpoint check | `PASS` | 108/108 frozen entries `OK`. |

### New-endpoint finding

The network evidence reaches the host address but not the inference service: `192.168.1.22` resolved to MAC `50:eb:f6:7c:18:6a` and has an active host route through `en0`, while both TCP and HTTP requests to port `1234` timed out. This is consistent with the inference service not listening on the LAN interface, Windows firewall filtering port `1234`, or the service not being ready at the stated address. It is not evidence of an AutoMLXStudio source failure.

## Mac physical resume — confirmed endpoint `192.168.1.7:1234` — 2026-09-28T16:34:33Z

### Chronology extension

9. Windows-side physical diagnosis identified the current IPv4 address as `192.168.1.7`, with LM Studio `0.4.25+1` listening on `0.0.0.0:1234`, Windows network profile Private, local and LAN `/v1/models` HTTP 200, `qwen/qwen3-4b-2507` present, and local inference returning `AUTOMLX_WINDOWS_LOCAL_OK`. The supplied runtime state used context length `8192` and parallelism `1`; it was not changed during this Mac validation.
10. The Mac independently established TCP connectivity to `192.168.1.7:1234`, received HTTP 200 from `/v1/models`, and observed `qwen/qwen3-4b-2507` in the returned model list. This supersedes the earlier environmental blocker without deleting its evidence.
11. The stable frozen Debug bundle was inspected and launched. The expected AutoMLXStudio executable process was observed running from the recorded bundle path.
12. The single controlled native UI automation attach returned `Sky Computer Use native pipe closed before response`. The AutoMLXStudio process remained running, but application UI responsiveness and runtime backend selection were not inferred from process liveness.
13. Preflight and final source checks both passed with 108/108 manifest entries valid.

### Mac-resume validation matrix

| Phase | Physical check | Status | Result / reason |
| --- | --- | --- | --- |
| P1 | Source manifest before physical validation | `PASS` | 108/108 frozen entries `OK`. |
| P2 | TCP connectivity to `192.168.1.7:1234` | `PASS` | TCP connection succeeded. |
| P2 | `GET http://192.168.1.7:1234/v1/models` | `PASS` | HTTP 200 received from the Mac. |
| P2 | Discovery of `qwen/qwen3-4b-2507` | `PASS` | Required model present in the returned JSON list. |
| P3 | Stable frozen application bundle | `PASS` | Debug arm64 bundle inspected; executable SHA-256 matched the previously recorded stable build; process `85583` launched from the expected path. |
| P4 | Runtime selection of Windows remote / `.7` / Qwen | `BLOCKED` | Native UI automation channel failed before runtime settings could be physically selected or observed. |
| P5 | Real AutoMLXStudio remote Chat | `BLOCKED` | Requires physical runtime configuration and UI interaction; direct curl was not substituted. |
| P6 | Multi-turn Chat context | `BLOCKED` | Depends on successful P5. |
| P7 | Conversation persistence | `BLOCKED` | No physical remote conversation was created. |
| P8 | Chat Stop and recovery | `BLOCKED` | No physical remote generation was started. |
| P9 | Engineering read/write fixture | `BLOCKED` | Requires the real Engineering UI workflow and confirmed Windows runtime selection. |
| P10 | Approval security: Allow Once / Deny | `BLOCKED` | Requires P9 and physical approval-dialog interaction. |
| P11 | Filesystem boundary | `BLOCKED` | Requires a physical Engineering session; no static substitute was used. |
| P12 | Quick Benchmark and result persistence | `BLOCKED` | Requires the real Benchmark UI and confirmed Windows runtime selection. |
| P13 | Benchmark cancellation | `BLOCKED` | No benchmark run was started. |
| P14 | Single native UI automation attach | `BLOCKED` | Exact result: `Sky Computer Use native pipe closed before response`; zero retries. |
| P15 | Controlled server failure/recovery | `NOT EXECUTED` | Successful normal application-level operation is a prerequisite, and unrelated Windows work was not disrupted. |
| P18 | Final source-manifest check | `PASS` | 108/108 frozen entries `OK`. |

### Stable app confirmation

| Property | Observed value |
| --- | --- |
| Bundle | `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3/Validation/V061BenchmarkHarness-20260911/DerivedData-Debug/Build/Products/Debug/AutoMLXStudio.app` |
| Configuration | Debug |
| Architecture | arm64 |
| Signing | Ad-hoc, linker-signed |
| Executable SHA-256 | `de235f3adf28482aa3911758fe77b17a272505f565413b8202348f430c43e9f8` |
| Process after launch and attach failure | Running from the expected executable path |

The network prerequisite is now physically satisfied from the Mac. The remaining blocker is human interaction with the real AutoMLXStudio UI, not Windows endpoint reachability and not source integrity.

## Findings

1. **Windows availability prevents current physical acceptance.** The target failed the executed transport prerequisite before any application request could reach it: `Host is down` for TCP and curl exit `7` for `/v1/models`. This is an environment/connectivity finding, not a demonstrated AutoMLXStudio application failure.
2. **Native UI automation remains unverified in this pass.** The mandated single attach attempt could not resolve the prior ephemeral `/tmp` app bundle. It was not treated as a UI pass and was not retried. Historical automation transport failures are not asserted as a result of this current attempt.
3. **No source-integrity regression was introduced.** Both manifest checks report all 108 frozen entries as valid.

## Baseline software-validation context

The following are the frozen baseline results supplied for V0.6.1 and were not rerun during this source-preserving physical revalidation: targeted tests `18/18` passing; regression `209` executed, `203` passing, `6` skipped, `0` failing; full runs `227` executed, `221` passing, `6` skipped, `0` failing; architecture builds, deterministic demo (`33/33`, score `100`), persistence, and security checks green.

## Evidence created in this revalidation

- `20260920-Preflight/SourceIntegrity-Before.log`
- `20260920-Preflight/SourceIntegrity-After.log`
- `20260920-Connectivity/Connectivity-Retry.log`
- `20260920-Connectivity/Models-Retry.log`
- `20260920-AutomationBlocker/Automation-Attempt.log`
- `20260920-AutomationBlocker/Process-And-Integrity-Summary-Corrected.log`
- `20260920T194624Z-Resume/SourceIntegrity-Resume.log`
- `20260920T194624Z-Resume/TCP-Retest.log`
- `20260920T194624Z-Resume/Models-Retest.log`
- `20260920T194624Z-Resume/Models-Retest.headers`
- `20260920T194624Z-Resume/Network-LocalEvidence.log`
- `20260920T194624Z-Resume/StableApp-Identity.log`
- `20260920T194624Z-Resume/StableApp-Launch.log`
- `20260920T194624Z-Resume/NativeUI-Attach.log`
- `20260920T194624Z-Resume/SourceIntegrity-Resume-Post.log`
- `20260920T200224Z-Resume-NewWindowsIP/SourceIntegrity-Before-NewEndpoint.log`
- `20260920T200224Z-Resume-NewWindowsIP/TCP-NewEndpoint.log`
- `20260920T200224Z-Resume-NewWindowsIP/Models-NewEndpoint.log`
- `20260920T200224Z-Resume-NewWindowsIP/Network-LocalEvidence-NewEndpoint.log`
- `20260920T200224Z-Resume-NewWindowsIP/SourceIntegrity-After-NewEndpoint.log`
- `20260928T163433Z-MacResume-192.168.1.7/SourceIntegrity-Before.log`
- `20260928T163433Z-MacResume-192.168.1.7/TCP-192.168.1.7.log`
- `20260928T163433Z-MacResume-192.168.1.7/Models-192.168.1.7.headers`
- `20260928T163433Z-MacResume-192.168.1.7/Models-192.168.1.7.json`
- `20260928T163433Z-MacResume-192.168.1.7/Models-192.168.1.7.log`
- `20260928T163433Z-MacResume-192.168.1.7/StableApp-Identity.log`
- `20260928T163433Z-MacResume-192.168.1.7/StableApp-Launch.log`
- `20260928T163433Z-MacResume-192.168.1.7/NativeUI-Attach.log`
- `20260928T163433Z-MacResume-192.168.1.7/SourceIntegrity-After.log`

An earlier `Process-And-Integrity-Summary.log` is retained as raw evidence but has no integrity counts because it used an unavailable absolute `rg` path; the corrected timestamped summary above is authoritative.

## Final status

| Dimension | Status |
| --- | --- |
| Frozen source integrity | `PASS` |
| Prior software-validation baseline | `PASS` (baseline; not rerun here) |
| Current Windows connectivity | `PASS` — `.7:1234` reachable; `/v1/models` HTTP 200; required model present |
| Current Windows application integration | `BLOCKED` |
| Current stable validation build | `PASS` — launched from a non-temporary path |
| Current native UI automation | `BLOCKED` — native pipe closed; no retry |
| Acceptance outcome | `PARTIALLY VERIFIED` |

V0.6.1 is not yet physically re-accepted for Windows application integration. The current endpoint `192.168.1.7:1234` and required Qwen model are now verified from the Mac, the stable app is running, and the source freeze remains intact. Final acceptance still requires genuine physical evidence from the real AutoMLXStudio UI for runtime backend selection, Chat, multi-turn context, persistence, Stop/recovery, Engineering read/write and approvals, filesystem boundary behavior, Quick Benchmark, and result persistence.
