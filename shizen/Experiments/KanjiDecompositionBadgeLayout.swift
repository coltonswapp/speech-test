//
//  KanjiDecompositionBadgeLayout.swift
//  shizen
//
//  Identifiers and in-session offsets for draggable meaning badges on kanji
//  decomposition cards. Offsets apply to live preview and export renders.
//  Which meanings appear on each badge is stored separately in
//  KanjiDecompositionBadgeMeaningStore.
//

import UIKit

enum KanjiDecompositionBadgeIdentifier: Hashable {
    /// Per-character detail slide (intro is slide 0; characters follow).
    case character(index: Int)
    /// Hero in the combined reveal preview row.
    case combinedPreview(index: Int)
}

final class KanjiDecompositionBadgeLayoutStore {
    private(set) var offsets: [KanjiDecompositionBadgeIdentifier: CGPoint] = [:]

    func offset(for identifier: KanjiDecompositionBadgeIdentifier) -> CGPoint {
        offsets[identifier] ?? .zero
    }

    func setOffset(_ offset: CGPoint, for identifier: KanjiDecompositionBadgeIdentifier) {
        offsets[identifier] = offset
    }

    func apply(to view: UIView) {
        guard let host = view as? KanjiDecompositionBadgeLayoutHost else { return }
        for hero in host.characterHeroViews() {
            hero.applyUserOffset(offset(for: hero.layoutIdentifier))
        }
    }
}

protocol KanjiDecompositionBadgeLayoutHost: UIView {
    func characterHeroViews() -> [KanjiDecompositionCharacterHeroView]
}
