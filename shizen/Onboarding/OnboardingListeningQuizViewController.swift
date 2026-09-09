import UIKit

final class OnboardingListeningQuizViewController: OnboardingViewController {

    private let config: ListeningQuizStepConfig
    private var collectionView: UICollectionView!
    private var selectedTitle: String?

    private let meter = SpeakingMeterPillView()
    private let playButton = OnboardingChrome.makeGlassPlayButton()
    private let speaker = WordUtteranceSpeaker()
    private var meterLink: CADisplayLink?
    private var playbackEndWork: DispatchWorkItem?

    private static let sampleJapanese = "お店に行かないといけません。"

    init(config: ListeningQuizStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: config.title, subtitle: config.subtitle)
        super.viewDidLoad()
        addCTAButton(title: config.ctaText ?? "Next")
        setCTAEnabled(false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlaybackPreview()
    }

    override func setupContent() {
        configurePlayerRow()

        let layout = makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = false
        collectionView.register(OnboardingOptionCell.self, forCellWithReuseIdentifier: OnboardingOptionCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 24),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func ctaTapped() {
        guard let selectedTitle else { return }
        coordinator?.updateListeningQuizAnswer([selectedTitle])
        coordinator?.next()
    }

    private func configurePlayerRow() {
        meter.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.accessibilityHint = "Plays a short Japanese phrase"

        view.addSubview(meter)
        view.addSubview(playButton)

        let preferredWidth = meter.widthAnchor.constraint(
            equalTo: view.widthAnchor,
            multiplier: SpeakingMeterPillView.preferredWidthMultiplier
        )
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            preferredWidth,
            meter.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 20),
            meter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            meter.heightAnchor.constraint(equalToConstant: SpeakingMeterPillView.pillHeight),
            meter.widthAnchor.constraint(
                lessThanOrEqualToConstant: SpeakingMeterPillView.maxWidth
            ),

            playButton.centerYAnchor.constraint(equalTo: meter.centerYAnchor),
            playButton.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 12),
            playButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc private func playTapped() {
        stopPlaybackPreview()
        speaker.speak(Self.sampleJapanese)
        meter.setMode(.playback)
        startMeterAnimation()

        let end = DispatchWorkItem { [weak self] in
            self?.meter.setMode(.idle)
            self?.stopMeterAnimation()
        }
        playbackEndWork = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: end)
    }

    private func startMeterAnimation() {
        let link = CADisplayLink(target: self, selector: #selector(pushAnimatedMeterLevel))
        link.add(to: .main, forMode: .common)
        meterLink = link
    }

    private func stopMeterAnimation() {
        meterLink?.invalidate()
        meterLink = nil
        meter.releaseToRest()
    }

    private func stopPlaybackPreview() {
        playbackEndWork?.cancel()
        playbackEndWork = nil
        speaker.stop()
        stopMeterAnimation()
        meter.setMode(.idle)
    }

    @objc private func pushAnimatedMeterLevel() {
        let t = CACurrentMediaTime()
        let pulse = (sin(t * 9.2) + 1) / 2
        let chatter = (sin(t * 17.4) + 1) / 2
        meter.pushLevel(Float(0.28 + pulse * 0.45 + chatter * 0.2))
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(OnboardingOptionCell.preferredHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 120, trailing: 24)
        return UICollectionViewCompositionalLayout(section: section)
    }
}

extension OnboardingListeningQuizViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        config.options.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: OnboardingOptionCell.reuseIdentifier,
            for: indexPath
        ) as! OnboardingOptionCell
        cell.configure(title: config.options[indexPath.item].title)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedTitle = config.options[indexPath.item].title
        setCTAEnabled(true)
    }
}
