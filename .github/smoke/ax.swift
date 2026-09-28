// Outil de test (temporaire) : arbre d’accessibilité d’Ollama Chat.
//   ax dump                      toute l’arborescence (rôle, libellés, position)
//   ax find <texte> [rôle]       éléments correspondants (code de sortie 1 si aucun)
//   ax click <texte> [rôle] [n]  clic de souris au centre du n-ième élément trouvé
//   ax press <texte> [rôle] [n]  action AXPress
//   ax wait <texte> [secondes]   attend qu’un élément apparaisse
//   ax close                     ferme les fenêtres choisies par AX_WINDOW
//   ax focused                   élément qui a le focus clavier
//   ax allow                     valide les alertes système (réseau local, micro…) des autres processus
// <texte> : partie d’un libellé, sans tenir compte des accents ni de la casse ; « =texte » : libellé exact.
// Rôle « - » : tous les rôles. n < 0 : en partant de la fin.
// AX_WINDOW=<texte> : seulement les fenêtres dont le titre ou l’identifiant contient ce texte.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)

struct Node {
    let element: AXUIElement
    let depth: Int
    let role: String
    let labels: [String]
    let frame: CGRect?
    var label: String { labels.joined(separator: " | ") }
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, "AXPosition"), let size = attribute(element, "AXSize"),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: origin, size: extent)
}

func collect(_ element: AXUIElement, depth: Int, into nodes: inout [Node]) {
    let role = text(element, "AXRole") ?? "?"
    let labels = ["AXTitle", "AXDescription", "AXHelp", "AXValue", "AXIdentifier"]
        .compactMap { text(element, $0) }
        .map { $0.replacingOccurrences(of: "\n", with: " ⏎ ") }
        .filter { !$0.isEmpty }
    nodes.append(Node(element: element, depth: depth, role: role, labels: labels, frame: frame(of: element)))
    guard depth < 80, let children = attribute(element, "AXChildren") as? [AXUIElement] else { return }
    for child in children {
        collect(child, depth: depth + 1, into: &nodes)
    }
}

func appElement() -> AXUIElement? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ollamachat.desktop").first else {
        print("Ollama Chat ne tourne pas")
        return nil
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 3)
    return root
}

func windowMatches(_ window: AXUIElement, _ filter: String) -> Bool {
    let names = [text(window, "AXTitle") ?? "", text(window, "AXIdentifier") ?? ""]
    return names.contains { $0.localizedCaseInsensitiveContains(filter) }
}

func allNodes() -> [Node] {
    guard let root = appElement() else { return [] }
    let filter = ProcessInfo.processInfo.environment["AX_WINDOW"] ?? ""
    var result: [Node] = []
    for child in attribute(root, "AXChildren") as? [AXUIElement] ?? [] {
        let role = text(child, "AXRole") ?? ""
        if role == "AXMenuBar" { continue }
        if !filter.isEmpty, role == "AXWindow", !windowMatches(child, filter) { continue }
        collect(child, depth: 0, into: &result)
    }
    return result
}

let containers: Set<String> = [
    "AXWindow", "AXApplication", "AXGroup", "AXScrollArea", "AXSplitGroup", "AXToolbar", "AXLayoutArea",
    "AXSheet", "AXList", "AXOutline", "AXTable", "AXUnknown", "AXSplitter", "AXScrollBar", "AXRow", "AXCell",
]
let priority: [String: Int] = [
    "AXButton": 0, "AXMenuItem": 0, "AXMenuButton": 0, "AXPopUpButton": 0, "AXCheckBox": 0, "AXRadioButton": 0,
    "AXTextArea": 1, "AXTextField": 1, "AXLink": 1, "AXStaticText": 2, "AXImage": 3,
]

