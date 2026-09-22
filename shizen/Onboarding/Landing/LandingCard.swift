import SwiftUI

struct LandingCard: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var image: String
    var placeholderColors: [Color]
    var symbolName: String
}

let landingCards: [LandingCard] = [
    .init(image: "L1", placeholderColors: [Color(red: 0.91, green: 0.38, blue: 0.42), Color(red: 0.62, green: 0.16, blue: 0.22)], symbolName: "cherry.blossom"),
    .init(image: "L2", placeholderColors: [Color(red: 0.98, green: 0.72, blue: 0.42), Color(red: 0.86, green: 0.38, blue: 0.18)], symbolName: "sun.horizon.fill"),
    .init(image: "L3", placeholderColors: [Color(red: 0.28, green: 0.36, blue: 0.72), Color(red: 0.10, green: 0.14, blue: 0.38)], symbolName: "moon.stars.fill"),
    .init(image: "L4", placeholderColors: [Color(red: 0.18, green: 0.62, blue: 0.64), Color(red: 0.08, green: 0.32, blue: 0.42)], symbolName: "water.waves"),
    .init(image: "L5", placeholderColors: [Color(red: 0.42, green: 0.68, blue: 0.38), Color(red: 0.16, green: 0.38, blue: 0.24)], symbolName: "leaf.fill"),
    .init(image: "L6", placeholderColors: [Color(red: 0.58, green: 0.42, blue: 0.82), Color(red: 0.28, green: 0.16, blue: 0.52)], symbolName: "sparkles"),
    .init(image: "L7", placeholderColors: [Color(red: 0.22, green: 0.24, blue: 0.32), Color(red: 0.08, green: 0.09, blue: 0.14)], symbolName: "tram.fill"),
    .init(image: "L8", placeholderColors: [Color(red: 0.86, green: 0.52, blue: 0.62), Color(red: 0.52, green: 0.22, blue: 0.38)], symbolName: "music.note"),
    .init(image: "L9", placeholderColors: [Color(red: 0.72, green: 0.62, blue: 0.38), Color(red: 0.38, green: 0.28, blue: 0.14)], symbolName: "building.columns.fill"),
]
