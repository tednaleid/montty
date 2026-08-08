// ABOUTME: Tests for PaneTint's stop clamping, primary/leading resolution,
// ABOUTME: and Codable round-tripping between a bare string and a stop array.

import Foundation
import Testing

@Suite struct PaneTintTests {
    @Test func emptyStopsFallBackToGray() {
        #expect(PaneTint(stops: []).stops == [.named(.gray)])
    }

    @Test func clampsToThreeStops() {
        let tint = PaneTint(stops: [
            .named(.red), .named(.green), .named(.blue), .named(.cyan)
        ])
        #expect(tint.stops.count == 3)
        #expect(tint.stops == [.named(.red), .named(.green), .named(.blue)])
    }

    @Test func primaryIsTrailingStopAndLeadingIsFirst() {
        let tint = PaneTint(stops: [.named(.red), .named(.green)])
        #expect(tint.primary == .named(.green))
        #expect(tint.leading == .named(.red))
        #expect(tint.isGradient)
        #expect(!PaneTint(stops: [.named(.red)]).isGradient)
    }

    @Test func decodesBareStringFromV2Sessions() throws {
        let data = Data("\"green\"".utf8)
        let tint = try JSONDecoder().decode(PaneTint.self, from: data)
        #expect(tint.stops == [.named(.green)])
    }

    @Test func decodesArrayOfStops() throws {
        let data = Data("[\"neutralBright\",\"#1a7f37\"]".utf8)
        let tint = try JSONDecoder().decode(PaneTint.self, from: data)
        #expect(tint.stops == [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
    }

    @Test func encodesSingleStopAsBareStringForOlderBuilds() throws {
        let data = try JSONEncoder().encode(PaneTint(stops: [.named(.green)]))
        #expect(String(data: data, encoding: .utf8) == "\"green\"")
    }

    @Test func encodesGradientAsArray() throws {
        let tint = PaneTint(stops: [.named(.neutralBright), .named(.green)])
        let data = try JSONEncoder().encode(tint)
        #expect(String(data: data, encoding: .utf8) == "[\"neutralBright\",\"green\"]")
    }

    @Test func roundTripsBothShapes() throws {
        let cases = [
            PaneTint(stops: [.named(.blue)]),
            PaneTint(stops: [.named(.blue), .hex(RGB(r: 1, g: 2, b: 3))]),
            PaneTint(stops: [.named(.blue), .named(.red), .named(.cyan)])
        ]
        for tint in cases {
            let data = try JSONEncoder().encode(tint)
            #expect(try JSONDecoder().decode(PaneTint.self, from: data) == tint)
        }
    }
}
