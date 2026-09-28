import Foundation

/// Export d’une conversation en Markdown.
enum ConversationExporter {
    static func fileName(for conversation: Conversation) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let base = conversation.title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Conversation" : String(base.prefix(80))) + ".md"
    }

    static func markdown(for conversation: Conversation) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        var lines: [String] = ["# \(conversation.title)", ""]
        var meta = "_\(formatter.string(from: conversation.createdAt))"
        if !conversation.model.isEmpty { meta += " · \(conversation.model)" }
        let profile = ResponseProfile.profile(id: conversation.profileID)
        if profile != .balanced { meta += " · profil \(profile.name)" }
        lines.append(meta + "_")
        if !conversation.documents.isEmpty {
            lines.append("")
            lines.append("Documents joints : " + conversation.documents.map(\.name).joined(separator: ", "))
        }

        for message in conversation.messages {
            lines.append("")
            switch message.role {
            case .user:
                lines.append(message.kind == .verification ? "## Vous (demande de vérification)" : "## Vous")
                lines.append("")
                if !message.images.isEmpty {
                    lines.append("_\(message.images.count) image\(message.images.count > 1 ? "s" : "") jointe\(message.images.count > 1 ? "s" : "")_")
                    lines.append("")
                }
                lines.append(message.content)
            case .assistant:
                lines.append("## Assistant" + (message.model.map { " (\($0))" } ?? ""))
                lines.append("")
                let parsed = ThinkingParser.split(message.content)
                let thinking = [message.thinking, parsed.thinking].filter { !$0.isEmpty }.joined(separator: "\n\n")
                if !thinking.isEmpty {
                    lines.append("<details><summary>Réflexion</summary>")
                    lines.append("")
                    lines.append(thinking.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
                    lines.append("")
                    lines.append("</details>")
                    lines.append("")
                }
                lines.append(parsed.answer.isEmpty ? "_(pas de réponse)_" : parsed.answer)
                if !message.sources.isEmpty {
                    lines.append("")
                    lines.append("**Sources**")
                    lines.append("")
                    for source in message.sources {
                        var entry = "- [\(source.tag)] "
                        if let url = source.url {
                            entry += "[\(source.title)](\(url))"
                        } else {
                            entry += source.title
                        }
                        if let detail = source.detail, source.url == nil { entry += " — \(detail)" }
                        lines.append(entry)
                    }
                }
            case .system:
                continue
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