func fold(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

func matches(_ needle: String, role: String?) -> [Node] {
    let exact = needle.hasPrefix("=")
    let wanted = fold(exact ? String(needle.dropFirst()) : needle)
    let found = allNodes().filter { node in
        if let role, role != "-" {
            if node.role != role { return false }
        } else if containers.contains(node.role) {
            return false
        }
        guard let frame = node.frame, frame.width > 0, frame.height > 0 else { return false }
        if wanted.isEmpty { return true }
        return node.labels.contains { exact ? fold($0) == wanted : fold($0).contains(wanted) }
    }
    return found.enumerated().sorted { first, second in
        let a = priority[first.element.role] ?? 5
        let b = priority[second.element.role] ?? 5
        return a != b ? a < b : first.offset < second.offset
    }.map { $0.element }
}

func describe(_ node: Node) -> String {
    let place = node.frame.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? ""
    return "\(node.role) [\(node.label.prefix(200))] \(place)"
}

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(120_000)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("usage : ax dump | find | click | press | wait …")
    exit(64)
}
let needle = arguments.count > 1 ? arguments[1] : ""
let role = arguments.count > 2 ? arguments[2] : nil
let requestedIndex = arguments.count > 3 ? Int(arguments[3]) ?? 0 : 0

switch command {
case "dump":
    print("Accessibilité autorisée : \(AXIsProcessTrusted())")
    for node in allNodes() {
        print(String(repeating: "  ", count: node.depth) + describe(node))
    }
case "find":
    let found = matches(needle, role: role)
    for node in found.prefix(8) { print(describe(node)) }
    exit(found.isEmpty ? 1 : 0)
case "click", "press":
    let found = matches(needle, role: role)
    let index = requestedIndex < 0 ? found.count + requestedIndex : requestedIndex
    guard index >= 0, index < found.count else {
        print("introuvable : \(needle)")
        exit(1)
    }
    let node = found[index]
    print("\(command) → \(describe(node))")
    if command == "press" {
        let result = AXUIElementPerformAction(node.element, "AXPress" as CFString)
        if result != .success {
            print("AXPress impossible (\(result.rawValue))")
            exit(1)
        }
    } else if let frame = node.frame {
        click(CGPoint(x: frame.midX, y: frame.midY))
    }
case "wait":
    let seconds = Double(role ?? "") ?? 20
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if !matches(needle, role: nil).isEmpty {
            print("présent : \(needle)")
            exit(0)
        }
        usleep(500_000)
    }
    print("toujours absent : \(needle)")
    exit(1)
case "close":
    let filter = ProcessInfo.processInfo.environment["AX_WINDOW"] ?? ""
    guard !filter.isEmpty, let root = appElement() else { exit(64) }
    var closed = 0
    for window in attribute(root, "AXWindows") as? [AXUIElement] ?? [] where windowMatches(window, filter) {
        if let button = attribute(window, "AXCloseButton"), CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(button as! AXUIElement, "AXPress" as CFString)
            closed += 1
        }
    }
    print("fenêtres fermées : \(closed)")
case "focused":
    guard let root = appElement(), let focused = attribute(root, "AXFocusedUIElement"),
          CFGetTypeID(focused) == AXUIElementGetTypeID() else {
        print("aucun")
        exit(1)
    }
    var nodes: [Node] = []
    let element = focused as! AXUIElement
    nodes.append(Node(element: element, depth: 0, role: text(element, "AXRole") ?? "?", labels: [text(element, "AXDescription") ?? "", text(element, "AXHelp") ?? ""].filter { !$0.isEmpty }, frame: frame(of: element)))
    print(describe(nodes[0]))
case "allow":
    // Alertes affichées par d’autres processus (autorisations de macOS) : bouton « Allow » ou « OK ».
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier != "com.ollamachat.desktop" {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        for window in attribute(root, "AXWindows") as? [AXUIElement] ?? [] {
            var nodes: [Node] = []
            collect(window, depth: 0, into: &nodes)
            let texts = nodes.filter { $0.role == "AXStaticText" }.map(\.label).joined(separator: " ")
            guard let button = nodes.first(where: { $0.role == "AXButton" && ["Allow", "Autoriser", "OK"].contains(text($0.element, "AXTitle") ?? "") })
            else { continue }
            AXUIElementPerformAction(button.element, "AXPress" as CFString)
            print("alerte validée (\(app.localizedName ?? "?")) : \(texts.prefix(160))")
        }
    }
default:
    print("commande inconnue : \(command)")
    exit(64)
}
