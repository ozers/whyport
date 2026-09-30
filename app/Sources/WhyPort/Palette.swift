import AppKit
import SwiftUI

enum Palette {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    // Orange and red are left out so a port number never reads as a warning or a stop button.
    private static let ports: [Color] = [
        dynamic(light: 0x0969DA, dark: 0x58A6FF),
        dynamic(light: 0x0B7A75, dark: 0x39C5BB),
        dynamic(light: 0x1A7F37, dark: 0x56D364),
        dynamic(light: 0x8A6100, dark: 0xE3B341),
        dynamic(light: 0xBF3989, dark: 0xF778BA),
        dynamic(light: 0x8250DF, dark: 0xBC8CFF),
        dynamic(light: 0x3F51B5, dark: 0x8C9EFF),
        dynamic(light: 0x9C5A2E, dark: 0xDDA073),
    ]

    // Common dev ports are multiples of 8 (3000, 8000, 8080, 5432), so a plain modulo paints them alike.
    // This multiplier gives 3000, 3001, 5173, 8000, 8080, 8081, 5432 and 6379 eight different colors.
    static func port(_ port: Int) -> Color {
        let hash = UInt32(truncatingIfNeeded: port) &* 0xD745_0E65
        return ports[Int(hash >> 29)]
    }

    static let exposure = Color(nsColor: .systemOrange)
    static let memory = Color(nsColor: .systemRed)
    static let live = Color(nsColor: .systemGreen)
    static let danger = Color(nsColor: .systemRed)
    static let chartMemory = Color(nsColor: .systemBlue)
    static let chartCPU = Color(nsColor: .systemTeal)
    static let why = Color.accentColor.opacity(0.09)
    static let well = Color.primary.opacity(0.05)
}
