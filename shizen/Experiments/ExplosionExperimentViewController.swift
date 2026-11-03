//
//  ExplosionExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: tap the canvas to fire NNKit explosions. Size, particle
//  kind, and emoji editing live in an undimmed detent sheet — small to play,
//  medium/large to edit.
//

import NNKit
import UIKit

enum ExplosionParticleKind: Int, CaseIterable {
    case emojis
    case mascots

    var title: String {
        switch self {
        case .emojis: return "Emojis"
        case .mascots: return "Mascots"
        }
    }
}

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
    private var particleKind: ExplosionParticleKind = .emojis
    private var mascotSettings = HanaParticleSettings()

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

        let sheet = ExplosionControlsSheetViewController(
            selectedSize: selectedSize,
            particleKind: particleKind,
            mascotSettings: mascotSettings
        )
        sheet.onSizeChanged = { [weak self] size in
            self?.selectedSize = size
        }
        sheet.onKindChanged = { [weak self] kind in
            self?.particleKind = kind
        }
        sheet.onMascotSettingsChanged = { [weak self] settings in
            self?.mascotSettings = settings
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
        let images = particleKind == .mascots ? HanaParticleImages.images(for: mascotSettings) : []
        let pointSize = particleKind == .mascots ? mascotSettings.particleSize : 0
        switch selectedSize {
        case .tiny:
            ExplosionManager.trigger(.tiny, at: location, images: images, imagePointSize: pointSize)
        case .small:
            ExplosionManager.trigger(.small, at: location, images: images, imagePointSize: pointSize)
        case .medium:
            ExplosionManager.trigger(.medium, at: location, images: images, imagePointSize: pointSize)
        case .large:
            ExplosionManager.trigger(.large, at: location, images: images, imagePointSize: pointSize)
        case .atomic:
            ExplosionManager.trigger(.atomic, at: location, images: images, imagePointSize: pointSize)
        case .random:
            ExplosionManager.triggerRandom(at: location, images: images, imagePointSize: pointSize)
        }
    }
}

final class ExplosionControlsSheetViewController: UIViewController, UISheetPresentationControllerDelegate {

    static let smallDetentID = UISheetPresentationController.Detent.Identifier("explosionSmall")
    static let smallDetentHeight: CGFloat = 212

    var onSizeChanged: ((ExplosionSizeOption) -> Void)?
    var onKindChanged: ((ExplosionParticleKind) -> Void)?
    var onMascotSettingsChanged: ((HanaParticleSettings) -> Void)?

    private let stack = UIStackView()
    private let instructionLabel = UILabel()
    private let kindControl = UISegmentedControl(items: ExplosionParticleKind.allCases.map(\.title))
    private let sizeControl = UISegmentedControl(items: ExplosionSizeOption.allCases.map(\.title))
    private let emojiCollectionView: UICollectionView
    private let mascotScroll = UIScrollView()
    private let mascotStack = UIStackView()
    private let consistentSwitch = UISwitch()
    private let particleSizeSlider = UISlider()
    private let petalSlider = UISlider()
    private let faceSlider = UISlider()
    private let spreadSlider = UISlider()
    private let wobbleSlider = UISlider()
    private let previewScroll = UIScrollView()
    private let previewStack = UIStackView()
    private let filler = UIView()
    private let copyButton = UIButton(type: .system)
    private var selectedEmojis: Set<String>
    private var particleKind: ExplosionParticleKind
    private var mascotSettings: HanaParticleSettings
    private var isExpanded = false
    private var previewWorkItem: DispatchWorkItem?
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var copyResetWorkItem: DispatchWorkItem?

    init(
        selectedSize: ExplosionSizeOption,
        particleKind: ExplosionParticleKind,
        mascotSettings: HanaParticleSettings
    ) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 44, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        emojiCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        selectedEmojis = Set(ExperimentSettings.explosionEmojis)
        self.particleKind = particleKind
        self.mascotSettings = mascotSettings
        super.init(nibName: nil, bundle: nil)
        sizeControl.selectedSegmentIndex = selectedSize.rawValue
        kindControl.selectedSegmentIndex = particleKind.rawValue
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
        applyDetentLayout()
        kindControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
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

