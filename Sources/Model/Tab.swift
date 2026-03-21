import Foundation

@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String
    var autoName: String
    var color: TabColor
    var position: Int
    var workingDirectory: String?
    var surfaceID: UUID

    var displayName: String {
        name.isEmpty ? autoName : name
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        autoName: String = "",
        color: TabColor = .auto,
        position: Int = 0,
        workingDirectory: String? = nil,
        surfaceID: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.autoName = autoName
        self.color = color
        self.position = position
        self.workingDirectory = workingDirectory
        self.surfaceID = surfaceID
    }
}
