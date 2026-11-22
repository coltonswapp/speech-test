//
//  ClipListViewController.swift
//  shizen
//
//  Experiment entry: clips that are aligned in Studio (Experiments → Clip
//  transcripts). Pull to refresh after aligning a new one.
//

import UIKit

final class ClipListViewController: UITableViewController {

    private var clips: [ClipSummary] = []
    private var isLoading = false
    private var errorText: String?
    private var loadGeneration = 0

    /// Learner level to list clips for (5 = N5 … 1 = N1); nil = every clip.
    /// Debug stand-in until the app has a real learner level to pass.
    private var learnerLevel: Int? = {
        let saved = UserDefaults.standard.integer(forKey: ClipListViewController.learnerLevelKey)
        return (1 ... 5).contains(saved) ? saved : nil
    }() {
        didSet {
            UserDefaults.standard.set(learnerLevel ?? 0, forKey: Self.learnerLevelKey)
        }
    }

    private static let learnerLevelKey = "debug.clips.learnerLevel"

    init() {
        super.init(style: .insetGrouped)
        title = "Clips"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "clip")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "playAll")
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        refreshControl = refresh
        updateLevelMenu()
        reload()
    }

    private func updateLevelMenu() {
        let choices: [Int?] = [nil, 5, 4, 3, 2, 1]
        let actions = choices.map { level in
            UIAction(
                title: level.map { "N\($0) learner" } ?? "All clips",
                state: level == learnerLevel ? .on : .off
            ) { [weak self] _ in
                guard let self, self.learnerLevel != level else { return }
                self.learnerLevel = level
                self.updateLevelMenu()
                self.reload()
            }
        }
        let levelItem = UIBarButtonItem(
            title: learnerLevel.map { "N\($0)" } ?? "Level",
            menu: UIMenu(title: "Show clips for", children: actions)
        )
        let feedItem = UIBarButtonItem(
            image: UIImage(systemName: "rectangle.stack.badge.play"),
            primaryAction: UIAction { [weak self] _ in self?.openFeed() }
        )
        feedItem.accessibilityLabel = "Open feed"
        navigationItem.rightBarButtonItems = [levelItem, feedItem]
    }

    /// The feed-eligible clips (same level filter) as a swipeable feed.
    private func openFeed() {
        let feed = ClipFeedViewController(learnerLevel: learnerLevel)
        feed.analyticsSource = ClipAnalytics.list
        navigationController?.pushViewController(feed, animated: true)
    }

    @objc private func reload() {
        // Each load supersedes the last, so switching level mid-load can't show stale clips.
        loadGeneration += 1
        let generation = loadGeneration
        let level = learnerLevel
        isLoading = true
        errorText = nil
        tableView.reloadData()
        Task { [weak self] in
            let result: Result<[ClipSummary], Error>
            do {
                result = .success(try await ContentCMSClient.fetchClipList(learnerLevel: level))
            } catch {
                result = .failure(error)
            }
            guard let self, self.loadGeneration == generation else { return }
            switch result {
            case .success(let clips): self.clips = clips
            case .failure(let error): self.errorText = error.localizedDescription
            }
            self.isLoading = false
            self.refreshControl?.endRefreshing()
            self.tableView.reloadData()
        }
    }

    /// Section 0: "Play All" (once clips are listed). Section 1: the clips.
    private static let playAllSection = 0
    private static let clipsSection = 1

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == Self.playAllSection ? (clips.isEmpty ? 0 : 1) : clips.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == Self.clipsSection else { return nil }
        if let errorText { return "Couldn’t load clips. \(errorText)" }
        if isLoading && clips.isEmpty { return "Loading…" }
        if clips.isEmpty, let learnerLevel {
            return "No clips rated N\(learnerLevel) or easier yet. Rate clips in Studio (6. Level), or choose All clips."
        }
        if clips.isEmpty {
            return "No aligned clips yet. Create one in Studio → Experiments → Clip transcripts and run Align."
        }
        return "YouTube clips with word-synced transcripts from Studio."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Self.playAllSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "playAll", for: indexPath)
            var content = UIListContentConfiguration.cell()
            content.text = "Play All"
            let feedCount = clips.filter(\.isInFeed).count
            content.secondaryText = feedCount == 1 ? "1 clip in the feed" : "\(feedCount) of \(clips.count) clips in the feed"
            content.textProperties.color = .tintColor
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: "play.fill")
            content.imageProperties.tintColor = .tintColor
            cell.contentConfiguration = content
            cell.accessibilityTraits = .button
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip", for: indexPath)
        let clip = clips[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = clip.jlptLevel.map { "\(clip.clipID) · N\($0)" } ?? clip.clipID
        content.secondaryText = [
            [clip.title, clip.channelName].compactMap { $0 }.joined(separator: " · "),
            "\(Self.formatTime(clip.startSec))–\(Self.formatTime(clip.endSec)) · \(clip.sentenceCount) sentences"
                + (clip.isPortrait ? " · Short" : ""),
            clip.previewJP,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        content.secondaryTextProperties.numberOfLines = 3
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "play.rectangle")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Self.playAllSection {
            openFeed()
            return
        }
        let clip = clips[indexPath.row]
        let player = ClipPlayerViewController(clipID: clip.clipID, preview: clip)
        player.analyticsSource = ClipAnalytics.list
        navigationController?.pushViewController(player, animated: true)
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
