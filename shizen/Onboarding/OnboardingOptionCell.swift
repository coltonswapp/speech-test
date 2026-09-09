import UIKit

final class OnboardingOptionCell: UICollectionViewCell {
    static let reuseIdentifier = "OnboardingOptionCell"
    static let preferredHeight: CGFloat = 64

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override var isSelected: Bool {
        didSet { applySelection() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = ExperimentPalette.cardSurface
        contentView.layer.cornerRadius = 16
        contentView.layer.borderWidth = ExperimentCardStroke.normalWidth
        contentView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: OnboardingOptionCell, _) in
            cell.applySelection()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
        applySelection()
    }

    private func applySelection() {
        contentView.layer.borderWidth = isSelected
            ? ExperimentCardStroke.emphasisWidth
            : ExperimentCardStroke.normalWidth
        contentView.layer.borderColor = isSelected
            ? ExperimentPalette.highlightBorder.cgColor
            : ExperimentPalette.cardBorder.cgColor
        contentView.backgroundColor = isSelected
            ? ExperimentPalette.highlightFill
            : ExperimentPalette.cardSurface
    }
}
