//
//  CMSLessonTrackFilterView.swift
//  shizen
//
//  Multi-select track chips for CMS Lessons. All is the default. Tapping a
//  chip from All selects only that chip. Clearing the last chip returns to All.
//  Selecting every chip by hand leaves All off.
//

import UIKit

private nonisolated enum CMSLessonTrackFilterChip: Hashable, Sendable {
    case all
    case track(CMSLessonTrack)
}

final class CMSLessonTrackFilterView: UIView {

    enum Selection: Equatable {
        case all
        case specific(Set<CMSLessonTrack>)
    }

    /// Fires only from a chip tap, after the selection has changed.
    var onSelectionChange: ((Selection) -> Void)?

    var selection: Selection {
        isAllChipActive ? .all : .specific(selectedTracks)
    }

    func includes(_ track: CMSLessonTrack) -> Bool {
        switch selection {
        case .all:
            return true
        case .specific(let tracks):
            return tracks.contains(track)
        }
    }

    private var availableTracks: [CMSLessonTrack] = []
    private var selectedTracks: Set<CMSLessonTrack> = []
    private var isAllChipActive = true

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, CMSLessonTrackFilterChip>!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCollectionView()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CMSLessonTrackFilterView, _: UITraitCollection) in
            view.reconfigureChips()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 55)
    }

    /// Replaces the chips that currently have lessons. Keeps All, or the tracks
    /// still available. Does not notify `onSelectionChange`.
    func setAvailableTracks(_ tracks: [CMSLessonTrack]) {
        let ordered = CMSLessonTrack.allCases.filter { tracks.contains($0) }
        let available = Set(ordered)
        if isAllChipActive {
            selectedTracks = available
        } else {
            selectedTracks.formIntersection(available)
            if selectedTracks.isEmpty {
                isAllChipActive = true
                selectedTracks = available
            }
        }
        availableTracks = ordered
        isHidden = ordered.isEmpty
        applyChips(animated: window != nil)
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize

        collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let registration = UICollectionView.CellRegistration<CMSLessonTrackChipCell, CMSLessonTrackFilterChip> { [weak self] cell, _, chip in
            guard let self else { return }
            switch chip {
            case .all:
                cell.configure(title: "All", isSelected: self.isAllChipActive)
            case .track(let track):
                let selected = !self.isAllChipActive && self.selectedTracks.contains(track)
                cell.configure(title: track.title, isSelected: selected)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, CMSLessonTrackFilterChip>(collectionView: collectionView) {
            collectionView, indexPath, chip in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: chip)
        }

        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func applyChips(animated: Bool) {
        let items = [CMSLessonTrackFilterChip.all] + availableTracks.map { CMSLessonTrackFilterChip.track($0) }
        let previous = dataSource.snapshot().itemIdentifiers
        if previous == items {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(items)
            dataSource.apply(snapshot, animatingDifferences: false)
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, CMSLessonTrackFilterChip>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: animated)

        let overlap = items.filter { previous.contains($0) }
        guard !overlap.isEmpty else { return }
        var refreshed = dataSource.snapshot()
        refreshed.reconfigureItems(overlap)
        dataSource.apply(refreshed, animatingDifferences: false)
    }

    private func reconfigureChips() {
        var snapshot = dataSource.snapshot()
        guard !snapshot.itemIdentifiers.isEmpty else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func selectAll() {
        guard !isAllChipActive else { return }
        isAllChipActive = true
        selectedTracks = Set(availableTracks)
        commitTap()
    }

    private func toggle(_ track: CMSLessonTrack) {
        if isAllChipActive {
            isAllChipActive = false
            selectedTracks = [track]
            commitTap()
            return
        }

        if selectedTracks.contains(track) {
            selectedTracks.remove(track)
        } else {
            selectedTracks.insert(track)
        }

        if selectedTracks.isEmpty {
            isAllChipActive = true
            selectedTracks = Set(availableTracks)
        } else {
            isAllChipActive = false
        }
        commitTap()
    }

    private func commitTap() {
        reconfigureChips()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelectionChange?(selection)
    }
}

extension CMSLessonTrackFilterView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let chip = dataSource.itemIdentifier(for: indexPath) else { return }
        switch chip {
        case .all:
            selectAll()
        case .track(let track):
            toggle(track)
        }
    }
}

private final class CMSLessonTrackChipCell: UICollectionViewCell {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.layer.borderWidth = 1.5

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isSelected: Bool) {
        titleLabel.text = title
        accessibilityLabel = title
        if isSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }

        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            if isSelected {
                self.contentView.backgroundColor = ExperimentPalette.highlightFill
                self.contentView.layer.borderColor = ExperimentPalette.highlightBorder.cgColor
                self.titleLabel.textColor = ExperimentPalette.meaningBadgeText
            } else {
                self.contentView.backgroundColor = ExperimentPalette.cardSurface
                self.contentView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
                self.titleLabel.textColor = .tertiaryLabel
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        accessibilityLabel = nil
    }
}
