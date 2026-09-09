import Foundation

struct SurveyQuestion: Codable {
    enum Layout: String, Codable {
        case list
        case grid
    }

    let id: String
    let title: String
    let subtitle: String?
    let options: [String]
    let isMultiSelect: Bool
    let layout: Layout?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case options
        case isMultiSelect = "multi_select"
        case layout
    }

    var columnCount: Int {
        layout == .grid ? 2 : 1
    }
}
