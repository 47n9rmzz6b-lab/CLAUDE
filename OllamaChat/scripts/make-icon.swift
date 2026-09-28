// Dessine l’icône de l’application (PNG 1024 × 1024).
// Usage : swift scripts/make-icon.swift sortie.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let side = 1024

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = CGFloat(side)
// Marges et arrondi des icônes macOS récentes (tuile de 824 px dans 1024 px).
let tile = NSRect(x: 100, y: 100, width: canvas - 200, height: canvas - 200)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(srgbRed: 0.92, green: 0.58, blue: 0.45, alpha: 1),
    ending: NSColor(srgbRed: 0.79, green: 0.39, blue: 0.28, alpha: 1)
)?.draw(in: shape, angle: -90)

if let symbol = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil) {
    let configuration = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor.white.withAlphaComponent(0.8)]))
    if let glyph = symbol.withSymbolConfiguration(configuration) {
        let size = glyph.size
        let origin = NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 8)
        glyph.draw(in: NSRect(origin: origin, size: size))
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
