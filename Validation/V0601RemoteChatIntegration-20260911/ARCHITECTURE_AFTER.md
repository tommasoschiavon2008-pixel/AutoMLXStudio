# V0.6.0.1 Chat architecture after integration

Ordinary text Chat now has one backend-neutral path:

```text
ChatView
  -> AppState generation ownership
  -> ChatGenerationSession
  -> ModelBackendDispatcher
     -> LocalMLXBackend
     -> RemoteInferenceBackend
```

The conversation persists a `ModelGenerationTarget` containing backend, location (local or remote server UUID), and model ID. This prevents same-name collisions across local models and multiple servers. The picker is grouped by `On this Mac` and each configured server; disabled, missing, removed, or not-yet-discovered saved selections are retained or reported honestly rather than silently replaced.

`ChatGenerationSession` assembles system instruction, exact prior user/assistant turns, and the current user turn once. Optional Project Memory uses the existing project-scoped store and limits. Both local and remote text execute one exact dispatcher route with fallback disabled, so target failure cannot silently move work elsewhere.

`AppState` freezes the selected target and conversation destination for an active request. Conversation switching and model selection are disabled while generating; identity-safe persistence also ensures a late response can update only its originating conversation. Stop cancels the owned task through local or URLSession-backed remote inference, records a cancelled terminal state, unlocks the UI, retains history and selection, and permits a later request.

The normalized result persists visible text, backend-qualified target, provider usage when supplied, duration, finish reason, tool-call count, and time-to-first-token only when genuinely measured. Remote Chat currently uses complete non-streaming delivery and says so in the UI. Unexpected normal-Chat tool calls are preserved at the backend result boundary but rejected explicitly without execution; Engineering remains the only agentic tool workflow.

Image attachments intentionally remain on the established local Vision workflow. Remote attachment support is not claimed.
