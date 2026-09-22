//
//  SettingsMenuStyle.swift
//  shizen
//
//  Shared list-row appearance: bold system-yellow symbol on the leading edge.
//

import UIKit

enum SettingsMenuStyle {
    static let iconSize = CGSize(width: 24, height: 24)

    static func content(title: String, subtitle: String?, symbolName: String) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = title
        content.secondaryText = subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2

        let symbol = UIImage.SymbolConfiguration(weight: .bold)
        content.image = UIImage(systemName: symbolName, withConfiguration: symbol)
        content.imageProperties.tintColor = .secondaryLabel
        content.imageProperties.maximumSize = iconSize
        content.imageProperties.reservedLayoutSize = iconSize
        content.imageToTextPadding = 16
        content.directionalLayoutMargins.top = 16
        content.directionalLayoutMargins.bottom = 16
        return content
    }

    static func apply(
        to cell: UICollectionViewListCell,
        title: String,
        subtitle: String?,
        symbolName: String,
        accessories: [UICellAccessory]
    ) {
        cell.contentConfiguration = content(title: title, subtitle: subtitle, symbolName: symbolName)
        cell.accessories = accessories
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }
}

nonisolated struct SettingsMenuItem: Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
}