        kindControl.translatesAutoresizingMaskIntoConstraints = false
        sizeControl.translatesAutoresizingMaskIntoConstraints = false

        mascotScroll.translatesAutoresizingMaskIntoConstraints = false
        mascotScroll.alwaysBounceVertical = true
        mascotScroll.showsVerticalScrollIndicator = true
        mascotScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        mascotScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        mascotStack.axis = .vertical
        mascotStack.spacing = 14
        mascotStack.translatesAutoresizingMaskIntoConstraints = false
        mascotScroll.addSubview(mascotStack)

        let consistentLabel = UILabel()
        consistentLabel.text = "Consistent"
        consistentLabel.font = .systemFont(ofSize: 16, weight: .medium)
        consistentLabel.textColor = .label
        consistentSwitch.isOn = mascotSettings.consistent
        consistentSwitch.addTarget(self, action: #selector(consistentChanged), for: .valueChanged)
        let consistentRow = UIStackView(arrangedSubviews: [consistentLabel, consistentSwitch])
        consistentRow.axis = .horizontal
        consistentRow.alignment = .center

        configureSlider(particleSizeSlider, min: 24, max: 96, value: Float(mascotSettings.particleSize))
        configureSlider(petalSlider, min: 0.5, max: 1.2, value: Float(mascotSettings.petalScale))
        configureSlider(faceSlider, min: 0.5, max: 1.6, value: Float(mascotSettings.faceScale))
        configureSlider(spreadSlider, min: 0, max: 1, value: Float(mascotSettings.petalSpread))
        configureSlider(wobbleSlider, min: 0, max: 1, value: Float(mascotSettings.petalWobble))

        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.alwaysBounceHorizontal = true
        previewScroll.showsHorizontalScrollIndicator = false
        previewStack.axis = .horizontal
        previewStack.spacing = 4
        previewStack.alignment = .center
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.addSubview(previewStack)

        mascotStack.addArrangedSubview(consistentRow)
        mascotStack.addArrangedSubview(ExperimentSliderRow.make(title: "Mascot size", slider: particleSizeSlider, format: "%.0f"))
        mascotStack.addArrangedSubview(ExperimentSliderRow.make(title: "Petal size", slider: petalSlider, format: "%.2f"))
        mascotStack.addArrangedSubview(ExperimentSliderRow.make(title: "Face size", slider: faceSlider, format: "%.2f"))
        mascotStack.addArrangedSubview(ExperimentSliderRow.make(title: "Petal spread", slider: spreadSlider, format: "%.2f"))
        mascotStack.addArrangedSubview(ExperimentSliderRow.make(title: "Petal wobble", slider: wobbleSlider, format: "%.2f"))
        mascotStack.addArrangedSubview(previewScroll)

        emojiCollectionView.translatesAutoresizingMaskIntoConstraints = false
        emojiCollectionView.backgroundColor = .clear
        emojiCollectionView.allowsMultipleSelection = true
        emojiCollectionView.alwaysBounceVertical = true
        emojiCollectionView.delegate = self
        emojiCollectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
        emojiCollectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        filler.backgroundColor = .clear
        filler.setContentHuggingPriority(.init(1), for: .vertical)
        filler.setContentCompressionResistancePriority(.init(1), for: .vertical)

        var copyConfig = UIButton.Configuration.tinted()
        copyConfig.title = "Copy selected"
        copyConfig.image = UIImage(systemName: "doc.on.doc")
        copyConfig.imagePadding = 8
        copyButton.configuration = copyConfig
        copyButton.addTarget(self, action: #selector(copySelectedTapped), for: .touchUpInside)

        stack.addArrangedSubview(kindControl)
        stack.addArrangedSubview(instructionLabel)
        stack.addArrangedSubview(sizeControl)
        stack.addArrangedSubview(emojiCollectionView)
        stack.addArrangedSubview(mascotScroll)
        stack.addArrangedSubview(copyButton)
        stack.addArrangedSubview(filler)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            kindControl.heightAnchor.constraint(equalToConstant: 32),
            sizeControl.heightAnchor.constraint(equalToConstant: 32),
            mascotStack.topAnchor.constraint(equalTo: mascotScroll.contentLayoutGuide.topAnchor),
            mascotStack.leadingAnchor.constraint(equalTo: mascotScroll.contentLayoutGuide.leadingAnchor),
            mascotStack.trailingAnchor.constraint(equalTo: mascotScroll.contentLayoutGuide.trailingAnchor),
            mascotStack.bottomAnchor.constraint(equalTo: mascotScroll.contentLayoutGuide.bottomAnchor),
            mascotStack.widthAnchor.constraint(equalTo: mascotScroll.frameLayoutGuide.widthAnchor),
            previewScroll.heightAnchor.constraint(equalToConstant: 96),
            previewStack.topAnchor.constraint(equalTo: previewScroll.contentLayoutGuide.topAnchor),
            previewStack.leadingAnchor.constraint(equalTo: previewScroll.contentLayoutGuide.leadingAnchor),
            previewStack.trailingAnchor.constraint(equalTo: previewScroll.contentLayoutGuide.trailingAnchor),
            previewStack.bottomAnchor.constraint(equalTo: previewScroll.contentLayoutGuide.bottomAnchor),
            previewStack.heightAnchor.constraint(equalTo: previewScroll.frameLayoutGuide.heightAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureSlider(_ slider: UISlider, min: Float, max: Float, value: Float) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: #selector(mascotSliderChanged), for: .valueChanged)
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

    private func applyDetentLayout() {
        let mascots = particleKind == .mascots
        let showMascotEditor = mascots && isExpanded
        let showEmojiEditor = !mascots && isExpanded
        if mascots {
            instructionLabel.text = isExpanded
                ? (mascotSettings.consistent ? "Same color, size and spin still vary" : "Themes, size, and spin vary")
                : "Pull up to tune mascots"
        } else {
            instructionLabel.text = isExpanded ? "Emojis in the burst" : "Pull up to edit emojis"
        }
        emojiCollectionView.isHidden = !showEmojiEditor
        copyButton.isHidden = !showEmojiEditor
        mascotScroll.isHidden = !showMascotEditor
        filler.isHidden = isExpanded
        if showMascotEditor {
            schedulePreviewRefresh()
        }
    }

    private func schedulePreviewRefresh() {
        previewWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildPreview()
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func rebuildPreview() {
        let images = HanaParticleImages.images(for: mascotSettings)
        let side: CGFloat = mascotSettings.consistent ? 88 : 64
        for view in previewStack.arrangedSubviews {
            previewStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for image in images {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: side),
                view.heightAnchor.constraint(equalToConstant: side),
            ])
            previewStack.addArrangedSubview(view)
        }
    }

    private func publishMascotSettings() {
        onMascotSettingsChanged?(mascotSettings)
        if particleKind == .mascots, isExpanded {
            instructionLabel.text = mascotSettings.consistent
                ? "Same color, size and spin still vary"
                : "Themes, size, and spin vary"
        }
        schedulePreviewRefresh()
    }

    private static func swiftArrayLiteral(from emojis: [String]) -> String {
        let items = emojis.map { "\"\($0)\"" }.joined(separator: ", ")
        return "[\(items)]"
    }

    @objc private func kindChanged() {
        particleKind = ExplosionParticleKind(rawValue: kindControl.selectedSegmentIndex) ?? .emojis
        onKindChanged?(particleKind)
        applyDetentLayout()
        HapticsHelper.superLightHaptic()
    }

    @objc private func consistentChanged() {
        mascotSettings.consistent = consistentSwitch.isOn
        publishMascotSettings()
        HapticsHelper.superLightHaptic()
    }

    @objc private func mascotSliderChanged() {
        mascotSettings.particleSize = CGFloat(particleSizeSlider.value)
        mascotSettings.petalScale = CGFloat(petalSlider.value)
        mascotSettings.faceScale = CGFloat(faceSlider.value)
        mascotSettings.petalSpread = CGFloat(spreadSlider.value)
        mascotSettings.petalWobble = CGFloat(wobbleSlider.value)
        publishMascotSettings()
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
        isExpanded = sheetPresentationController.selectedDetentIdentifier != Self.smallDetentID
        applyDetentLayout()
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
