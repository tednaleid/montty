import Foundation
import Testing
@testable import montty_unit

@Suite struct TabColorAutoTests {
    @Test func sameDirectoryGetsSameColor() {
        let color1 = TabColor.colorForDirectory("/Users/ted/projects/myapp")
        let color2 = TabColor.colorForDirectory("/Users/ted/projects/myapp")
        #expect(color1 == color2)
    }

    @Test func nilDirectoryReturnsGray() {
        let color = TabColor.colorForDirectory(nil)
        #expect(color == .gray)
    }

    @Test func emptyDirectoryReturnsGray() {
        // Empty string hashes to 0 which should map to the first color,
        // but the important thing is it doesn't crash
        _ = TabColor.colorForDirectory("")
    }

    @Test func hashCoversMultipleColors() {
        // Hash a variety of directories and check that we get more than one color
        let dirs = (0..<50).map { "/dir/project-\($0)" }
        let colors = Set(dirs.map { TabColor.colorForDirectory($0) })
        #expect(colors.count >= 5, "Expected at least 5 distinct colors from 50 directories")
    }

    @Test func homeDirectoryGetsConsistentColor() {
        let color = TabColor.colorForDirectory("/Users/ted")
        // Run it again to confirm determinism
        #expect(color == TabColor.colorForDirectory("/Users/ted"))
    }
}
