import UIKit

final class OnboardingSurveyViewController: OnboardingViewController {

    private let question: SurveyQuestion
    private let ctaText: String
    private var collectionView: UICollectionView!
    private var selectedTitles: Set<String> = []

    init(question: SurveyQuestion, ctaText: String?) {
        self.question = question
        self.ctaText = ctaText ?? "Next"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: question.title, subtitle: question.subtitle)
        super.viewDidLoad()
        addCTAButton(title: ctaText)
        setCTAEnabled(false)
    }

    override func setupContent() {
        let layout = makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = question.isMultiSelect
        collectionView.alwaysBounceVertical = true
        collectionView.register(OnboardingOptionCell.self, forCellWithReuseIdentifier: OnboardingOptionCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func ctaTapped() {
        guard !selectedTitles.isEmpty else { return }
        let answers = question.options.filter { selectedTitles.contains($0) }
        coordinator?.updateSurveyResponses([question.id: answers])
        coordinator?.next()
    }

    private func makeLayout() -> UICollectionViewLayout {
        let columns = question.columnCount
        let itemHeight = columns > 1
            ? OnboardingOptionCell.compactHeight
            : OnboardingOptionCell.preferredHeight
        let interItemSpacing: CGFloat = 12
        let contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 120, trailing: 24)

        return UICollectionViewCompositionalLayout { _, environment in
            let availableWidth = environment.container.effectiveContentSize.width
                - contentInsets.leading
                - contentInsets.trailing
            let itemWidth = columns > 1
                ? floor((availableWidth - interItemSpacing * CGFloat(columns - 1)) / CGFloat(columns))
                : availableWidth

            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .absolute(max(itemWidth, 1)),
                    heightDimension: .absolute(itemHeight)
                )
            )

            let group: NSCollectionLayoutGroup
            if columns > 1 {
                let row = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(itemHeight)
                    ),
                    repeatingSubitem: item,
                    count: columns
                )
                row.interItemSpacing = .fixed(interItemSpacing)
                group = row
            } else {
                group = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(itemHeight)
                    ),
                    subitems: [item]
                )
            }

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = contentInsets
            return section
        }
    }
}

extension OnboardingSurveyViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        question.options.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: OnboardingOptionCell.reuseIdentifier,
            for: indexPath
        ) as! OnboardingOptionCell
        cell.configure(title: question.options[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let title = question.options[indexPath.item]
        if question.isMultiSelect {
            selectedTitles.insert(title)
        } else {
            selectedTitles = [title]
        }
        setCTAEnabled(!selectedTitles.isEmpty)
        playSelectionHaptic()
        if let cell = collectionView.cellForItem(at: indexPath) {
            explodeEmoji(from: cell)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedTitles.remove(question.options[indexPath.item])
        setCTAEnabled(!selectedTitles.isEmpty)
        playSelectionHaptic()
    }
}
