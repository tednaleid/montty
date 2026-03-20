// Copied from ghostty (MIT). See ghostty-binding-adaptation.md for details.
// MONTTY: Simplified -- original references BaseTerminalController and
// SurfaceDragSource for split pane drag handles. Stubbed to empty view
// until Phase 3 (splits) when this will be properly implemented.

import SwiftUI

extension Ghostty {
    struct SurfaceGrabHandle: View {
        @ObservedObject var surfaceView: SurfaceView

        var body: some View {
            EmptyView()
        }
    }
}
