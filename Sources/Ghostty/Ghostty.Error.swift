import Foundation

extension Ghostty {
    /// Possible errors from internal Ghostty calls.
    // MONTTY: Removed CustomLocalizedStringResourceConvertible conformance
    // (requires iOS 16+ / macOS 15+ API). Using LocalizedError instead.
    enum Error: Swift.Error, LocalizedError {
        case apiFailed

        var errorDescription: String? {
            switch self {
            case .apiFailed: return "libghostty API call failed"
            }
        }
    }
}
