import SwiftUI

@main
struct MonttyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appDelegate.ghostty)
        }
    }
}
