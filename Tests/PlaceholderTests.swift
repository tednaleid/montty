// ABOUTME: Smoke test that the unit test target compiles and links against the app
// ABOUTME: sources it includes.
import Testing

@Test func appTargetBuilds() {
    // Verifies the test target links against the app target.
    #expect(true)
}
