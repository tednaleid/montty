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

    @Test func fifteenColorsExist() {
        // 14 Catppuccin colors + gray
        #expect(TabColor.allCases.count == 15)
    }

    @Test func ansiCodeMapsToTheAnsiSixteenSlotEachNameRepresents() {
        #expect(TabColor.red.ansiCode == 31)
        #expect(TabColor.green.ansiCode == 32)
        #expect(TabColor.yellow.ansiCode == 33)
        #expect(TabColor.blue.ansiCode == 34)
        #expect(TabColor.magenta.ansiCode == 35)
        #expect(TabColor.cyan.ansiCode == 36)
        #expect(TabColor.neutral.ansiCode == 37)
        #expect(TabColor.brightRed.ansiCode == 91)
        #expect(TabColor.brightGreen.ansiCode == 92)
        #expect(TabColor.brightYellow.ansiCode == 93)
        #expect(TabColor.brightBlue.ansiCode == 94)
        #expect(TabColor.brightMagenta.ansiCode == 95)
        #expect(TabColor.brightCyan.ansiCode == 96)
        #expect(TabColor.neutralBright.ansiCode == 97)
        #expect(TabColor.gray.ansiCode == 90)
    }
}
