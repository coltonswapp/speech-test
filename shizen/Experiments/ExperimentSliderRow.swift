//
//  ExperimentSliderRow.swift
//  shizen
//

import UIKit

enum ExperimentSliderRow {

    static func make(
        title: String,
        slider: UISlider,
        format: String = "%.1f"
    ) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.text = String(format: format, slider.value)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.spacing = 8

        slider.addAction(UIAction { _ in
            valueLabel.text = String(format: format, slider.value)
        }, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 4
        return row
    }
}
