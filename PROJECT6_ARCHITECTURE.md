# V0.6 architecture

The Mac owns the application, orchestration, authorizations, workspace, tools, and process lifecycle. Only inference changes location.

```text
AppState → RootView → EngineeringView → EngineeringController
                                    → EngineeringSessionBuilder
                                      ├─ EngineeringAgentEngine
                                      ├─ EngineeringAgentToolRuntimeAdapter
                                      │  → EngineeringToolRuntime → Mac workspace / owned processes
                                      └─ EngineeringAgentModelBackendAdapter
                                         → ModelRouter plan → ModelBackendDispatcher
                                           ├─ LocalMLXBackend → shared ModelResourceManager → MLX
                                           └─ RemoteInferenceBackend → LAN → managed server → LLM

RootView → RemoteModelsView → shared RemoteModelsController
                            ├─ RemoteServerStore → profile JSON + token vault
                            └─ shared RemoteInferenceBackend → health / discovery
```

## Ownership and session assembly

AppState owns one remote store, backend, configuration controller, local backend, approval broker, session builder, and Engineering controller. Local inference reuses the pre-existing resource manager and completion client. Providers capture AppState weakly. Views use the app-owned controllers, so navigation does not create another session. The controller cancels its owned tasks on deinitialization.

EngineeringSessionBuilder captures assignments and discovery records before asynchronous preparation. It validates the primary route, constructs the run-scoped Mac tool runtime and adapter, and supplies a phase-aware model adapter to one bounded engine. Reviewer and Composer routes are resolved only if the selected quality requires them; missing optional quality models degrade the result rather than preventing a valid Fast session.

The controller captures task, quality, remote target, optional memory project, and context budget at Run. Workspace switching is refused while loading or running. Re-entering the page preserves active and completed state. Operational events are streamed to the controller without private reasoning or raw source payloads.

## Local mode

`Engineering → ModelBackendDispatcher → LocalMLXBackend → ModelResourceManager → MLXCompletionClient → local LLM`

Local routing requires an enabled, installed MLX text profile satisfying the logical agent's capabilities. It considers only the preferred assignment and explicitly declared fallbacks. Native tools are not sent to the current plain-text MLX endpoint. The adapter supplies the bounded strict JSON tool/complete protocol and converts prior tool results into untrusted user-context messages.

The full local deterministic E2E includes the production LocalMLXBackend; only physical preparation and final model inference are injected. It does not load a real model.

## Distributed mode

`Engineering on Mac → ModelBackendDispatcher → RemoteInferenceBackend → OpenAI-compatible endpoint → remote LLM`

Remote Models supports manually entered server profiles, credential-free endpoint previews, health, discovery, enable/disable, and per-server operations. No network scan or server installation occurs. Example configuration: HTTP, host `192.168.1.50`, port `1234`, base path `/v1`. LM Studio is one possible server, not a hardcoded dependency.

Discovery establishes identity and availability, not model capability. The user's explicit selected discovered model is allowed to retain unknown text/tool capability metadata. Native support is observed from actual replies; incompatible servers can fail visibly. The configured compatible local Engineering assignment is the explicit recovery route, with actual attempts and fallback shown in activity. Reviewer/Composer continue to use their configured local assignments.

The remote inference actor handles profile validation, tokens at the request boundary, non-streaming chat completion, structured native calls, bounded responses, timeouts, cancellation, and safe errors. Streaming and Ollama-native transport are not claimed as implemented.

## Multi-turn tools

1. The engine sends a prompt and allowed schemas through the model adapter.
2. The selected backend returns a typed tool proposal.
3. The engine enforces allowed names, strict arguments, bounded calls, and loop/iteration policy.
4. The Mac runtime enforces workspace paths and approval before executing locally.
5. A bounded, untrusted tool-result message is returned to the model.
6. Native remote history preserves both assistant `tool_calls` and matching `tool_call_id` results.
7. The loop ends on explicit completion, denial, cancellation, failure, repetition, or the hard turn limit.

A remote server receives selected context and tool results, including source text when a read tool is requested. It receives no bookmark, filesystem handle, shell session, or direct Mac file API. This is controlled data disclosure, not a promise that source content never leaves the Mac.

## Preserved scope

Existing Chat, Voice, model control, Optimize, Benchmark, and Project Memory remain in place. This milestone adds local/remote Engineering, not a replacement remote Chat application. Project Memory remains opt-in, project-isolated, and separate from filesystem authorization. Current sessions/results survive navigation within the running app, not application restart; workspace authorizations and transaction history are persisted.
