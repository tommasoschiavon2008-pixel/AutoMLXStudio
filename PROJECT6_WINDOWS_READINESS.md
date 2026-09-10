# Windows remote readiness

Software integration is implemented and deterministically tested. **PHYSICALLY VERIFIED: NO — PENDING PHYSICAL VALIDATION.** No real Windows host or LAN inference server was available/used during this run.

The Mac continues to own UI, session orchestration, project memory selection, filesystem, tools, approval, and process execution. The Windows machine supplies inference only. LM Studio is one possible OpenAI-compatible server; no provider-specific API is required beyond the supported OpenAI-compatible endpoints and native tool-call contract.

## Prepare a real test

- On Windows, run a user-managed OpenAI-compatible server and a model suitable for coding and native tools. Select the model explicitly in that server.
- Bind it to the intended private interface and port. Restrict the firewall to the trusted Mac/private network. Do not expose an unauthenticated inference endpoint to the public Internet.
- Configure authentication if supported. Enter the bearer token in the Mac app's credential control; it belongs in Keychain, not screenshots, logs, source files, or profile JSON.
- Add the endpoint in Remote Models. For `http://192.168.1.50:1234/v1`, enter host `192.168.1.50`, port `1234`, HTTP, and `/v1` separately. Replace the example address with the actual Windows host.
- Review the LAN HTTP warning. HTTP is cleartext, including selected source context; prefer a trusted private route or TLS where available.
- Use a disposable Mac workspace with a small known bug and independent test. Start with Fast to isolate remote primary inference from local Reviewer/Composer stages.

## Physical acceptance checklist

Record date, Mac/Windows versions, server/version, model identifier, endpoint scheme/port, and sanitized result for each row. Never record a token.

| Check | Required real observation | Status |
|---|---|---|
| Health | Mac receives a compatible API response from the Windows host | PENDING |
| Discovery | `/v1/models` returns the selected Windows model identity | PENDING |
| Generation | A simple text request receives the selected model's answer | PENDING |
| Multi-turn | The next request uses the prior conversation correctly | PENDING |
| Cancellation | Stop ends the Mac-owned inference request promptly; unrelated processes remain running | PENDING |
| Timeout | An unreachable or deliberately delayed test endpoint produces a bounded timeout, without a false success | PENDING |
| Native tools | Windows returns a valid call; the Mac executes it after policy checks | PENDING |
| Correlation | The next Windows request contains the assistant call and its matching Mac tool result | PENDING |
| Full Engineering | Inspect → approve edit → real test → verify completes in the disposable Mac workspace | PENDING |
| Deny | Denying the proposed edit leaves the file unchanged and ends with permission denied | PENDING |
| Locality | File changes/processes occur on the Mac; Windows has no direct filesystem access to that workspace | PENDING |
| Fallback | A controlled remote failure either uses only an explicitly compatible local assignment, visibly, or reports failure | PENDING |

Deterministic URLProtocol tests already cover real request serialization/parsing, discovery, native multi-turn correlation, and Mac tool execution. They deliberately open no network connection, so they cannot validate firewall rules, server-specific model behavior, real latency, or Windows GPU/VRAM capacity.

On a native-tool incompatibility, retain the safe failure trace, verify the server/model's actual tool support, or use the local strict-JSON route. Do not relabel discovery's unknown capabilities as supported to force a pass.
