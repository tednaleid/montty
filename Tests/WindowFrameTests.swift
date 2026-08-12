// ABOUTME: Verifies a restored window frame lands on a screen that exists,
// ABOUTME: and that a frame already on screen is left alone.

import CoreGraphics
import Testing

@Suite struct WindowFrameTests {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func leavesAFrameThatIsAlreadyOnScreenAlone() {
        let frame = WindowFrame(x: 100, y: 100, width: 1200, height: 800)

        #expect(frame.clamped(toVisible: [mainScreen]) == frame)
    }

    @Test func pullsAFrameFromADisconnectedDisplayBackOnScreen() {
        let frame = WindowFrame(x: 3000, y: 200, width: 1200, height: 800)

        let clamped = frame.clamped(toVisible: [mainScreen])

        #expect(clamped.x >= mainScreen.minX)
        #expect(clamped.x + clamped.width <= mainScreen.maxX)
        #expect(clamped.width == 1200)
        #expect(clamped.height == 800)
    }

    @Test func shrinksAFrameLargerThanEveryScreen() {
        let frame = WindowFrame(x: 0, y: 0, width: 4000, height: 3000)

        let clamped = frame.clamped(toVisible: [mainScreen])

        #expect(clamped.width <= mainScreen.width)
        #expect(clamped.height <= mainScreen.height)
    }

    @Test func keepsAFrameOnTheScreenItOverlapsMost() {
        let secondScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frame = WindowFrame(x: 2000, y: 100, width: 800, height: 600)

        #expect(frame.clamped(toVisible: [mainScreen, secondScreen]) == frame)
    }

    @Test func treatsAZeroSizedFrameAsEmpty() {
        #expect(WindowFrame(x: 0, y: 0, width: 0, height: 0).isEmpty)
        #expect(!WindowFrame(x: 0, y: 0, width: 10, height: 10).isEmpty)
    }
}
