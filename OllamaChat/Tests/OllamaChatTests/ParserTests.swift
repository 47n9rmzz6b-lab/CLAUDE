import XCTest
@testable import OllamaChat

final class MarkdownParserTests: XCTestCase {
    func testParagraphsAndHeadings() {
        let blocks = MarkdownParser.parse("# Titre\n\nPremière ligne\nDeuxième ligne\n\n## Sous-titre")
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Titre"),
            .paragraph("Première ligne\nDeuxième ligne"),
            .heading(level: 2, text: "Sous-titre"),
        ])
    }

    func testHashtagIsNotAHeading() {
        XCTAssertEqual(MarkdownParser.parse("#swift"), [.paragraph("#swift")])
    }

    func testCodeBlock() {
        let blocks = MarkdownParser.parse("Voici :\n```swift\nlet a = 1\n\nprint(a)\n```\nFin")
        XCTAssertEqual(blocks, [
            .paragraph("Voici :"),
            .code(language: "swift", code: "let a = 1\n\nprint(a)"),
            .paragraph("Fin"),
        ])
    }

    func testUnterminatedCodeBlockWhileStreaming() {
        let blocks = MarkdownParser.parse("```python\nprint('a')\nprint(")
        XCTAssertEqual(blocks, [.code(language: "python", code: "print('a')\nprint(")])
    }

    func testIndentedCodeBlockInsideList() {
        let blocks = MarkdownParser.parse("1. Installer :\n   ```sh\n   brew install ollama\n   ```")
        XCTAssertEqual(blocks, [
            .list([MarkdownListItem(ordered: true, marker: "1.", level: 0, text: "Installer :")]),
            .code(language: "sh", code: "brew install ollama"),
        ])
    }

    func testLists() {
        let blocks = MarkdownParser.parse("- un\n- **deux**\n  - imbriqué\n- [x] fait\n\n1. premier\n2) second")
        XCTAssertEqual(blocks, [
            .list([
                MarkdownListItem(ordered: false, marker: "•", level: 0, text: "un"),
                MarkdownListItem(ordered: false, marker: "•", level: 0, text: "**deux**"),
                MarkdownListItem(ordered: false, marker: "•", level: 1, text: "imbriqué"),
                MarkdownListItem(ordered: false, marker: "•", level: 0, text: "☑ fait"),
            ]),
            .list([
                MarkdownListItem(ordered: true, marker: "1.", level: 0, text: "premier"),
                MarkdownListItem(ordered: true, marker: "2)", level: 0, text: "second"),
            ]),
        ])
    }

    func testBoldLineIsNotAListItem() {
        XCTAssertEqual(MarkdownParser.parse("**Important** : lire ceci"), [.paragraph("**Important** : lire ceci")])
    }

    func testListItemContinuation() {
        let blocks = MarkdownParser.parse("- premier point\n  suite du point")
        XCTAssertEqual(blocks, [
            .list([MarkdownListItem(ordered: false, marker: "•", level: 0, text: "premier point\nsuite du point")]),
        ])
    }

    func testTable() {
        let blocks = MarkdownParser.parse("| Modèle | Taille |\n|:---|---:|\n| llama3.2 | 2 Go |\n| qwen3 | 5 Go |\n\nAprès")
        XCTAssertEqual(blocks, [
            .table(header: ["Modèle", "Taille"], rows: [["llama3.2", "2 Go"], ["qwen3", "5 Go"]]),
            .paragraph("Après"),
        ])
    }

    func testQuoteAndRule() {
        let blocks = MarkdownParser.parse("> citation\n> suite\n\n---\n\ntexte")
        XCTAssertEqual(blocks, [.quote("citation\nsuite"), .rule, .paragraph("texte")])
    }
}

final class ThinkingParserTests: XCTestCase {
    func testNoThinking() {
        let result = ThinkingParser.split("Bonjour")
        XCTAssertEqual(result.thinking, "")
        XCTAssertEqual(result.answer, "Bonjour")
    }

    func testClosedThinking() {
        let result = ThinkingParser.split("<think>\nJe réfléchis.\n</think>\n\nRéponse.")
        XCTAssertEqual(result.thinking, "Je réfléchis.")
        XCTAssertEqual(result.answer, "Réponse.")
    }

    func testThinkingInProgress() {
        let result = ThinkingParser.split("<think>Je réfl")
        XCTAssertEqual(result.thinking, "Je réfl")
        XCTAssertEqual(result.answer, "")
    }
}

final class OllamaClientTests: XCTestCase {
    func testAddressNormalization() throws {
        XCTAssertEqual(try OllamaClient(address: "localhost:11434").baseURL.absoluteString, "http://localhost:11434")
        XCTAssertEqual(try OllamaClient(address: " http://192.168.1.20:11434/ ").baseURL.absoluteString, "http://192.168.1.20:11434")
        XCTAssertEqual(try OllamaClient(address: "").baseURL.absoluteString, AppDefaults.serverURL)
    }

    func testChatChunkDecoding() throws {
        let line = #"{"model":"qwen3","message":{"role":"assistant","content":"","thinking":"Hmm"},"done":false}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8))
        XCTAssertEqual(chunk.message?.thinking, "Hmm")
        XCTAssertEqual(chunk.done, false)

        let last = #"{"model":"qwen3","message":{"role":"assistant","content":""},"done":true,"eval_count":120,"eval_duration":2000000000}"#
        let done = try JSONDecoder().decode(ChatChunk.self, from: Data(last.utf8))
        XCTAssertEqual(done.evalCount, 120)
        XCTAssertEqual(done.evalDuration, 2_000_000_000)
    }

    func testModelListDecoding() throws {
        let json = #"{"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","size":2019393189,"digest":"a80c","details":{"family":"llama","parameter_size":"3.2B","quantization_level":"Q4_K_M"}}]}"#
        struct Tags: Decodable { let models: [OllamaModel] }
        let models = try JSONDecoder().decode(Tags.self, from: Data(json.utf8)).models
        XCTAssertEqual(models.first?.name, "llama3.2:latest")
        XCTAssertEqual(models.first?.details?.parameterSize, "3.2B")
    }
}
