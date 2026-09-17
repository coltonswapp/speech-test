//
//  ExplosionExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: tap the canvas to fire NNKit explosions. Size and emoji
//  editing live in an undimmed detent sheet — small to play, medium/large to edit.
//

import NNKit
import UIKit

enum ExplosionSizeOption: Int, CaseIterable {
    case tiny
    case small
    case medium
    case large
    case atomic
    case random

    var title: String {
        switch self {
        case .tiny: return "Tiny"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .atomic: return "Atomic"
        case .random: return "Random"
        }
    }
}

final class ExplosionExperimentViewController: UIViewController {

    private let hintLabel = UILabel()
    private var selectedSize: ExplosionSizeOption = .medium

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Explosions"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        hintLabel.text = "Tap to explode"
        hintLabel.font = .systemFont(ofSize: 16, weight: .medium)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(canvasTapped))
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentControlsSheetIfNeeded(animated: animated)
    }

    private func presentControlsSheetIfNeeded(animated: Bool) {
        guard presentedViewController == nil else { return }

        let sheet = ExplosionControlsSheetViewController(selectedSize: selectedSize)
        sheet.onSizeChanged = { [weak self] size in
            self?.selectedSize = size
        }
        sheet.modalPresentationStyle = .pageSheet
        sheet.isModalInPresentation = true
        if let presentation = sheet.sheetPresentationController {
            let small = UISheetPresentationController.Detent.custom(
                identifier: ExplosionControlsSheetViewController.smallDetentID
            ) { _ in
                ExplosionControlsSheetViewController.smallDetentHeight
            }
            presentation.detents = [small, .medium(), .large()]
            presentation.selectedDetentIdentifier = ExplosionControlsSheetViewController.smallDetentID
            presentation.largestUndimmedDetentIdentifier = .large
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            presentation.prefersEdgeAttachedInCompactHeight = true
            presentation.preferredCornerRadius = 28
            presentation.delegate = sheet
        }
        present(sheet, animated: animated)
    }

    @objc private func canvasTapped(_ gesture: UITapGestureRecognizer) {
        HapticsHelper.lightHaptic()
        let location = view.convert(gesture.location(in: view), to: nil)
        switch selectedSize {
        case .tiny:
            ExplosionManager.trigger(.tiny, at: location)
        case .small:
            ExplosionManager.trigger(.small, at: location)
        case .medium:
            ExplosionManager.trigger(.medium, at: location)
        case .large:
            ExplosionManager.trigger(.large, at: location)
        case .atomic:
            ExplosionManager.trigger(.atomic, at: location)
        case .random:
            ExplosionManager.triggerRandom(at: location)
        }
    }
}

final class ExplosionControlsSheetViewController: UIViewController, UISheetPresentationControllerDelegate {

    static let smallDetentID = UISheetPresentationController.Detent.Identifier("explosionSmall")
    static let smallDetentHeight: CGFloat = 168

    var onSizeChanged: ((ExplosionSizeOption) -> Void)?

    private let stack = UIStackView()
    private let instructionLabel = UILabel()
    private let sizeControl = UISegmentedControl(items: ExplosionSizeOption.allCases.map(\.title))
    private let emojiCollectionView: UICollectionView
    private let copyButton = UIButton(type: .system)
    private var selectedEmojis: Set<String>
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var copyResetWorkItem: DispatchWorkItem?

