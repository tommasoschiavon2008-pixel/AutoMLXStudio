# V0.6.0.1 targeted Chat architecture audit

Audited scope: `ChatView`, `AppState`, conversation persistence, model routing,
the dispatcher, local and remote backends, cancellation, Project Memory context,
and Remote Models state. The wider V0.6 architecture was not re-audited.

## Root cause

`ChatView.send()` calls `AppState.sendChat(_:)`. That method captures the current
conversation and invokes `WorkflowEngine.execute(...)`. Inside
`WorkflowEngine.executeAgent(...)`, local model selection is followed by direct
`ModelResourceManager.prepare(...)` and `LLMCompletionClient.complete(...)`
calls. No Chat-level selected `ModelGenerationTarget` exists, and the shared
`ModelBackendDispatcher` is currently assembled only by
`EngineeringSessionBuilder`. Consequently the normal Chat UI has no remote
target identity and cannot route to `RemoteInferenceBackend`.

## Current flow

```text
ChatView
  -> AppState.sendChat
  -> WorkflowEngine
  -> ModelRouter (local ModelProfile only)
  -> ModelResourceManager
  -> LLMCompletionClient
  -> local MLX server
```

Conversation messages and Project Memory preferences are durable, but the
conversation schema has no backend-qualified Chat model selection. Cancellation
owns one `generationTask`, while conversation selection remains interactable
during generation, so an explicit conversation identity guard is also needed to
prevent a late response from being appended to a different selected chat.

## Required correction

Introduce one backend-neutral Chat session boundary which persists an exact
`ModelGenerationTarget`, builds a route with `ModelRouter`, and executes it
through the shared `ModelBackendDispatcher`. Local and remote choices must feed
the same generation state, history, cancellation, result, and error path. The
existing attachment-aware local Workflow path must remain available until the
text backends expose a common multimodal contract; it must be represented
honestly rather than described as remote support.
