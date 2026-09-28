// Crée un PDF contenant du vrai texte : make_pdf.swift <texte.txt> <sortie.pdf>
import AppKit

let arguments = CommandLine.arguments
let text = (try? String(contentsOfFile: arguments[1], encoding: .utf8)) ?? ""
let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
view.font = NSFont.systemFont(ofSize: 14)
view.string = text
try? view.dataWithPDF(inside: view.bounds).write(to: URL(fileURLWithPath: arguments[2]))
