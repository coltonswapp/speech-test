//
//  OnboardingStageLayoutExperimentViewController.swift
//  shizen
//
//  DEBUG experiment, separate from the auth landing. Each stage is a layout:
//  title, subtitle, and assets placed in the canvas. Next fades the title
//  out, then brings the next one up on NNKit's overshoot curve. Shared assets
//  shift to their next position; new ones fade in.
//

import NNKit
import UIKit

struct OnboardingStageLayout {
    struct Asset: Identifiable {
        enum Kind {
            case symbol(String)
            case phrase(String)
        }

        let id: String
        let kind: Kind
        /// Unit center inside the stage canvas, 0...1.
        let center: CGPoint
        let size: CGSize

        static func phrase(_ id: String, _ text: String, at center: CGPoint) -> Asset {
            Asset(id: id, kind: .phrase(text), center: center, size: CGSize(width: 168, height: 108))
        }

        static func symbol(_ id: String, _ name: String, at center: CGPoint) -> Asset {
            Asset(id: id, kind: .symbol(name), center: center, size: CGSize(width: 92, height: 92))
        }
    }

    let title: String
    let subtitle: String
    let assets: [Asset]
    var showsStudyField = false
    /// Hold the current title this long before the next stage animates in.
    var nextStageDelay: TimeInterval = 0

    static let catalog: [OnboardingStageLayout] = [
        OnboardingStageLayout(
            title: "Learning Japanese got\ncomplicated.",
            subtitle: "Lists, decks, apps; when did it get\nso complicated?",
            assets: [],
            showsStudyField: true,
            nextStageDelay: 1.6
        ),
        OnboardingStageLayout(
            title: "Then say it back",
            subtitle: "The same line, now it's yours.",
            assets: [
                .phrase("phrase", "おはよう", at: CGPoint(x: 0.64, y: 0.26)),
                .symbol("wave", "waveform", at: CGPoint(x: 0.28, y: 0.48)),
                .symbol("mic", "mic.fill", at: CGPoint(x: 0.70, y: 0.72)),
            ]
        ),
        OnboardingStageLayout(
            title: "Keep the close calls",
            subtitle: "What almost stuck comes back tomorrow.",
            assets: [
                .phrase("phrase", "おはよう", at: CGPoint(x: 0.50, y: 0.36)),
                .symbol("mark", "bookmark.fill", at: CGPoint(x: 0.26, y: 0.72)),
                .symbol("spark", "sparkles", at: CGPoint(x: 0.74, y: 0.68)),
            ]
        ),
    ]
}

final class OnboardingStageLayoutExperimentViewController: UIViewController {

    private static let entranceDuration: TimeInterval = 0.55
    private static let titleRise: CGFloat = 14
    private static let titleEdgeFeather: CGFloat = 72

    private let stages = OnboardingStageLayout.catalog
    private var index = 0
    private var hasStarted = false
    private var isShowingStage = false
    private var isTransitioning = false
    private var isShiftingAssets = false

    private let closeButton = OnboardingChrome.makeCircularIconButton(symbolName: "xmark")
    private let titleContainer = UIView()
    private let titleEdgeMask = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let canvas = UIView()
    private let studyField = StudyMethodFloatField()
    private let pageControl = UIPageControl()
    private let ctaButton = PrimaryButton(type: .system)

    private struct PlacedAsset {
        let view: StageAssetView
        let centerX: NSLayoutConstraint
        let centerY: NSLayoutConstraint
    }

