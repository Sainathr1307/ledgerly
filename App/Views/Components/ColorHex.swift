// ColorHex.swift — converts between "#RRGGBB" strings (how categories store their color) and SwiftUI colors.

import SwiftUI
import UIKit

extension Color {
    /// Builds a color from "#RRGGBB" (the "#" is optional). Unreadable input gives a neutral gray.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleaned.count == 6, let value = UInt64(cleaned, radix: 16) {
            let red = Double((value >> 16) & 0xFF) / 255.0
            let green = Double((value >> 8) & 0xFF) / 255.0
            let blue = Double(value & 0xFF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
        } else {
            self.init(.sRGB, red: 0.53, green: 0.56, blue: 0.59, opacity: 1.0)
        }
    }

    /// "#RRGGBB" for this color in sRGB (components are clamped, opacity is dropped).
    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        if !converted {
            return "#868E96"
        }
        let r = Int((min(max(red, 0), 1) * 255).rounded())
        let g = Int((min(max(green, 0), 1) * 255).rounded())
        let b = Int((min(max(blue, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
