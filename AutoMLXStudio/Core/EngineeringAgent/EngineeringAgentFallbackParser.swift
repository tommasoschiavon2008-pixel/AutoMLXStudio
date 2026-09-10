import Foundation // Supplies bounded UTF-8 conversion and strict JSON object parsing.

enum EngineeringAgentFallbackAction: Equatable, Sendable { // Represents the only actions accepted from the non-native fallback protocol.
    case toolCall(EngineeringAgentToolCall) // Carries one exact strict-JSON tool proposal.
    case complete(String) // Carries one exact strict-JSON completion summary.
} // Ends strict fallback actions.

enum EngineeringAgentFallbackParserError: LocalizedError, Equatable, Sendable { // Describes every deterministic fallback or argument rejection.
    case empty // Indicates that the model returned no structured fallback content.
    case tooLarge // Indicates that the envelope or argument object exceeded its hard byte bound.
    case invalidJSON // Indicates that the response was not one standalone JSON object.
    case invalidEnvelope // Indicates that required keys, key types, or the action discriminator were invalid.
    case invalidArguments // Indicates that tool arguments were not one standalone JSON object.

    var errorDescription: String? { // Supplies concise repair-safe diagnostics without echoing model content.
        switch self { // Selects a bounded diagnostic for the concrete validation failure.
        case .empty: return "The structured response was empty." // Describes absent structured content.
        case .tooLarge: return "The structured response exceeded the 65,536-byte safety limit." // Describes the fixed fallback bound.
        case .invalidJSON: return "The response was not one standalone JSON object." // Describes natural-language or malformed JSON rejection.
        case .invalidEnvelope: return "The JSON envelope did not match the exact tool_call or complete schema." // Describes strict schema rejection.
        case .invalidArguments: return "Tool arguments must be one bounded JSON object." // Describes malformed argument rejection.
        } // Ends parser-error description selection.
    } // Ends the localized parser diagnostic.
} // Ends strict parser errors.

enum EngineeringAgentFallbackParser { // Implements the bounded fallback without interpreting arbitrary natural language.
    static let maximumByteCount = 65_536 // Caps both fallback envelopes and native tool argument objects at sixty-four KiB.

    static func parse(_ source: String) throws -> EngineeringAgentFallbackAction { // Parses exactly one supported JSON envelope.
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines) // Removes harmless surrounding whitespace without accepting prose.
        guard !trimmed.isEmpty else { throw EngineeringAgentFallbackParserError.empty } // Rejects an absent action deterministically.
        guard trimmed.utf8.count <= maximumByteCount else { throw EngineeringAgentFallbackParserError.tooLarge } // Enforces the hard transport-independent input bound.
        guard trimmed.first == "{", trimmed.last == "}" else { throw EngineeringAgentFallbackParserError.invalidJSON } // Rejects Markdown fences and natural-language prefixes or suffixes.
        guard let data = trimmed.data(using: .utf8) else { throw EngineeringAgentFallbackParserError.invalidJSON } // Converts only valid Swift UTF-8 text to JSON bytes.
        let object: Any // Declares the Foundation JSON value before checking its exact top-level type.
        do { // Attempts strict Foundation JSON decoding.
            object = try JSONSerialization.jsonObject(with: data, options: []) // Parses one complete JSON value without fragment support.
        } catch { // Maps provider syntax details to one bounded public diagnostic.
            throw EngineeringAgentFallbackParserError.invalidJSON // Rejects malformed JSON without retaining its contents.
        } // Ends JSON syntax validation.
        guard let envelope = object as? [String: Any], let type = envelope["type"] as? String else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Requires one keyed object with a string discriminator.

