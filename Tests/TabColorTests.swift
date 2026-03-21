import Foundation
import Testing

struct TabColorTests {
    @Test func presetColorCodableRoundTrip() throws {
        let color = TabColor.preset(.red)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(TabColor.self, from: data)
        #expect(decoded == color)
    }

    @Test func autoColorCodableRoundTrip() throws {
        let color = TabColor.auto
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(TabColor.self, from: data)
        #expect(decoded == .auto)
    }

    @Test func allPresetColorsRoundTrip() throws {
        for preset in TabColor.PresetColor.allCases {
            let color = TabColor.preset(preset)
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(TabColor.self, from: data)
            #expect(decoded == color)
        }
    }

    @Test func presetColorEquality() {
        #expect(TabColor.preset(.red) == TabColor.preset(.red))
        #expect(TabColor.preset(.red) != TabColor.preset(.blue))
        #expect(TabColor.auto != TabColor.preset(.red))
    }

    @Test func tenPresetColorsExist() {
        #expect(TabColor.PresetColor.allCases.count == 10)
    }
}
