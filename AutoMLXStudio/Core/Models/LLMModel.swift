import Foundation // Supplies Codable support for model registry values.

struct LLMModel: Identifiable, Codable, Equatable { // Describes a local model independently from any one agent.
    let id: String // Stores the identifier sent to the OpenAI-compatible MLX endpoint.
    let name: String // Stores a concise display name derived from the configured identifier.
    let repository: String // Stores the model repository or local model reference.
    let capabilities: Set<ModelCapability> // Declares which agent requirements this model can satisfy.
} // Ends the local model abstraction.
