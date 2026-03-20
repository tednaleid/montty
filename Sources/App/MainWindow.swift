import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var ghostty: Ghostty.App

    var body: some View {
        Ghostty.Terminal()
    }
}
