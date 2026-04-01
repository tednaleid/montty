import SwiftUI

@main
struct MonttyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow(tabStore: appDelegate.tabStore)
                .environmentObject(appDelegate.ghostty)
                .environmentObject(appDelegate)
        }
    }
}
