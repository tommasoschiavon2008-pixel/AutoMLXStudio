import Foundation // Supplies Codable values, stable UUID identities, URLs, and Sendable Foundation types.

struct UserRequest: Codable, Equatable, Sendable { // Represents one extensible user submission independently from Chat or a model backend.
    let text: String // Stores the optional textual portion supplied by the user.
    let attachments: [UserAttachment] // Stores typed URL-backed attachments without embedding media bytes or AppKit objects.

    init(text: String, attachments: [UserAttachment] = []) { // Keeps text-only construction concise while allowing multimodal requests.
        self.text = text // Preserves the exact user text for routing and workflow execution.
        self.attachments = attachments // Preserves validated attachment values in their original order.
    } // Ends user-request construction.

    var imageAttachments: [ImageAttachment] { // Exposes image inputs without making callers inspect enum cases repeatedly.
        attachments.compactMap { attachment in // Visits each typed attachment while preserving request order.
            guard case let .image(image) = attachment else { return nil } // Ignores non-image attachment kinds safely.
            return image // Returns the URL-backed image metadata for Vision routing or inference.
        } // Ends typed image extraction.
    } // Ends image-attachment access.

    var hasImageAttachment: Bool { // Provides a deterministic Fast Router precedence signal.
        attachments.contains { attachment in // Checks attachment kinds without reading any private file content.
            if case .image = attachment { return true } // Reports the presence of at least one image immediately.
            return false // Continues searching when the current attachment is not an image.
        } // Ends image-presence evaluation.
    } // Ends image-presence access.
} // Ends the extensible user-request value.

enum UserAttachmentKind: String, Codable, CaseIterable, Equatable, Sendable { // Provides stable privacy-safe attachment categories for routing and traces.
    case image // Identifies a validated still-image attachment.
    case audio // Identifies an audio attachment reserved for the Voice workflow.
    case file // Identifies a generic file attachment reserved for later document workflows.
} // Ends attachment-kind definitions.

enum UserAttachment: Codable, Equatable, Sendable, Identifiable { // Stores one typed attachment using Codable associated values and stable identity.
    case image(ImageAttachment) // Carries validated image URL and metadata without raw pixels.
    case audio(AudioAttachment) // Carries audio URL and metadata without raw samples.
    case file(FileAttachment) // Carries a generic file URL and metadata without raw contents.

    var id: UUID { // Exposes the stable identity owned by the associated typed attachment.
        switch self { // Selects identity from the current attachment kind.
        case let .image(attachment): return attachment.id // Returns the image attachment identity.
        case let .audio(attachment): return attachment.id // Returns the audio attachment identity.
        case let .file(attachment): return attachment.id // Returns the generic file attachment identity.
        } // Ends attachment identity selection.
    } // Ends attachment identity access.

    var kind: UserAttachmentKind { // Exposes the attachment category without leaking its URL or contents.
        switch self { // Maps each associated-value case to its stable category.
        case .image: return .image // Classifies image metadata as an image attachment.
        case .audio: return .audio // Classifies audio metadata as an audio attachment.
        case .file: return .file // Classifies generic file metadata as a file attachment.
        } // Ends attachment-kind selection.
    } // Ends attachment-kind access.

    var traceMetadata: AttachmentTraceMetadata { // Produces metadata safe for operational traces without paths, names, or contents.
        switch self { // Selects privacy-safe fields for the current attachment type.
        case let .image(attachment): // Handles validated still-image metadata.
            return AttachmentTraceMetadata( // Creates an image trace record containing only operational facts.
                id: attachment.id, // Correlates the trace record with the request attachment.
                kind: .image, // Records the attachment category.
                contentTypeIdentifier: attachment.contentTypeIdentifier, // Records the detected media type without file contents.
                byteCount: attachment.byteCount, // Records bounded input size for operational diagnostics.
                pixelWidth: attachment.pixelWidth, // Records decoded image width without storing pixels.
                pixelHeight: attachment.pixelHeight, // Records decoded image height without storing pixels.
                durationMilliseconds: nil // Leaves audio-only duration absent for images.
            ) // Ends privacy-safe image trace metadata.
        case let .audio(attachment): // Handles audio attachment metadata.
            return AttachmentTraceMetadata( // Creates an audio trace record containing only operational facts.
                id: attachment.id, // Correlates the trace record with the request attachment.
                kind: .audio, // Records the attachment category.
                contentTypeIdentifier: attachment.contentTypeIdentifier, // Records the declared or detected media type.
                byteCount: attachment.byteCount, // Records the input byte count without storing samples.
                pixelWidth: nil, // Leaves image-only width absent for audio.
                pixelHeight: nil, // Leaves image-only height absent for audio.
                durationMilliseconds: attachment.durationMilliseconds // Records known duration without fabricating unavailable values.
            ) // Ends privacy-safe audio trace metadata.
        case let .file(attachment): // Handles generic file attachment metadata.
            return AttachmentTraceMetadata( // Creates a generic trace record containing only operational facts.
                id: attachment.id, // Correlates the trace record with the request attachment.
                kind: .file, // Records the attachment category.
                contentTypeIdentifier: attachment.contentTypeIdentifier, // Records an optional declared or detected content type.
                byteCount: attachment.byteCount, // Records the input byte count without storing file contents.
                pixelWidth: nil, // Leaves image-only width absent for generic files.
                pixelHeight: nil, // Leaves image-only height absent for generic files.
                durationMilliseconds: nil // Leaves audio-only duration absent for generic files.
            ) // Ends privacy-safe generic trace metadata.
        } // Ends privacy-safe metadata selection.
    } // Ends trace-metadata access.
} // Ends typed user-attachment definitions.

