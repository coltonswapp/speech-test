import UIKit

// MARK: - Tip Model

struct TipModel {
    let id: String
    let title: String
    let message: String?
    let systemImageName: String

    init(id: String, title: String, message: String? = nil, systemImageName: String) {
        self.id = id
        self.title = title
        self.message = message
        self.systemImageName = systemImageName
    }
}

// MARK: - Arrow Edge

public enum TipArrowEdge {
    case top       // Tooltip above source, arrow points down
    case bottom    // Tooltip below source, arrow points up
    case leading   // Tooltip right of source, arrow points right
    case trailing  // Tooltip left of source, arrow points left
}
