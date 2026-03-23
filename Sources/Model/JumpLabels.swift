import Foundation

/// A target surface that can be jumped to.
struct JumpTarget: Equatable {
    let tabID: UUID
    let leafID: UUID
}

/// State for the surface jump overlay (ace-jump/easy-motion).
struct JumpState: Equatable {
    /// Map from label string ("a", "ab") to jump target.
    let labelToTarget: [String: JumpTarget]
    /// Map from leafID to label string (for rendering).
    let leafToLabel: [UUID: String]
    /// Partially typed prefix (empty if waiting for first key).
    var buffer: String
    /// Set of valid prefix characters (for two-char labels).
    let prefixes: Set<Character>
}

enum JumpLabels {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

    /// Generate labels for a list of targets, ordered by priority
    /// (first target gets the shortest label).
    static func assign(targets: [JumpTarget]) -> JumpState {
        let count = targets.count
        guard count > 0 else {
            return JumpState(
                labelToTarget: [:], leafToLabel: [:],
                buffer: "", prefixes: []
            )
        }

        let labels = generateLabels(count: count)
        var labelToTarget: [String: JumpTarget] = [:]
        var leafToLabel: [UUID: String] = [:]
        var prefixes = Set<Character>()

        for (index, target) in targets.enumerated() {
            let label = labels[index]
            labelToTarget[label] = target
            leafToLabel[target.leafID] = label
            if label.count > 1, let first = label.first {
                prefixes.insert(first)
            }
        }

        return JumpState(
            labelToTarget: labelToTarget,
            leafToLabel: leafToLabel,
            buffer: "",
            prefixes: prefixes
        )
    }

    /// Generate `count` labels, shortest first.
    /// <= 26: single chars a-z
    /// > 26: first (26 - P) get single chars, rest get two-char (prefix + suffix)
    static func generateLabels(count total: Int) -> [String] {
        guard total > 0 else { return [] }
        if total <= 26 {
            return (0..<total).map { String(alphabet[$0]) }
        }

        // prefixCount = number of prefix letters reserved for two-char labels
        let prefixCount = min(26, Int((Double(total - 26) / 25.0).rounded(.up)))
        let singleCount = 26 - prefixCount

        var labels: [String] = []

        // Single-char labels for the closest targets
        for idx in 0..<singleCount {
            labels.append(String(alphabet[prefixCount + idx]))
        }

        // Two-char labels using prefix letters
        var prefixIndex = 0
        while labels.count < total && prefixIndex < prefixCount {
            let prefix = alphabet[prefixIndex]
            for suffix in alphabet {
                labels.append(String(prefix) + String(suffix))
                if labels.count >= total { break }
            }
            prefixIndex += 1
        }

        return labels
    }

    /// Process a key press during jump mode.
    /// Returns the updated state, or nil if jump mode should end.
    /// If a target is found, it's returned as the second element.
    static func handleKey(
        _ key: Character, state: JumpState
    ) -> (newState: JumpState?, target: JumpTarget?) {
        let newBuffer = state.buffer + String(key)

        // Check for exact match
        if let target = state.labelToTarget[newBuffer] {
            return (nil, target)
        }

        // Check if this is a valid prefix (more chars needed)
        if state.buffer.isEmpty && state.prefixes.contains(key) {
            var updated = state
            updated.buffer = newBuffer
            return (updated, nil)
        }

        // Invalid key -- cancel
        return (nil, nil)
    }
}
