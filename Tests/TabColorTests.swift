import Foundation
import Testing

struct TabColorTests {
    @Test func colorCodableRoundTrip() throws {
        let color = TabColor.red
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(TabColor.self, from: data)
        #expect(decoded == color)
    }

    @Test func allColorsRoundTrip() throws {
        for color in TabColor.allCases {
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(TabColor.self, from: data)
            #expect(decoded == color)
        }
    }

    @Test func colorEquality() {
        #expect(TabColor.red == TabColor.red)
        #expect(TabColor.red != TabColor.blue)
    }

    @Test func tenColorsExist() {
        #expect(TabColor.allCases.count == 10)
    }
}
