# Windows Physical Revalidation — Supplemental Run

**Validation date:** 2026-09-24
**Previous report:** `Validation/V061WindowsPhysicalRevalidation-20260911/FINAL-WINDOWS-PHYSICAL-REVALIDATION.md`
**Endpoint:** `http://192.168.1.10:1234`
**Final result:** `PARTIALLY VERIFIED`

## Scope and preservation

This run resumed the previously blocked Windows physical revalidation using the confirmed physical Windows endpoint. The Mac ran AutoMLXStudio and local tools; the Windows PC ran LM Studio and the remote model. No source, project configuration, dependency, test, Git file, firewall rule, or repository endpoint file was modified. Only new artifacts in this validation directory were created.

## Environment

Mac:
- Hostname: `MacBook-Pro-di-Tommaso.local`
- macOS 27.0, build 26A428
- Repository: `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3`
- Bundle: `Validation/V061BenchmarkHarness-20260911/DerivedData-Debug/Build/Products/Debug/AutoMLXStudio.app`

Windows:
- Hostname: `TommyPC`
- Windows 11 Pro 64 bit, version 10.0.26200
- IPv4: `192.168.1.10`
- LM Studio 0.4.24; listener `0.0.0.0:1234`
- Model: `qwen/qwen3-4b-2507`
- Successful temporary runtime context: 8192 tokens

## Connectivity

| Check | Result | Evidence |
| --- | --- | --- |
| Windows localhost → `/v1/models` | PASS | HTTP 200, 642 bytes |
| Windows LAN IP → `/v1/models` | PASS | HTTP 200, 642 bytes |
| Mac → Windows `/v1/models` | PASS | curl exit 0; valid JSON |
| AutoMLXStudio process → Windows LAN | FAIL | CFNetwork: `Local network prohibited`, NSURLError -1009, zero request/response bytes |

Models returned: `qwen/qwen3-4b-2507`, `mistral-small-3.1-24b-instruct-2503`, `deepseek/deepseek-r1-0528-qwen3-8b`, `qwen/qwen3-vl-8b`, and `text-embedding-nomic-embed-text-v1.5`.

## LM Studio readiness

Initial chat requests returned HTTP 400 because LM Studio failed to load Qwen and DeepSeek. Developer logs showed GPU-memory exhaustion: the default load dialog used a 262144-token context and could not allocate compute buffers.

Through the real LM Studio UI, `qwen/qwen3-4b-2507` was loaded temporarily with context 8192 and reported `READY`. No project or persistent repository setting was changed.

| Prompt | Actual output | Result |
| --- | --- | --- |
| `Respond with exactly:\nAUTOMLX_WINDOWS_OK` | `AUTOMLX_WINDOWS_OK` | PASS |
| `Calculate 7319 + 2846 and return only the result.` | `10165` | PASS |

Both requests succeeded from Windows and the Mac Terminal against the physical Windows model. These are isolation evidence, not an AutoMLXStudio Chat pass.

## Remote Chat

**FAIL / BLOCKED.** AutoMLXStudio was configured through its UI with `http://192.168.1.10:1234/v1` and remote routing enabled. It displayed `The connection to the remote server was lost` and `Server offline`; discovery and model selection did not complete.

The macOS log shows `Local network prohibited` on `en7` and `NSURLErrorDomain Code=-1009` before any bytes were sent. The permission dialog was answered with **Allow**, and the app was quit and relaunched once, but the process remained prohibited. No permanent System Settings change was made.

Streaming, persistence, model identity in Chat, and Stop/Cancel recovery were not executable. No local fallback was counted.

## Remote Engineering

**FAIL / BLOCKED.** The remote model could not be selected in AutoMLXStudio. `read_file`, `write_file`, approval UI, Allow Once, Deny, post-deny behavior, and continuation were not executed. No fixture was created and no tool action was represented as a pass.

## Remote Benchmark

**FAIL / BLOCKED.** No remote suite could start. Suite loading, requests, grader, progress, completion, persistence, JSON export, Markdown export, and cancellation remain unverified. No score or duration was invented.

## Failure and recovery

- LM Studio load failure: recovered at runtime by loading Qwen 4B with context 8192; subsequent direct inference passed.
- AutoMLXStudio Stop/Cancel recovery: FAIL / NOT EXECUTED because no app generation could start.
- AutoMLXStudio network recovery: FAIL after permission dialog and relaunch.

## Repository Integrity

- Before: **PASS — 108/108**
- After: **PASS — 108/108**
- Manifest: `Validation/V061BenchmarkHarness-20260911/SourceManifest-freeze-final.sha256`

## Evidence

- `SourceIntegrity-Before.log`
- `SourceIntegrity-After.log`
- `Preflight-Environment-And-Connectivity.log`
- `Models.raw.json`
- `App-Launch.log`
- `Mac-Curl.headers`
- `Mac-Curl-Models.json`
- `AutoMLXStudio-UnifiedLog.txt`
- `AutoMLXStudio-Network-Diagnostic.txt`
- `Direct-Chat-Exact.json` and `Direct-Chat-Arithmetic.json` (pre-load HTTP 400)
- `Direct-Chat-Exact-AfterLoad.json`
- `Direct-Chat-Arithmetic-AfterLoad.json`

## Problems discovered

1. AutoMLXStudio is denied local-network access by macOS despite the permission prompt being answered with Allow.
2. LM Studio's default 262144-token context exhausts GPU memory; Qwen 4B works with temporary context 8192.

No corrective source or system-configuration change was made.

## Final Result

`PARTIALLY VERIFIED`

Physical connectivity, model discovery through the raw endpoint, runtime model loading, and direct physical inference are verified. AutoMLXStudio Remote Chat, Engineering, Benchmark, and Stop/recovery are not verified because the application process is blocked by macOS local-network privacy policy.