    init(selectedSize: ExplosionSizeOption) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 44, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        emojiCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        selectedEmojis = Set(ExperimentSettings.explosionEmojis)
        super.init(nibName: nil, bundle: nil)
        sizeControl.selectedSegmentIndex = selectedSize.rawValue
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        configureUI()
        configureCollection()
        applySelectedEmojis()
        applySnapshot()
        applyDetentLayout(isExpanded: false)
        sizeControl.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
    }

    private func configureUI() {
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        instructionLabel.text = "Pull up to edit emojis"
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .secondaryLabel

        sizeControl.translatesAutoresizingMaskIntoConstraints = false

        emojiCollectionView.translatesAutoresizingMaskIntoConstraints = false
        emojiCollectionView.backgroundColor = .clear
        emojiCollectionView.allowsMultipleSelection = true
        emojiCollectionView.alwaysBounceVertical = true
        emojiCollectionView.delegate = self
        emojiCollectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
        emojiCollectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        var copyConfig = UIButton.Configuration.tinted()
        copyConfig.title = "Copy selected"
        copyConfig.image = UIImage(systemName: "doc.on.doc")
        copyConfig.imagePadding = 8
        copyButton.configuration = copyConfig
        copyButton.addTarget(self, action: #selector(copySelectedTapped), for: .touchUpInside)

        stack.addArrangedSubview(instructionLabel)
        stack.addArrangedSubview(sizeControl)
        stack.addArrangedSubview(emojiCollectionView)
        stack.addArrangedSubview(copyButton)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            sizeControl.heightAnchor.constraint(equalToConstant: 32),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureCollection() {
        let registration = UICollectionView.CellRegistration<ExplosionEmojiCell, String> {
            cell, _, emoji in
            cell.configure(emoji: emoji)
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: emojiCollectionView
        ) { collectionView, indexPath, emoji in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: emoji)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ExperimentSettings.explosionEmojiChoices, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)

        for (index, emoji) in ExperimentSettings.explosionEmojiChoices.enumerated()
            where selectedEmojis.contains(emoji)
        {
            emojiCollectionView.selectItem(
                at: IndexPath(item: index, section: 0),
                animated: false,
                scrollPosition: []
            )
        }
        refreshChipAppearance()
    }

    private func refreshChipAppearance() {
        for indexPath in emojiCollectionView.indexPathsForVisibleItems {
            guard let cell = emojiCollectionView.cellForItem(at: indexPath) as? ExplosionEmojiCell else { continue }
            let selected = emojiCollectionView.indexPathsForSelectedItems?.contains(indexPath) == true
            cell.setSelectedAppearance(selected)
        }
    }

    private func orderedSelectedEmojis() -> [String] {
        ExperimentSettings.explosionEmojiChoices.filter { selectedEmojis.contains($0) }
    }

    private func applySelectedEmojis() {
        let emojis = orderedSelectedEmojis()
        ExperimentSettings.explosionEmojis = emojis
        ExplosionManager.emojis = ExperimentSettings.explosionEmojis
    }

    private func applyDetentLayout(isExpanded: Bool) {
        instructionLabel.text = isExpanded ? "Emojis in the burst" : "Pull up to edit emojis"
        emojiCollectionView.isHidden = !isExpanded
        copyButton.isHidden = !isExpanded
    }

    private static func swiftArrayLiteral(from emojis: [String]) -> String {
        let items = emojis.map { "\"\($0)\"" }.joined(separator: ", ")
        return "[\(items)]"
    }

    @objc private func sizeChanged() {
        let size = ExplosionSizeOption(rawValue: sizeControl.selectedSegmentIndex) ?? .medium
        onSizeChanged?(size)
    }

    @objc private func copySelectedTapped() {
        let emojis = orderedSelectedEmojis()
        let literal = Self.swiftArrayLiteral(from: emojis)
        print("Explosion emojis (\(emojis.count)): \(emojis.joined(separator: " "))")
        print(literal)
        UIPasteboard.general.string = literal
        HapticsHelper.lightHaptic()

        copyResetWorkItem?.cancel()
        copyButton.configuration?.title = "Copied"
        let workItem = DispatchWorkItem { [weak self] in
            self?.copyButton.configuration?.title = "Copy selected"
            self?.copyResetWorkItem = nil
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        let isSmall = sheetPresentationController.selectedDetentIdentifier == Self.smallDetentID
        applyDetentLayout(isExpanded: !isSmall)
    }
}

extension ExplosionControlsSheetViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = ExperimentSettings.explosionEmojiChoices[indexPath.item]
        selectedEmojis.insert(emoji)
        applySelectedEmojis()
        refreshChipAppearance()
        HapticsHelper.superLightHaptic()
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        let emoji = ExperimentSettings.explosionEmojiChoices[indexPath.item]
        if selectedEmojis.count <= 1 {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            return
        }
        selectedEmojis.remove(emoji)
        applySelectedEmojis()
        refreshChipAppearance()
        HapticsHelper.superLightHaptic()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let selected = collectionView.indexPathsForSelectedItems?.contains(indexPath) == true
        (cell as? ExplosionEmojiCell)?.setSelectedAppearance(selected)
    }
}

private final class ExplosionEmojiCell: UICollectionViewCell {
    private let emojiLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        emojiLabel.font = .systemFont(ofSize: 28)
        emojiLabel.textAlignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emojiLabel)
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: String) {
        emojiLabel.text = emoji
    }

    func setSelectedAppearance(_ selected: Bool) {
        emojiLabel.alpha = selected ? 1 : 0.32
        contentView.backgroundColor = selected
            ? ExperimentPalette.highlightFill
            : .clear
    }
}
