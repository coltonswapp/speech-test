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
        let itemHeight = OnboardingOptionCell.preferredHeight
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let group: NSCollectionLayoutGroup
        if columns > 1 {
            let horizontal = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            horizontal.interItemSpacing = .fixed(12)
            group = horizontal
        } else {
            group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        }

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 120, trailing: 24)
        return UICollectionViewCompositionalLayout(section: section)
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
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedTitles.remove(question.options[indexPath.item])
        setCTAEnabled(!selectedTitles.isEmpty)
    }
}