struct ImageAttachment: Identifiable, Codable, Equatable, Sendable { // Stores a validated image reference and deterministic metadata without AppKit values.
    let id: UUID // Provides stable request, preview, removal, and trace identity.
    let url: URL // References the local image without copying or embedding its bytes.
    let originalFilename: String // Preserves a user-facing filename for Chat UI only, not privacy-safe traces.
    let contentTypeIdentifier: String // Stores the content type detected from the actual image source.
    let byteCount: UInt64 // Stores the validated regular-file size.
    let pixelWidth: Int // Stores the decoded image width in pixels.
    let pixelHeight: Int // Stores the decoded image height in pixels.

    init(id: UUID = UUID(), url: URL, originalFilename: String, contentTypeIdentifier: String, byteCount: UInt64, pixelWidth: Int, pixelHeight: Int) { // Creates complete validated image metadata.
        self.id = id // Stores the stable attachment identity.
        self.url = url // Stores the standardized local file reference.
        self.originalFilename = originalFilename // Stores the filename intended for visible attachment UI.
        self.contentTypeIdentifier = contentTypeIdentifier // Stores the detected supported image type.
        self.byteCount = byteCount // Stores the validated bounded size.
        self.pixelWidth = pixelWidth // Stores the positive decoded width.
        self.pixelHeight = pixelHeight // Stores the positive decoded height.
    } // Ends image-attachment construction.
} // Ends image-attachment metadata.

struct AudioAttachment: Identifiable, Codable, Equatable, Sendable { // Stores future Voice input metadata without raw audio samples.
    let id: UUID // Provides stable request, UI, and trace identity.
    let url: URL // References the local audio resource without embedding bytes.
    let originalFilename: String // Preserves a visible filename while traces omit it for privacy.
    let contentTypeIdentifier: String? // Stores a media type only when validation can determine it.
    let byteCount: UInt64 // Stores the known input size.
    let durationMilliseconds: Int? // Stores measured duration only when a backend provides it.

    init(id: UUID = UUID(), url: URL, originalFilename: String, contentTypeIdentifier: String?, byteCount: UInt64, durationMilliseconds: Int? = nil) { // Creates future-ready audio metadata.
        self.id = id // Stores the stable attachment identity.
        self.url = url // Stores the local audio reference.
        self.originalFilename = originalFilename // Stores the visible user-facing filename.
        self.contentTypeIdentifier = contentTypeIdentifier // Stores optional type metadata without inventing a value.
        self.byteCount = byteCount // Stores the known file size.
        self.durationMilliseconds = durationMilliseconds // Stores optional measured duration.
    } // Ends audio-attachment construction.
} // Ends audio-attachment metadata.

struct FileAttachment: Identifiable, Codable, Equatable, Sendable { // Stores a future generic file reference without loading its contents into workflow state.
    let id: UUID // Provides stable request, UI, and trace identity.
    let url: URL // References the local file without copying or embedding its bytes.
    let originalFilename: String // Preserves a visible filename while privacy-safe traces omit it.
    let contentTypeIdentifier: String? // Stores a type only when deterministic validation can supply one.
    let byteCount: UInt64 // Stores the known regular-file size.

    init(id: UUID = UUID(), url: URL, originalFilename: String, contentTypeIdentifier: String?, byteCount: UInt64) { // Creates future-ready generic file metadata.
        self.id = id // Stores the stable attachment identity.
        self.url = url // Stores the local file reference.
        self.originalFilename = originalFilename // Stores the visible user-facing filename.
        self.contentTypeIdentifier = contentTypeIdentifier // Stores optional type metadata without fabrication.
        self.byteCount = byteCount // Stores the known input size.
    } // Ends generic file-attachment construction.
} // Ends generic file-attachment metadata.

struct AttachmentTraceMetadata: Identifiable, Codable, Equatable, Sendable { // Stores privacy-safe operational attachment facts for workflow traces.
    let id: UUID // Correlates the metadata with one request attachment without revealing its location.
    let kind: UserAttachmentKind // Records only the stable attachment category.
    let contentTypeIdentifier: String? // Records media type when known without storing file contents.
    let byteCount: UInt64 // Records input size for validation and performance diagnostics.
    let pixelWidth: Int? // Records image width only for validated images.
    let pixelHeight: Int? // Records image height only for validated images.
    let durationMilliseconds: Int? // Records media duration only when deterministically measured.
} // Ends privacy-safe attachment trace metadata.
