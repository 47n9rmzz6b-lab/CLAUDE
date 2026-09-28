import Foundation

struct MarkdownListItem: Hashable {
    var ordered: Bool
    var marker: String
    var level: Int
    var text: String
}

enum MarkdownBlock: Hashable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String, code: String)
    case list([MarkdownListItem])
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
}

/// Découpe une réponse Markdown en blocs (titres, listes, code, tableaux…).
/// La mise en forme à l’intérieur des blocs (gras, italique, liens, `code`) est
/// confiée à `AttributedString(markdown:)`. Un bloc de code non refermé, fréquent
/// pendant l’affichage progressif, est traité comme s’il se terminait à la fin du texte.
enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var list: [MarkdownListItem] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote.removeAll()
            }
            if !list.isEmpty {
                blocks.append(.list(list))
                list.removeAll()
            }
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceMarker(trimmed) {
                flush()
                let indentation = line.prefix(while: { $0 == " " }).count
                let language = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(dropLeadingSpaces(lines[index], upTo: indentation))
                    index += 1
                }
                blocks.append(.code(language: language, code: code.joined(separator: "\n")))
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }

            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                index += 1
                continue
            }

            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flush()
                let header = cells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.contains("|") else { break }
                    rows.append(cells(row))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !list.isEmpty { flush() }
                var content = trimmed.dropFirst()
                if content.hasPrefix(" ") { content = content.dropFirst() }
                quote.append(String(content))
                index += 1
                continue
            }

            if let item = listItem(line) {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                list.append(item)
                index += 1
                continue
            }

            // Ligne de texte qui suit directement un élément de liste ou une citation : elle en fait partie.
            if !list.isEmpty {
                list[list.count - 1].text += "\n" + trimmed
            } else if !quote.isEmpty {
                quote.append(trimmed)
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flush()
        return blocks
    }

    private static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func dropLeadingSpaces(_ line: String, upTo count: Int) -> String {
        guard count > 0 else { return line }
        let spaces = min(count, line.prefix(while: { $0 == " " }).count)
        return String(line.dropFirst(spaces))
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|:- \t".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var content = Substring(line)
        if content.hasPrefix("|") { content = content.dropFirst() }
        if content.hasSuffix("|") { content = content.dropLast() }
        return content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        var indentation = 0
        for character in line {
            if character == " " {
                indentation += 1
            } else if character == "\t" {
                indentation += 4
            } else {
                break
            }
        }
        let content = line.drop(while: { $0 == " " || $0 == "\t" })
        let level = min(indentation / 2, 4)

        if let first = content.first, "-*+".contains(first), content.dropFirst().hasPrefix(" ") {
            var text = content.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[ ] ") {
                text = "☐ " + text.dropFirst(4)
            } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                text = "☑ " + text.dropFirst(4)
            }
            return MarkdownListItem(ordered: false, marker: "•", level: level, text: text)
        }

        let digits = content.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = content.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")", rest.dropFirst().hasPrefix(" ") else {
            return nil
        }
        return MarkdownListItem(
            ordered: true,
            marker: String(digits) + String(delimiter),
            level: level,
            text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        )
    }
}
