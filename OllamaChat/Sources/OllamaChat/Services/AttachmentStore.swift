import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fichiers joints aux conversations, rangés dans « Application Support/OllamaChat/attachments » :
/// images (réduites et converties en JPEG) et index des documents.
final class AttachmentStore: @unchecked Sendable {
    static let shared = AttachmentStore()

    enum AttachmentError: LocalizedError {
        case unreadableImage(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage(let name): return "Impossible de lire l’image « \(name) »."
            }
        }
    }

    /// Côté le plus long des images envoyées aux modèles de vision.
    static let maxImageSide = 1568

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? AppPaths.support.appending(path: "attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: - Images

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    /// Copie une image dans le dossier des pièces jointes et renvoie son nom de fichier.
    func importImage(from url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AttachmentError.unreadableImage(url.lastPathComponent)
        }
        return try importImage(source: source, name: url.lastPathComponent)
    }

    /// Image collée ou déposée sous forme de données.
    func importImage(data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AttachmentError.unreadableImage("image collée")
        }
        return try importImage(source: source, name: "image collée")
    }

    private func importImage(source: CGImageSource, name: String) throws -> String {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxImageSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AttachmentError.unreadableImage(name)
        }
        let fileName = UUID().uuidString + ".jpg"
        let destinationURL = url(for: fileName)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AttachmentError.unreadableImage(name)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AttachmentError.unreadableImage(name)
        }
        return fileName
    }

    func base64(for name: String) -> String? {
        try? Data(contentsOf: url(for: name)).base64EncodedString()
    }

    func image(named name: String) -> NSImage? {
        NSImage(contentsOf: url(for: name))
    }

    // MARK: - Documents

    func documentIndexURL(for id: UUID) -> URL {
        url(for: "\(id.uuidString).document.json")
    }

    func save(_ index: DocumentIndex, for id: UUID) throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: documentIndexURL(for: id), options: .atomic)
    }

    func loadIndex(for id: UUID) -> DocumentIndex? {
        guard let data = try? Data(contentsOf: documentIndexURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(DocumentIndex.self, from: data)
    }

    // MARK: - Nettoyage

    func removeDocument(_ id: UUID) {
        try? FileManager.default.removeItem(at: documentIndexURL(for: id))
    }

    func removeFiles(of conversation: Conversation) {
        for message in conversation.messages {
            for name in message.images {
                try? FileManager.default.removeItem(at: url(for: name))
            }
        }
        for document in conversation.documents {
            removeDocument(document.id)
        }
    }
}