        switch type { // Selects one of the only two supported structured actions.
        case "tool_call": // Handles one strict tool-call envelope.
            let requiredKeys: Set<String> = ["type", "id", "name", "arguments"] // Declares the exact accepted tool-call key set.
            guard Set(envelope.keys) == requiredKeys else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Rejects omitted and unrecognized fields rather than guessing intent.
            guard let id = envelope["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 256 else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Requires one bounded non-empty call identity.
            guard let name = envelope["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 256 else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Requires one bounded non-empty registered name candidate.
            guard let arguments = envelope["arguments"] as? [String: Any] else { throw EngineeringAgentFallbackParserError.invalidArguments } // Requires an object rather than a string, list, scalar, or null.
            let argumentsData: Data // Declares canonical argument bytes used for deterministic loop comparison.
            do { // Attempts canonical JSON serialization of the validated object.
                argumentsData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes]) // Sorts keys so semantically identical objects share one signature.
            } catch { // Maps unsupported Foundation values to the strict argument error.
                throw EngineeringAgentFallbackParserError.invalidArguments // Rejects arguments that cannot be represented as JSON.
            } // Ends canonical argument serialization.
            guard argumentsData.count <= maximumByteCount else { throw EngineeringAgentFallbackParserError.tooLarge } // Applies the same hard bound to the extracted argument object.
            guard let argumentsJSON = String(data: argumentsData, encoding: .utf8) else { throw EngineeringAgentFallbackParserError.invalidArguments } // Requires reversible UTF-8 canonical arguments.
            return .toolCall(EngineeringAgentToolCall(id: id, name: name, argumentsJSON: argumentsJSON, origin: .strictJSONFallback)) // Returns one typed proposal for normal engine permission checks.
        case "complete": // Handles one strict completion envelope.
            let requiredKeys: Set<String> = ["type", "summary"] // Declares the exact accepted completion key set.
            guard Set(envelope.keys) == requiredKeys else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Rejects extra authority, verification, or command fields.
            guard let summary = envelope["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngineeringAgentFallbackParserError.invalidEnvelope } // Requires a useful non-empty user-facing summary.
            return .complete(summary) // Returns text only and never accepts a model-supplied verification claim.
        default: // Handles every unsupported action discriminator.
            throw EngineeringAgentFallbackParserError.invalidEnvelope // Rejects unknown or provider-invented action types.
        } // Ends strict action selection.
    } // Ends strict fallback parsing.

    static func canonicalArguments(from source: String) throws -> String { // Validates and canonicalizes native-call arguments before runtime dispatch.
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines) // Removes harmless whitespace without changing string values inside JSON.
        guard !trimmed.isEmpty else { throw EngineeringAgentFallbackParserError.invalidArguments } // Rejects absent native arguments.
        guard trimmed.utf8.count <= maximumByteCount else { throw EngineeringAgentFallbackParserError.tooLarge } // Enforces the same fixed argument safety bound.
        guard trimmed.first == "{", trimmed.last == "}" else { throw EngineeringAgentFallbackParserError.invalidArguments } // Requires one standalone JSON object rather than fragments or prose.
        guard let data = trimmed.data(using: .utf8) else { throw EngineeringAgentFallbackParserError.invalidArguments } // Converts valid Swift text to UTF-8 bytes.
        let object: Any // Declares the decoded JSON value before enforcing an object top level.
        do { // Attempts strict JSON syntax decoding.
            object = try JSONSerialization.jsonObject(with: data, options: []) // Parses one complete JSON value without fragments.
        } catch { // Maps syntax details to a bounded repair diagnostic.
            throw EngineeringAgentFallbackParserError.invalidArguments // Rejects malformed native arguments without echoing them.
        } // Ends native argument syntax validation.
        guard let arguments = object as? [String: Any] else { throw EngineeringAgentFallbackParserError.invalidArguments } // Rejects array, scalar, and null arguments.
        let canonicalData: Data // Declares sorted canonical bytes for deterministic loop detection.
        do { // Attempts canonical reserialization of the validated object.
            canonicalData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes]) // Produces stable object-key ordering.
        } catch { // Maps impossible or unsupported values to one strict error.
            throw EngineeringAgentFallbackParserError.invalidArguments // Rejects values that cannot be represented safely.
        } // Ends canonical native argument serialization.
        guard canonicalData.count <= maximumByteCount else { throw EngineeringAgentFallbackParserError.tooLarge } // Reapplies the byte bound after canonicalization.
        guard let canonical = String(data: canonicalData, encoding: .utf8) else { throw EngineeringAgentFallbackParserError.invalidArguments } // Requires reversible canonical UTF-8.
        return canonical // Returns stable validated arguments for the runtime and repetition tracker.
    } // Ends native argument canonicalization.
} // Ends the strict fallback and argument parser.