    private var placed: [String: PlacedAsset] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        configureHeader()
        configureCanvas()
        configurePageControl()
        configureCTA()
        view.sendSubviewToBack(studyField)
        titleLabel.alpha = 0
        subtitleLabel.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        showStage(0)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        studyField.stopFloating()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTitleEdge()
        guard !isShiftingAssets else { return }
        placeAssets(for: stages[index], animated: false)
    }

    private func configureHeader() {
        titleContainer.backgroundColor = ExperimentPalette.pageBackground
        titleContainer.isUserInteractionEnabled = false
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleEdgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        titleEdgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        titleContainer.layer.mask = titleEdgeMask
        view.addSubview(titleContainer)

        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = OnboardingChrome.subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleContainer.topAnchor.constraint(equalTo: view.topAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleContainer.bottomAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16 + Self.titleEdgeFeather),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: OnboardingChrome.titleHorizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -OnboardingChrome.titleHorizontalInset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    private func configureCanvas() {
        canvas.clipsToBounds = true
        canvas.backgroundColor = .clear
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)

        studyField.translatesAutoresizingMaskIntoConstraints = false
        studyField.alpha = 0
        view.addSubview(studyField)
        NSLayoutConstraint.activate([
            studyField.topAnchor.constraint(equalTo: view.topAnchor),
            studyField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            studyField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            studyField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configurePageControl() {
        pageControl.numberOfPages = stages.count
        pageControl.currentPage = 0
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addTarget(self, action: #selector(pageChanged), for: .valueChanged)
        view.addSubview(pageControl)
    }

    private func configureCTA() {
        ctaButton.primaryStyle = .yellow
        ctaButton.setTitle("Next", for: .normal)
        ctaButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        view.addSubview(ctaButton)

        NSLayoutConstraint.activate([
            ctaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            ctaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            ctaButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            ctaButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -8),

            canvas.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),
        ])
    }

    @objc private func closeTapped() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func nextTapped() {
        guard hasStarted, !isTransitioning else { return }
        showStage((index + 1) % stages.count)
    }

    @objc private func pageChanged(_ sender: UIPageControl) {
        guard hasStarted, !isTransitioning, sender.currentPage != index else {
            sender.currentPage = index
            return
        }
        showStage(sender.currentPage)
    }

    private func updateTitleEdge() {
        let bounds = titleContainer.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        titleEdgeMask.frame = bounds
        let feather = min(Self.titleEdgeFeather, bounds.height * 0.45)
        let solid = (bounds.height - feather) / bounds.height
        titleEdgeMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
        ]
        titleEdgeMask.locations = [0, NSNumber(value: Double(solid)), 1]
    }

    private func showStage(_ nextIndex: Int) {
        let stage = stages[nextIndex]
        let previous = isShowingStage ? stages[index] : nil
        index = nextIndex
        isShowingStage = true
        isTransitioning = true

        let hold = previous?.nextStageDelay ?? 0
        if hold > 0, previous?.showsStudyField == true, !stage.showsStudyField {
            setStudyField(shown: false, animated: true)
        }

        let begin = { [weak self] in
            guard let self, self.index == nextIndex else { return }
            self.presentStage(stage, previous: previous, skipFieldExit: hold > 0)
        }

        guard hold > 0, previous != nil else {
            begin()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: begin)
    }

    private func presentStage(_ stage: OnboardingStageLayout, previous: OnboardingStageLayout?, skipFieldExit: Bool) {
        ctaButton.setTitle(index == stages.count - 1 ? "Replay" : "Next", for: .normal)
        pageControl.currentPage = index
        reconcileAssets(from: previous, to: stage)
        if !(skipFieldExit && previous?.showsStudyField == true && !stage.showsStudyField) {
            setStudyField(shown: stage.showsStudyField, animated: true)
        }

        let reveal = { [weak self] in
            guard let self else { return }
            self.titleLabel.text = stage.title
            self.subtitleLabel.text = stage.subtitle
            self.titleLabel.prepareForSlideIn(slideDistance: Self.titleRise)
            self.subtitleLabel.alpha = 0
            self.titleLabel.animateSlideIn(duration: Self.entranceDuration) {
                self.isTransitioning = false
            }
            UIView.animate(
                withDuration: AnimationDefaults.standardDuration,
                delay: 0.08,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.subtitleLabel.alpha = 1
            }
            self.fadeInArrivals(of: stage, previousIDs: Set(previous?.assets.map(\.id) ?? []))
        }

        guard previous != nil else {
            reveal()
            return
        }

        let fadeOut = UIViewPropertyAnimator(duration: AnimationDefaults.fastDuration, curve: .easeIn) {
            self.titleLabel.alpha = 0
            self.subtitleLabel.alpha = 0
        }
        fadeOut.addCompletion { _ in reveal() }
        fadeOut.startAnimation()
    }

    private func setStudyField(shown: Bool, animated: Bool) {
        if shown {
            studyField.alpha = 1
            studyField.startFloating()
            studyField.prepareSnapshotsIfNeeded()
            return
        }

        guard animated else {
            studyField.stopFloating()
            studyField.alpha = 0
            return
        }

        studyField.dropUnderGravity { [weak self] in
            self?.studyField.alpha = 0
        }
    }

    private func reconcileAssets(from previous: OnboardingStageLayout?, to stage: OnboardingStageLayout) {
        let previousIDs = Set(previous?.assets.map(\.id) ?? [])
        let nextIDs = Set(stage.assets.map(\.id))
        let staying = stage.assets.filter { previousIDs.contains($0.id) }
        if !staying.isEmpty {
            isShiftingAssets = true
        }

        for id in previousIDs.subtracting(nextIDs) {
            guard let placed = placed[id] else { continue }
            self.placed[id] = nil
            UIView.animate(
                withDuration: AnimationDefaults.fastDuration,
                delay: 0,
                options: .curveEaseIn,
                animations: { placed.view.alpha = 0 },
                completion: { _ in placed.view.removeFromSuperview() }
            )
        }

        for asset in stage.assets where !previousIDs.contains(asset.id) {
            placed[asset.id] = install(asset, alpha: 0)
        }

        guard !staying.isEmpty else {
            placeAssets(for: stage, animated: false)
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: Self.entranceDuration,
            controlPoint1: AnimationDefaults.overshootControlPoint1,
            controlPoint2: AnimationDefaults.overshootControlPoint2
        ) {
            self.placeAssets(staying, animated: true)
        }
        animator.addCompletion { [weak self] _ in
            self?.isShiftingAssets = false
        }
        animator.startAnimation()
    }

    private func fadeInArrivals(of stage: OnboardingStageLayout, previousIDs: Set<String>) {
        let arrivals = stage.assets.filter { !previousIDs.contains($0.id) }
        for (offset, asset) in arrivals.enumerated() {
            guard let view = placed[asset.id]?.view else { continue }
            view.alpha = 0
            UIView.animate(
                withDuration: AnimationDefaults.standardDuration,
                delay: 0.05 + TimeInterval(offset) * 0.06,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                view.alpha = 1
            }
        }
    }

    private func install(_ asset: OnboardingStageLayout.Asset, alpha: CGFloat) -> PlacedAsset {
        let assetView = StageAssetView(kind: asset.kind)
        assetView.translatesAutoresizingMaskIntoConstraints = false
        assetView.alpha = alpha

        let centerX = assetView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor)
        let centerY = assetView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor)
        let placedAsset = PlacedAsset(view: assetView, centerX: centerX, centerY: centerY)

        UIView.performWithoutAnimation {
            canvas.addSubview(assetView)
            NSLayoutConstraint.activate([
                centerX,
                centerY,
                assetView.widthAnchor.constraint(equalToConstant: asset.size.width),
                assetView.heightAnchor.constraint(equalToConstant: asset.size.height),
            ])
            applyCenter(of: asset, to: placedAsset)
            canvas.layoutIfNeeded()
        }
        return placedAsset
    }

    private func placeAssets(for stage: OnboardingStageLayout, animated: Bool) {
        placeAssets(stage.assets, animated: animated)
    }

    private func placeAssets(_ assets: [OnboardingStageLayout.Asset], animated: Bool) {
        for asset in assets {
            guard let placed = placed[asset.id] else { continue }
            applyCenter(of: asset, to: placed)
        }
        if animated {
            canvas.layoutIfNeeded()
        }
    }

    private func applyCenter(of asset: OnboardingStageLayout.Asset, to placed: PlacedAsset) {
        let width = canvas.bounds.width
        let height = canvas.bounds.height
        guard width > 0, height > 0 else { return }
        placed.centerX.constant = (asset.center.x - 0.5) * width
        placed.centerY.constant = (asset.center.y - 0.5) * height
    }

}

private final class StageAssetView: UIView {

    private let symbolView = UIImageView()
    private let phraseLabel = UILabel()

    init(kind: OnboardingStageLayout.Asset.Kind) {
        super.init(frame: .zero)
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .label
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        phraseLabel.font = .systemFont(ofSize: 28, weight: .bold)
        phraseLabel.textColor = .label
        phraseLabel.textAlignment = .center
        phraseLabel.adjustsFontSizeToFitWidth = true
        phraseLabel.minimumScaleFactor = 0.7
        phraseLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(symbolView)
        addSubview(phraseLabel)

        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 34),
            symbolView.heightAnchor.constraint(equalToConstant: 34),

            phraseLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            phraseLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            phraseLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        switch kind {
        case .symbol(let name):
            let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            symbolView.image = UIImage(systemName: name, withConfiguration: config)
            symbolView.isHidden = false
            phraseLabel.isHidden = true
        case .phrase(let text):
            phraseLabel.text = text
            phraseLabel.isHidden = false
            symbolView.isHidden = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }
}
