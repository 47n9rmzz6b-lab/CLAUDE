import AppKit
import SwiftUI

/// Palette chaude inspirée de l’application Claude, en clair et en sombre.
enum Theme {
    static let accent = Color(nsColor: NSColor(hex: 0xD97757))
    static let background = Color(light: 0xFAF9F5, dark: 0x262624)
    static let composerBackground = Color(light: 0xFFFFFF, dark: 0x30302E)
    static let userBubble = Color(light: 0xF0EEE6, dark: 0x141413)
    static let codeBackground = Color(light: 0xF3F1EA, dark: 0x1E1D1B)
    static let codeHeader = Color(light: 0xEAE7DE, dark: 0x2A2926)
    static let inlineCodeBackground = Color(light: 0xECE9E0, dark: 0x3A3834)
    static let border = Color.primary.opacity(0.1)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Couleur qui suit automatiquement l’apparence claire ou sombre du système.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
