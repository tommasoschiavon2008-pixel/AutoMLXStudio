import Foundation // Supplies read-only filesystem metadata, URLs, and localized validation errors.
import ImageIO // Supplies content-based image type inspection, properties, and deterministic decoding.
import UniformTypeIdentifiers // Supplies supported PNG, JPEG, and HEIC type definitions.

struct AttachmentValidationConfiguration: Codable, Equatable, Sendable { // Stores explicit bounded image validation policy independently from the UI.
    let maximumImageBytes: UInt64 // Limits input size before ImageIO parses or decodes the image.

    init(maximumImageBytes: UInt64 = 25 * 1_024 * 1_024) { // Uses a conservative 25 MiB local-image default while allowing tests or settings to override it.
        self.maximumImageBytes = maximumImageBytes // Stores the exact inclusive byte limit.
    } // Ends validation-configuration construction.
} // Ends attachment validation configuration.

struct ImageAttachmentValidationResult: Codable, Equatable, Sendable { // Returns the validated attachment plus nonfatal structured diagnostics.
    let attachment: ImageAttachment // Contains the standardized URL and content-derived image metadata.
    let warnings: [String] // Carries bounded nonfatal diagnostics without changing attachment validity.
} // Ends structured image validation result.

enum AttachmentValidationError: LocalizedError, Equatable, Sendable { // Defines controlled rejection reasons suitable for Chat and tests.
    case fileMissing // Indicates that the selected URL no longer resolves to a filesystem item.
    case notRegularFile // Indicates that the selected item is a directory, package, or other non-regular resource.
    case unreadableFile // Indicates that the process cannot read the selected local file.
    case fileTooLarge(actualBytes: UInt64, maximumBytes: UInt64) // Indicates that the file exceeds the configured safe parsing limit.
    case unsupportedImageType(String?) // Indicates that content inspection did not find PNG, JPEG, or HEIC data.
    case invalidImage // Indicates that ImageIO could not parse and decode the selected content.
    case invalidDimensions // Indicates that decoded width or height metadata is absent or nonpositive.

    var errorDescription: String? { // Produces clear controlled UI messages without exposing private filesystem paths.
        switch self { // Selects the message for the exact deterministic rejection reason.
        case .fileMissing: return "The selected image no longer exists." // Explains a stale picker or drag-and-drop URL.
        case .notRegularFile: return "Select a regular PNG, JPEG, or HEIC image file." // Rejects folders and non-file resources.
        case .unreadableFile: return "The selected image cannot be read with the current file permissions." // Explains an inaccessible local resource.
        case let .fileTooLarge(actualBytes, maximumBytes): return "The selected image is too large (\(Self.megabytes(actualBytes)) MB). The limit is \(Self.megabytes(maximumBytes)) MB." // Reports actual and configured bounded sizes.
        case let .unsupportedImageType(identifier): return "Unsupported image format\(identifier.map { ": \($0)" } ?? ""). Select a PNG, JPEG, or HEIC image." // Reports detected type when available.
        case .invalidImage: return "The selected file could not be decoded as a valid image." // Rejects corrupt data and extension spoofing.
        case .invalidDimensions: return "The selected image does not contain valid pixel dimensions." // Rejects unusable decoded geometry.
        } // Ends validation-error message selection.
    } // Ends localized validation-error access.

    private static func megabytes(_ bytes: UInt64) -> String { // Formats byte limits compactly without filesystem or content disclosure.
        String(format: "%.1f", Double(bytes) / 1_048_576) // Converts bytes to binary megabytes with one decimal place.
    } // Ends byte-count formatting.
} // Ends controlled attachment validation errors.

