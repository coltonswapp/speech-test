//
//  LanguageProgressSnakeExperimentViewController.swift
//  shizen
//
//  Debug experiment: a Duolingo-style vertical lesson path with alternating (snaking) nodes.
//

import UIKit


// MARK: - Public

final class LanguageProgressSnakeExperimentViewController: UIViewController {

    private var lessons: [Lesson] = Lesson.samplePath
    private var selectedIndex: Int = Lesson.samplePath.firstIndex { $0.state == .current } ?? 0

    private let scrollView = UIScrollView()
    private let pathContainer = UIView()
    private let bottomCard = UIView()
    private let lessonTitleLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private var nodeViews: [LessonNodeView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Progress path"
        view.backgroundColor = ExperimentPalette.pageBackground
        configureScroll()
        configureBottomCard()
        rebuildPath()
        updateBottomCard()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = bottomCard.bounds.height + view.safeAreaInsets.bottom + 8
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    private func configureScroll() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let header = LevelHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        pathContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(header)
        scrollView.addSubview(pathContainer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),

            pathContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            pathContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pathContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pathContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            pathContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func configureBottomCard() {
        bottomCard.backgroundColor = .systemBackground
        bottomCard.layer.cornerRadius = 22
        bottomCard.layer.cornerCurve = .continuous
        bottomCard.layer.shadowColor = UIColor.black.cgColor
        bottomCard.layer.shadowOpacity = 0.08
        bottomCard.layer.shadowRadius = 16
        bottomCard.layer.shadowOffset = CGSize(width: 0, height: 4)
        bottomCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomCard)

        lessonTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        lessonTitleLabel.numberOfLines = 2
        lessonTitleLabel.textAlignment = .center
        lessonTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        config.baseForegroundColor = .white
        config.title = "Start"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 17, weight: .semibold)
            return out
        }
        startButton.configuration = config
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addAction(UIAction { [weak self] _ in
            self?.startTapped()
        }, for: UIControl.Event.touchUpInside)

        let stack = UIStackView(arrangedSubviews: [lessonTitleLabel, startButton])
        stack.axis = NSLayoutConstraint.Axis.vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomCard.addSubview(stack)

        NSLayoutConstraint.activate([
            bottomCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: bottomCard.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: bottomCard.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: bottomCard.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomCard.bottomAnchor, constant: -18),

            startButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func rebuildPath() {
        nodeViews.forEach { $0.removeFromSuperview() }
        nodeViews = []

        let rowHeight: CGFloat = 96
        let offset: CGFloat = min(88, (view.bounds.width - 80) * 0.22)
        var previousBottom = pathContainer.topAnchor

        for (index, lesson) in lessons.enumerated() {
            let node = LessonNodeView(lesson: lesson)
            node.translatesAutoresizingMaskIntoConstraints = false
            node.onTap = { [weak self] in self?.selectLesson(at: index) }
            pathContainer.addSubview(node)
            nodeViews.append(node)

            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            NSLayoutConstraint.activate([
                node.topAnchor.constraint(equalTo: previousBottom),
                node.centerXAnchor.constraint(
                    equalTo: pathContainer.centerXAnchor,
                    constant: direction * offset
                ),
                node.widthAnchor.constraint(equalTo: pathContainer.widthAnchor, constant: -32),
                node.heightAnchor.constraint(equalToConstant: rowHeight),
            ])
            previousBottom = node.bottomAnchor
        }

        previousBottom.constraint(equalTo: pathContainer.bottomAnchor).isActive = true

        for (i, node) in nodeViews.enumerated() {
            node.setSelected(i == selectedIndex)
        }
        layoutIfNeededOnNodes()
    }

    private func layoutIfNeededOnNodes() {
        pathContainer.setNeedsLayout()
        pathContainer.layoutIfNeeded()
        nodeViews.forEach { $0.refreshHighlight() }
    }

    private func selectLesson(at index: Int) {
        guard lessons.indices.contains(index) else { return }
        selectedIndex = index
        UIView.transition(with: lessonTitleLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.updateBottomCard()
        }
        for (i, v) in nodeViews.enumerated() {
            v.setSelected(i == selectedIndex)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateBottomCard() {
        lessonTitleLabel.text = lessons[selectedIndex].title
    }

    private func startTapped() {
        let message =
            lessons[selectedIndex].state == .locked
            ? "This lesson is still locked. In a full flow, you’d jump into the activity."
            : "Experiment only — hook your lesson flow here."
        let alert = UIAlertController(title: lessons[selectedIndex].title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Model

private struct Lesson {
    enum State {
        case completed
        case current
        case locked
    }

    let title: String
    let state: State

    static let samplePath: [Lesson] = [
        Lesson(title: "Writing Programs", state: .completed),
        Lesson(title: "Sequencing Commands", state: .current),
        Lesson(title: "Variables", state: .locked),
        Lesson(title: "Conditionals", state: .locked),
        Lesson(title: "Loops", state: .locked),
        Lesson(title: "Functions", state: .locked),
        Lesson(title: "Review", state: .locked),
        Lesson(title: "Project", state: .locked),
    ]
}

// MARK: - Level header

private final class LevelHeaderView: UIView {

    private let levelLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        layer.borderColor = UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 0.55).cgColor

        levelLabel.text = "LEVEL 1"
        levelLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        levelLabel.textColor = UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        levelLabel.textAlignment = .center

        titleLabel.text = "Taking the First Steps"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [levelLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Lesson node

private final class LessonNodeView: UIView {

    var onTap: (() -> Void)?

    private let lesson: Lesson
    private let titleLabel = UILabel()
    private let platform = UIView()
    private let ringView = UIView()
    private let innerMark = UIView()
    private let badgeView = UIView()

    init(lesson: Lesson) {
        self.lesson = lesson
        super.init(frame: .zero)
        isUserInteractionEnabled = true

        titleLabel.text = lesson.title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        platform.backgroundColor = UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        platform.layer.cornerRadius = 22
        platform.layer.shadowColor = UIColor.black.cgColor
        platform.layer.shadowOpacity = 0.12
        platform.layer.shadowRadius = 6
        platform.layer.shadowOffset = CGSize(width: 0, height: 3)
        platform.translatesAutoresizingMaskIntoConstraints = false

        ringView.backgroundColor = .clear
        ringView.layer.borderColor = UIColor.white.cgColor
        ringView.isHidden = true
        ringView.translatesAutoresizingMaskIntoConstraints = false

        innerMark.translatesAutoresizingMaskIntoConstraints = false

        badgeView.backgroundColor = UIColor(red: 0.2, green: 0.78, blue: 0.45, alpha: 1)
        badgeView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        badgeView.layer.cornerRadius = 4
        badgeView.isHidden = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(platform)
        platform.addSubview(ringView)
        platform.addSubview(innerMark)
        addSubview(badgeView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            platform.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            platform.centerXAnchor.constraint(equalTo: centerXAnchor),
            platform.widthAnchor.constraint(equalToConstant: 76),
            platform.heightAnchor.constraint(equalToConstant: 44),
            platform.bottomAnchor.constraint(equalTo: bottomAnchor),

            ringView.centerXAnchor.constraint(equalTo: platform.centerXAnchor),
            ringView.centerYAnchor.constraint(equalTo: platform.centerYAnchor),
            ringView.widthAnchor.constraint(equalTo: platform.widthAnchor, multiplier: 1.34),
            ringView.heightAnchor.constraint(equalTo: platform.heightAnchor, multiplier: 1.45),

            innerMark.centerXAnchor.constraint(equalTo: platform.centerXAnchor),
            innerMark.centerYAnchor.constraint(equalTo: platform.centerYAnchor),
            innerMark.widthAnchor.constraint(equalToConstant: 14),
            innerMark.heightAnchor.constraint(equalToConstant: 14),

            badgeView.centerXAnchor.constraint(equalTo: platform.centerXAnchor),
            badgeView.centerYAnchor.constraint(equalTo: platform.topAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 20),
            badgeView.heightAnchor.constraint(equalToConstant: 20),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ringView.layer.cornerRadius = ringView.bounds.height / 2
        refreshHighlight()
    }

    func refreshHighlight() {
        guard lesson.state == .current else {
            layer.shadowOpacity = 0
            return
        }
        // Glow around the current node: bright on dark backgrounds, the brand purple on light.
        let glow: UIColor = traitCollection.userInterfaceStyle == .dark
            ? .white
            : UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        platform.layer.shadowColor = glow.cgColor
        platform.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.95 : 0.5
        platform.layer.shadowRadius = 8
        platform.layer.shadowOffset = .zero
    }

    func setSelected(_ selected: Bool) {
        switch lesson.state {
        case .locked:
            alpha = selected ? 1 : 0.42
            titleLabel.textColor = selected ? .secondaryLabel : .tertiaryLabel
        case .completed:
            alpha = selected ? 1 : 0.78
            titleLabel.textColor = .tertiaryLabel
        case .current:
            alpha = 1
            titleLabel.textColor = .label
        }
    }

    private func applyState() {
        innerMark.subviews.forEach { $0.removeFromSuperview() }
        innerMark.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        switch lesson.state {
        case .completed:
            titleLabel.textColor = .tertiaryLabel
            titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
            innerMark.backgroundColor = .clear
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = .white
            check.translatesAutoresizingMaskIntoConstraints = false
            innerMark.addSubview(check)
            NSLayoutConstraint.activate([
                check.centerXAnchor.constraint(equalTo: innerMark.centerXAnchor),
                check.centerYAnchor.constraint(equalTo: innerMark.centerYAnchor),
            ])
            ringView.isHidden = true
            badgeView.isHidden = true

        case .current:
            titleLabel.textColor = .label
            titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
            ringView.isHidden = false
            ringView.layer.borderWidth = 4
            badgeView.isHidden = false
            innerMark.backgroundColor = .black
            innerMark.layer.cornerRadius = 3
            alpha = 1

        case .locked:
            titleLabel.textColor = .secondaryLabel
            titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
            platform.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.32, alpha: 1)
                    : UIColor(white: 0.82, alpha: 1)
            }
            ringView.isHidden = true
            badgeView.isHidden = true
            innerMark.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.55, alpha: 1)
                    : UIColor(white: 0.55, alpha: 1)
            }
            innerMark.layer.cornerRadius = 7
            alpha = 0.55
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}

