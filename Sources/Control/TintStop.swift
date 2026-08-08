// ABOUTME: One gradient stop: a themed ANSI palette slot, or a literal RGB
// ABOUTME: color set from the montty CLI.

import Foundation

/// A literal 24-bit color.
struct RGB: Equatable, Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

extension RGB {
    /// Six hex digits without a leading `#`. Rejects any other length and any
    /// non-hex character, so partial scans never slip through.
    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        self.init(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    var text: String { String(format: "#%02x%02x%02x", Int(r), Int(g), Int(b)) }

    /// The hue family this color reads as, so a CLI-set stop still knocks out
    /// its own family when montty builds a repo gradient around it.
    var hueFamily: TabColor.HueFamily {
        let red = Double(r) / 255, green = Double(g) / 255, blue = Double(b) / 255
        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let delta = highest - lowest
        guard delta > 0.08 else { return .neutral }

        var hue: Double
        if highest == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if highest == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case ..<30, 330...: return .red
        case ..<90: return .yellow
        case ..<150: return .green
        case ..<210: return .cyan
        case ..<270: return .blue
        default: return .magenta
        }
    }
}

/// One stop in a pane's gradient.
enum TintStop: Equatable, Hashable {
    case named(TabColor)
    case hex(RGB)
}

extension TintStop {
    /// Parse one stop. A leading `#` forces hex; otherwise a palette name wins
    /// and a bare six-digit hex value is the fallback, because bash treats an
    /// unquoted `#` as a comment introducer.
    static func parse(_ text: String) -> TintStop? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            return RGB(hex: String(trimmed.dropFirst())).map(TintStop.hex)
        }

        let normalized = trimmed.lowercased().filter { $0 != "-" && $0 != "_" }
        if let color = TabColor.allCases.first(
            where: { $0.rawValue.lowercased() == normalized }
        ) {
            return .named(color)
        }
        return RGB(hex: trimmed).map(TintStop.hex)
    }

    var text: String {
        switch self {
        case .named(let color): color.rawValue
        case .hex(let rgb): rgb.text
        }
    }

    var hueFamily: TabColor.HueFamily {
        switch self {
        case .named(let color): color.hueFamily
        case .hex(let rgb): rgb.hueFamily
        }
    }
}

extension TintStop: Codable {
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let stop = TintStop.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "unrecognized tint stop \"\(text)\""
            )
        }
        self = stop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