enum AttachmentValidationService { // Performs deterministic read-only validation before an image enters request state.
    static func validateImage( // Validates one local image using actual content rather than trusting its extension.
        at sourceURL: URL, // Accepts a picker or drag-and-drop file URL.
        id: UUID = UUID(), // Allows callers to retain stable identity across deliberate revalidation.
        configuration: AttachmentValidationConfiguration = AttachmentValidationConfiguration(), // Applies the shared bounded default unless explicitly overridden.
        fileManager: FileManager = .default // Allows deterministic filesystem tests without global mutation.
    ) throws -> ImageAttachmentValidationResult { // Returns complete validated metadata or one controlled rejection.
        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource() // Opens picker-granted access when the URL requires security scope.
        defer { if didAccessSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } } // Releases only access started by this validation call.
        let fileURL = sourceURL.standardizedFileURL // Normalizes equivalent local path components without changing the target.
        var isDirectory: ObjCBool = false // Receives directory identity from the read-only existence check.
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { throw AttachmentValidationError.fileMissing } // Rejects stale or nonexistent URLs before metadata access.
        guard !isDirectory.boolValue else { throw AttachmentValidationError.notRegularFile } // Rejects directories before ImageIO inspection.
        let resourceValues: URLResourceValues // Declares the regular-file and byte-size metadata read atomically from the URL.
        do { // Attempts read-only filesystem metadata access.
            resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) // Reads only values required for safe preflight validation.
        } catch { // Converts metadata failures into a stable privacy-safe error.
            throw AttachmentValidationError.unreadableFile // Avoids exposing a private local path or system error string.
        } // Ends filesystem metadata recovery.
        guard resourceValues.isRegularFile == true else { throw AttachmentValidationError.notRegularFile } // Rejects symbolic special resources, sockets, and packages that are not regular files.
        guard fileManager.isReadableFile(atPath: fileURL.path) else { throw AttachmentValidationError.unreadableFile } // Confirms current process read permission before ImageIO access.
        let byteCount = UInt64(max(resourceValues.fileSize ?? 0, 0)) // Converts the nonnegative filesystem size into stable trace metadata.
        guard byteCount <= configuration.maximumImageBytes else { throw AttachmentValidationError.fileTooLarge(actualBytes: byteCount, maximumBytes: configuration.maximumImageBytes) } // Rejects oversized data before parsing or decoding.
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { throw AttachmentValidationError.invalidImage } // Parses actual file content instead of trusting the extension.
        guard CGImageSourceGetCount(source) > 0 else { throw AttachmentValidationError.invalidImage } // Requires at least one decodable image frame.
        let detectedIdentifier = CGImageSourceGetType(source).map { $0 as String } // Reads the content-derived Uniform Type Identifier when ImageIO provides it.
        guard let detectedIdentifier, let detectedType = UTType(detectedIdentifier), isSupportedImageType(detectedType) else { throw AttachmentValidationError.unsupportedImageType(detectedIdentifier) } // Accepts only PNG, JPEG, or HEIC content.
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { throw AttachmentValidationError.invalidDimensions } // Reads first-frame geometry without storing image contents.
        let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0 // Extracts positive pixel width from ImageIO metadata.
        let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0 // Extracts positive pixel height from ImageIO metadata.
        guard pixelWidth > 0, pixelHeight > 0 else { throw AttachmentValidationError.invalidDimensions } // Rejects malformed or unusable geometry.
        let decodeOptions: [CFString: Any] = [ // Builds a bounded thumbnail decode that proves pixel data is readable without retaining full resolution.
            kCGImageSourceCreateThumbnailFromImageAlways: true, // Forces ImageIO to decode source pixels into a thumbnail.
            kCGImageSourceThumbnailMaxPixelSize: 64, // Bounds the validation decode to a small deterministic surface.
            kCGImageSourceCreateThumbnailWithTransform: true // Applies embedded orientation during validation decoding.
        ] // Ends bounded decode options.
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) != nil else { throw AttachmentValidationError.invalidImage } // Rejects corrupt or spoofed content that metadata parsing alone cannot decode.
        let attachment = ImageAttachment( // Creates the core URL-backed value only after every validation check passes.
            id: id, // Preserves caller-provided or newly generated stable identity.
            url: fileURL, // Stores the standardized local reference without copying bytes.
            originalFilename: fileURL.lastPathComponent, // Stores visible UI metadata outside privacy-safe trace conversion.
            contentTypeIdentifier: detectedType.identifier, // Stores the actual supported content type detected by ImageIO.
            byteCount: byteCount, // Stores the validated bounded regular-file size.
            pixelWidth: pixelWidth, // Stores content-derived first-frame width.
            pixelHeight: pixelHeight // Stores content-derived first-frame height.
        ) // Ends validated image attachment creation.
        return ImageAttachmentValidationResult(attachment: attachment, warnings: []) // Returns structured success without fabricating nonfatal diagnostics.
    } // Ends image validation.

    private static func isSupportedImageType(_ type: UTType) -> Bool { // Applies one explicit content-type allowlist shared by picker and drag/drop paths.
        type == .png || type == .jpeg || type == .heic // Accepts only the requested common still-image formats.
    } // Ends supported-image type evaluation.
} // Ends the read-only attachment validation service.
