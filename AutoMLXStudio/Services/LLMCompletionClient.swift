import Foundation // Supplies asynchronous protocol and value-type support for completion requests.

struct LLMConversationMessage: Equatable { // Represents recent conversational context without coupling agents to a view model.
    let role: String // Stores the OpenAI-compatible message role.
    let content: String // Stores the conversational text supplied to the specialist.
} // Ends the model-neutral conversation message.

struct LLMCompletionRequest { // Describes one model inference independently from MLX networking details.
    let serverPort: Int // Identifies the currently running local MLX endpoint.
    let model: LLMModel // Identifies the registered model assigned to the agent.
    let systemPrompt: String // Supplies the selected agent's centralized instructions.
    let history: [LLMConversationMessage] // Supplies only the recent context needed by the current agent.
    let userPrompt: String // Supplies the stage-specific user payload.
    let maxTokens: Int // Limits generation cost and latency for the stage.
} // Ends the generic completion request.

protocol LLMCompleting { // Isolates workflow execution from the concrete local inference transport.
    func complete(_ request: LLMCompletionRequest) async throws -> String // Executes one completion and returns plain assistant content.
} // Ends the clean LLM client interface.

struct MLXCompletionClient: LLMCompleting { // Adapts the existing working MLX service to the agent-facing interface.
    private let service: MLXService // Reuses the single existing service for all network calls.

    init(service: MLXService) { // Injects the current MLX service without starting another server.
        self.service = service // Stores the shared local inference service.
    } // Ends construction of the MLX completion adapter.

    func complete(_ request: LLMCompletionRequest) async throws -> String { // Converts a generic agent request into one MLX chat completion.
        try await service.complete( // Delegates all HTTP behavior to the existing MLX service.
            port: request.serverPort, // Uses the actual configured or automatically selected port.
            model: request.model.id, // Uses the currently configured model identifier.
            systemPrompt: request.systemPrompt, // Sends only the selected agent's central system prompt.
            history: request.history, // Sends the bounded recent history chosen by WorkflowEngine.
            userPrompt: request.userPrompt, // Sends the current stage payload.
            maxTokens: request.maxTokens // Applies the workflow stage token limit.
        ) // Ends delegation to the existing service.
    } // Ends the adapter completion call.
} // Ends the MLX completion client adapter.
