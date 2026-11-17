//
//  ClipTagFlow.swift
//  shizen
//
//  Clip catalog tags as glass hashtag pills (the QA note composer's
//  GlassTagControl / GlassTagFlowView), for SwiftUI screens.
//

import SwiftUI
import UIKit

/// One pill: a tag filter, its label, and whether it's selected.
struct ClipTagChip: Hashable {
    let filter: ClipTagFilter
    var title: String
    var isSelected = false

    init(filter: ClipTagFilter, count: Int? = nil, isSelected: Bool = false) {
        self.filter = filter
        title = count.map { "\(filter.hashtag) \($0)" } ?? filter.hashtag
        self.isSelected = isSelected
    }
}

/// Wrapping rows of glass hashtag pills.
/// `toggles`: pills toggle on tap (filters); otherwise they act as buttons.
struct ClipTagFlow: UIViewRepresentable {
    let chips: [ClipTagChip]
    var toggles = false
    var onTap: (ClipTagFilter) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GlassTagFlowView {
        let flow = GlassTagFlowView()
        flow.setContentCompressionResistancePriority(.required, for: .vertical)
        return flow
    }

    func updateUIView(_ flow: GlassTagFlowView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        let titles = chips.map(\.title)
        if titles != coordinator.titles || toggles != coordinator.toggles {
            coordinator.titles = titles
            coordinator.toggles = toggles
            coordinator.controls = chips.map { chip in
                let control = GlassTagControl(title: chip.title)
                control.isToggleable = toggles
                control.addAction(
                    UIAction { [weak coordinator] _ in coordinator?.onTap?(chip.filter) },
                    for: toggles ? .valueChanged : .primaryActionTriggered
                )
                return control
            }
            flow.setTags(coordinator.controls)
        }
        for (control, chip) in zip(coordinator.controls, chips) where control.isSelected != chip.isSelected {
            control.isSelected = chip.isSelected
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlassTagFlowView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: 0))
    }

    final class Coordinator {
        var titles: [String] = []
        var toggles = false
        var controls: [GlassTagControl] = []
        var onTap: ((ClipTagFilter) -> Void)?
    }
}
