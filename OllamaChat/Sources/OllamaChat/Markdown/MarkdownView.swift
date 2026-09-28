import SwiftUI

/// Affiche une réponse Markdown : titres, listes, citations, tableaux et blocs de code avec bouton « Copier ».
struct MarkdownView: View {
    let text: String
    var serif = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, serif: serif)
            }
        }
        .textSelection(.enabled)
    }
}

enum MarkdownInline {
    /// Gras, italique, liens et `code` à l’intérieur d’un bloc.
    static func render(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var result = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }
        let codeRanges = result.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        let codeBackground: Color = Theme.inlineCodeBackground
        for range in codeRanges {
            result[range].backgroundColor = codeBackground
        }
        return result
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let serif: Bool

    private var design: Font.Design { serif ? .serif : .default }
    private var bodyFont: Font { .system(size: 15, design: design) }

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(MarkdownInline.render(text))
                .font(bodyFont)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let text):
            Text(MarkdownInline.render(text))
                .font(.system(size: headingSize(level), weight: .semibold, design: design))
                .padding(.top, level <= 2 ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.ordered ? item.marker : bullet(for: item.level))
                            .font(bodyFont)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: item.ordered ? 18 : 10, alignment: .trailing)
                        Text(MarkdownInline.render(item.text))
                            .font(bodyFont)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 20)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 3)
                Text(MarkdownInline.render(text))
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows, font: .system(size: 13.5, design: design))

        case .rule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 15
        }
    }

    private func bullet(for level: Int) -> String {
        switch level {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Pasteboard.copy(code)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.codeHeader)

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }
}

private struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]
    let font: Font

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                ForEach(0..<columnCount, id: \.self) { column in
                    Text(MarkdownInline.render(cell(header, column)))
                        .fontWeight(.semibold)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(MarkdownInline.render(cell(row, column)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(font)
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }

    private func cell(_ row: [String], _ column: Int) -> String {
        row.indices.contains(column) ? row[column] : ""
    }
}
