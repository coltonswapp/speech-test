//
//  InsetGroupedDetailSectionLayout.swift
//  shizen
//
//  Shared compositional-layout helpers for detail-style collection views:
//  a custom hero section plus inset-grouped list sections below.
//

import UIKit

enum InsetGroupedDetailSectionLayout {
    /// Custom hero section — not list layout, so UIKit does not paint grouped card chrome.
    static func makeCompositionalHeroSection(
        estimatedHeight: CGFloat,
        contentInsets: NSDirectionalEdgeInsets
    ) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(estimatedHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = contentInsets
        return section
    }
}
