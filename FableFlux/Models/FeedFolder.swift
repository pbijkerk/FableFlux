import SwiftData
import Foundation

enum FeedMediaType: String, Codable {
    case audio, video, unknown
}

@Model
class FeedFolder {
    var id: UUID
    var name: String
    var sortOrder: Int
    var isSystem: Bool
    var isExpanded: Bool = true

    @Relationship(deleteRule: .nullify, inverse: \Feed.folder)
    var feeds: [Feed] = []

    init(name: String, sortOrder: Int, isSystem: Bool = false, isExpanded: Bool = true) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.isExpanded = isExpanded
    }

    var icon: String {
        switch name {
        case "Video": return "play.rectangle"
        case "Audio": return "headphones"
        case "Social": return "bubble.left.and.bubble.right"
        default: return "folder"
        }
    }
}
