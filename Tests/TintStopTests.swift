// ABOUTME: Tests for TintStop parsing, hue family derivation, and Codable
// ABOUTME: round-tripping between named palette slots and literal hex colors.

import Foundation
import Testing

@Suite struct TintStopTests {
    @Test func parsesPaletteName() {
        #expect(TintStop.parse("green") == .named(.green))
        #expect(TintStop.parse("brightGreen") == .named(.brightGreen))
    }

    @Test func paletteNameIgnoresCaseAndSeparators() {
        #expect(TintStop.parse("BRIGHTGREEN") == .named(.brightGreen))
        #expect(TintStop.parse("bright-green") == .named(.brightGreen))
        #expect(TintStop.parse("bright_green") == .named(.brightGreen))
    }

    @Test func parsesHexWithAndWithoutHash() {
        let expected = TintStop.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))
        #expect(TintStop.parse("#1a7f37") == expected)
        #expect(TintStop.parse("1a7f37") == expected)
        #expect(TintStop.parse("#1A7F37") == expected)
    }

    @Test func rejectsMalformedInput() {
        #expect(TintStop.parse("#fff") == nil)
        #expect(TintStop.parse("#gggggg") == nil)
        #expect(TintStop.parse("12345g") == nil)
        #expect(TintStop.parse("") == nil)
        #expect(TintStop.parse("chartreuse") == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let stops: [TintStop] = [.named(.brightMagenta), .hex(RGB(r: 0, g: 255, b: 128))]
        for stop in stops {
            let data = try JSONEncoder().encode(stop)
            let decoded = try JSONDecoder().decode(TintStop.self, from: data)
            #expect(decoded == stop)
        }
    }

    @Test func encodesAsPlainString() throws {
        let data = try JSONEncoder().encode(TintStop.named(.green))
        #expect(String(data: data, encoding: .utf8) == "\"green\"")
    }

    @Test func namedStopKeepsItsPaletteHueFamily() {
        #expect(TintStop.named(.brightGreen).hueFamily == .green)
        #expect(TintStop.named(.gray).hueFamily == .neutral)
    }

    @Test func hexStopDerivesHueFamilyFromRGB() {
        #expect(TintStop.parse("#00ff00")?.hueFamily == .green)
        #expect(TintStop.parse("#ff0000")?.hueFamily == .red)
        #expect(TintStop.parse("#0000ff")?.hueFamily == .blue)
        #expect(TintStop.parse("#00ffff")?.hueFamily == .cyan)
        #expect(TintStop.parse("#ff00ff")?.hueFamily == .magenta)
        #expect(TintStop.parse("#ffff00")?.hueFamily == .yellow)
    }

    @Test func desaturatedHexIsNeutral() {
        #expect(TintStop.parse("#808080")?.hueFamily == .neutral)
        #expect(TintStop.parse("#ffffff")?.hueFamily == .neutral)
    }
}
