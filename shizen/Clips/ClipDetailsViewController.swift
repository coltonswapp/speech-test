//
//  ClipDetailsViewController.swift
//  shizen
//
//  Clip Details sheet (options menu → Clip Details): the source video's title,
//  channel, and what the clip covers, with links out to YouTube, plus the
//  other clips cut from the same video, and its catalog tags (tap one for
//  more clips with that tag). A Japanese title gets an English rendering from
//  the on-device model when available. An inset-grouped table.
//

import CSFeedbackKitUI
import FoundationModels
import UIKit

final class ClipDetailsViewController: UITableViewController {
    private enum Section {
        case video
        case clip
        case tags
        case moreFromVideo
        case links
        case feedback
        #if DEBUG
        case debug
        #endif
    }

    private enum MoreRow {
        case playAll
        /// Index into `videoClips`.
        case clip(Int)
    }

    private enum LinkRow {
        /// Every (feed) clip from this video's channel, in the app.
        case moreFromChannel(String)
        case openVideo(URL)
        case viewChannel(URL)
        case share(URL)
    }

    private enum FeedbackRow {
        case rating
        case report
    }

    let details: ClipDetails
    /// A clip picked under "More From This Video". Nil hides that section.
    private let onSelectClip: ((ClipSummary) -> Void)?
    /// "Play All" under "More From This Video": the whole video's clips as a feed.
    private let onPlayAll: (([ClipSummary]) -> Void)?
    /// A tag tapped: more clips with it. Nil makes the tags display-only.
    private var onSelectTag: ((ClipTagFilter) -> Void)?
    /// "More From This Channel" tapped: the channel's clips in the app. Nil hides the row.
    private var onSelectChannel: ((String) -> Void)?

    /// Every clip from the video, this one included, in video order. Empty until
    /// loaded, or if there are none.
    private var videoClips: [ClipSummary] = []
    private var translation: ClipDetailsTitleCell.Translation = .idle
    private var hasRated = false
    #if DEBUG
    private var copiedStudioLink = false
    #endif

    private let titleCell = ClipDetailsTitleCell()
    private lazy var tagsCell = ClipDetailsTagsCell(filters: details.tagFilters) { [weak self] filter in
        self?.onSelectTag?(filter)
    }
    private lazy var ratingCell: ClipDetailsRatingCell = {
        let cell = ClipDetailsRatingCell(clipID: details.clipID)
        cell.onRated = { [weak self] in self?.setRated() }
        return cell
    }()

    /// `onSelectClip`: a clip picked under "More From This Video". Nil hides that section.
    /// `onPlayAll`: every clip from this video, in video order, for a feed.
    /// `onPlayFeed`: clips picked from a tag's list, as a feed starting at the given one.
    /// Nil hides the tags' links (the tags still show).
    init(
        payload: ClipPayload,
        onSelectClip: ((ClipSummary) -> Void)? = nil,
        onPlayAll: (([ClipSummary]) -> Void)? = nil,
        onPlayFeed: (([ClipSummary], Int) -> Void)? = nil
    ) {
        details = ClipDetails(payload: payload)
        self.onSelectClip = onSelectClip
        self.onPlayAll = onPlayAll
        super.init(style: .insetGrouped)
        if let onPlayFeed {
            onSelectTag = { [weak self] filter in
                self?.navigationController?.pushViewController(
                    ClipQueryListViewController(filter: filter, onPlay: onPlayFeed),
                    animated: true
                )
            }
            onSelectChannel = { [weak self] channel in
                self?.navigationController?.pushViewController(
                    ClipQueryListViewController(query: .channel(channel), onPlay: onPlayFeed),
                    animated: true
                )
            }
        }
        title = "Clip Details"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Wraps the details in a navigation controller, shown as a medium/large sheet.
    static func makeSheet(
        payload: ClipPayload,
        onSelectClip: ((ClipSummary) -> Void)? = nil,
        onPlayAll: (([ClipSummary]) -> Void)? = nil,
        onPlayFeed: (([ClipSummary], Int) -> Void)? = nil
    ) -> UINavigationController {
        let nav = UINavigationController(
            rootViewController: ClipDetailsViewController(
                payload: payload,
                onSelectClip: onSelectClip,
                onPlayAll: onPlayAll,
                onPlayFeed: onPlayFeed
            )
        )
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.applySolidNonLargeBackground()
        }
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(ClipDetailsClipCell.self, forCellReuseIdentifier: ClipDetailsClipCell.reuseID)
        tagsCell.isInteractive = onSelectTag != nil
        hasRated = ClipRatingMemory.hasRated(details.clipID)
        ratingCell.setRated(hasRated, animated: false)
        titleCell.configure(details: details, translation: translation)
        Task { await translateTitle() }
        Task { await loadVideoClips() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A rating sent from elsewhere (or before this screen) since it last showed.
        if !hasRated, ClipRatingMemory.hasRated(details.clipID) { setRated() }
    }

    // MARK: - Rows

    private var sections: [Section] {
        var result: [Section] = [.video, .clip]
        if !details.tagFilters.isEmpty { result.append(.tags) }
        if onSelectClip != nil, videoClips.contains(where: { $0.clipID != details.clipID }) {
            result.append(.moreFromVideo)
        }
        result.append(.links)
        result.append(.feedback)
        #if DEBUG
        result.append(.debug)
        #endif
        return result
    }

    /// This clip's 1-based place among the video's clips, once they've loaded.
    private var currentClipNumber: Int? {
        videoClips.firstIndex { $0.clipID == details.clipID }.map { $0 + 1 }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let currentClipNumber, videoClips.count > 1 {
            rows.append(("Clip", "\(currentClipNumber) of \(videoClips.count)"))
        }
        rows.append(("Length", Self.formatTime(max(0, details.endSec - details.startSec))))
        rows.append(("In the video", "\(Self.formatTime(details.startSec))–\(Self.formatTime(details.endSec))"))
        rows.append(("Lines", "\(details.lineCount)"))
        if details.vocabularyCount > 0 { rows.append(("Vocabulary", "\(details.vocabularyCount)")) }
        if details.grammarCount > 0 { rows.append(("Grammar", "\(details.grammarCount)")) }
        rows.append(("Level", details.jlptLevel.map { "N\($0)" } ?? "Not rated"))
        if let pace = details.pace {
            rows.append((
                "Pace",
                "\(pace.label.capitalized) · \(pace.charsPerSec.formatted(.number.precision(.fractionLength(1)))) chars/s"
            ))
        }
        rows.append(("Format", details.isPortrait ? "YouTube Short" : "Video"))
        return rows
    }

    private var moreRows: [MoreRow] {
        let clips = videoClips.indices.map(MoreRow.clip)
        return onPlayAll != nil && videoClips.count > 1 ? [.playAll] + clips : clips
    }

    private var linkRows: [LinkRow] {
        var rows: [LinkRow] = []
        if onSelectChannel != nil, let channel = details.channelName { rows.append(.moreFromChannel(channel)) }
        if let url = details.videoURL { rows.append(.openVideo(url)) }
        if let url = details.channelURL { rows.append(.viewChannel(url)) }
        if let url = details.videoURL { rows.append(.share(url)) }
        return rows
    }

    private var feedbackRows: [FeedbackRow] {
        // Rating and reporting both need a signed-in learner; the footer says so otherwise.
        guard ClipFeedbackClient.canSend else { return [] }
        return [.rating, .report]
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .video, .tags: 1
        case .clip: infoRows.count
        case .moreFromVideo: moreRows.count
        case .links: linkRows.count
        case .feedback: feedbackRows.count
        #if DEBUG
        case .debug: 1
        #endif
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .video: "Video"
        case .clip: "This Clip"
        case .tags: "Tags"
        case .moreFromVideo: "More From This Video"
        case .links: nil
        case .feedback: "Feedback"
        #if DEBUG
        case .debug: "Debug"
        #endif
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sections[section] {
        case .video, .clip, .moreFromVideo: nil
        case .tags: onSelectTag != nil ? "Tap a tag for more clips like this one." : nil
        case .links: "YouTube links leave the app. Open in YouTube starts the full video at this clip."
        case .feedback:
            ClipFeedbackClient.canSend
                ? "Wrong translation or words split wrong? Open a line and use ••• → Report an Issue to point at it."
                : "Sign in to rate clips or report a problem."
        #if DEBUG
        case .debug: details.studioLink
        #endif
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .video:
            return titleCell
        case .tags:
            return tagsCell
        case .clip:
            let (label, value) = infoRows[indexPath.row]
            var content = UIListContentConfiguration.valueCell()
            content.text = label
            content.secondaryText = value
            return plainCell(content, at: indexPath, selectable: false)
        case .moreFromVideo:
            switch moreRows[indexPath.row] {
            case .playAll:
                var content = UIListContentConfiguration.subtitleCell()
                content.image = UIImage(systemName: "play.fill")
                content.imageProperties.tintColor = .tintColor
                content.text = "Play All"
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.textProperties.color = .tintColor
                content.secondaryText = "\(videoClips.count) clips from this video in a feed"
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
                content.secondaryTextProperties.color = .secondaryLabel
                content.textToSecondaryTextVerticalPadding = 2
                return plainCell(content, at: indexPath, selectable: true)
            case .clip(let index):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: ClipDetailsClipCell.reuseID,
                    for: indexPath
                ) as! ClipDetailsClipCell
                let clip = videoClips[index]
                cell.configure(
                    clip: clip,
                    number: index + 1,
                    of: videoClips.count,
                    isCurrent: clip.clipID == details.clipID
                )
                return cell
            }
        case .links:
            var content = UIListContentConfiguration.cell()
            switch linkRows[indexPath.row] {
            case .moreFromChannel(let channel):
                content = UIListContentConfiguration.subtitleCell()
                content.text = "More From This Channel"
                content.image = UIImage(systemName: "square.stack")
                content.secondaryText = channel
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
                content.secondaryTextProperties.color = .secondaryLabel
                content.textToSecondaryTextVerticalPadding = 2
                let cell = actionCell(content, at: indexPath)
                cell.accessoryType = .disclosureIndicator
                return cell
            case .openVideo:
                content.text = "Open in YouTube"
                content.image = UIImage(systemName: "play.rectangle.fill")
            case .viewChannel:
                content.text = "View Channel on YouTube"
                content.image = UIImage(systemName: "person.crop.square")
            case .share:
                content.text = "Share Video"
                content.image = UIImage(systemName: "square.and.arrow.up")
            }
            return actionCell(content, at: indexPath)
        case .feedback:
            switch feedbackRows[indexPath.row] {
            case .rating:
                return ratingCell
            case .report:
                var content = UIListContentConfiguration.cell()
                content.text = "Report a Problem"
                content.image = UIImage(systemName: "exclamationmark.bubble")
                return actionCell(content, at: indexPath)
            }
        #if DEBUG
        case .debug:
            var content = UIListContentConfiguration.cell()
            content.text = copiedStudioLink ? "Copied Studio Link" : "Copy Studio Link"
            content.image = UIImage(systemName: copiedStudioLink ? "checkmark" : "doc.on.doc")
            return actionCell(content, at: indexPath)
        #endif
        }
    }

    /// A row that does something: tinted text and icon, like a button.
    private func actionCell(_ content: UIListContentConfiguration, at indexPath: IndexPath) -> UITableViewCell {
        var content = content
        content.textProperties.color = .tintColor
        content.imageProperties.tintColor = .tintColor
        let cell = plainCell(content, at: indexPath, selectable: true)
        cell.accessibilityTraits = .button
        return cell
    }

    private func plainCell(
        _ content: UIListContentConfiguration,
        at indexPath: IndexPath,
        selectable: Bool
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentConfiguration = content
        cell.selectionStyle = selectable ? .default : .none
        cell.accessoryType = .none
        cell.accessibilityTraits = selectable ? .button : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch sections[indexPath.section] {
        case .video, .clip, .tags: false
        case .moreFromVideo:
            switch moreRows[indexPath.row] {
            case .playAll: true
            case .clip(let index): videoClips[index].clipID != details.clipID
            }
        case .links: true
        case .feedback: feedbackRows[indexPath.row] == .report
        #if DEBUG
        case .debug: true
        #endif
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .video, .clip, .tags:
            break
        case .moreFromVideo:
            switch moreRows[indexPath.row] {
            case .playAll:
                onPlayAll?(videoClips)
            case .clip(let index):
                let clip = videoClips[index]
                guard clip.clipID != details.clipID else { return }
                onSelectClip?(clip)
            }
        case .links:
            switch linkRows[indexPath.row] {
            case .moreFromChannel(let channel):
                onSelectChannel?(channel)
            case .openVideo(let url), .viewChannel(let url):
                UIApplication.shared.open(url)
            case .share(let url):
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                present(share, animated: true)
            }
        case .feedback:
            guard feedbackRows[indexPath.row] == .report else { return }
            navigationController?.pushViewController(
                ClipIssueReportViewController(clipID: details.clipID, line: nil),
                animated: true
            )
        #if DEBUG
        case .debug:
            UIPasteboard.general.string = details.studioLink
            copiedStudioLink = true
            tableView.reloadRows(at: [indexPath], with: .none)
        #endif
        }
    }

    /// Long-press the title to copy it (or its English).
    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard sections[indexPath.section] == .video else { return nil }
        var actions: [UIAction] = []
        if let title = details.title {
            actions.append(UIAction(title: "Copy Title", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = title
            })
        }
        if case .done(let english) = translation {
            actions.append(UIAction(title: "Copy English Title", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = english
            })
        }
        guard !actions.isEmpty else { return nil }
        return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: actions) })
    }

    // MARK: - Loading

    private func setRated() {
        guard !hasRated else { return }
        hasRated = true
        ratingCell.setRated(true, animated: true)
    }

    /// Best effort: on any failure the section just stays hidden.
    private func loadVideoClips() async {
        guard onSelectClip != nil, videoClips.isEmpty else { return }
        guard let clips = try? await ContentCMSClient.fetchClipList(videoID: details.videoID) else { return }
        // Checked here too: a server from before `video_id` ignores it and sends every clip.
        videoClips = clips
            .filter { $0.videoID == details.videoID }
            .sorted { $0.startSec < $1.startSec }
        guard !videoClips.isEmpty else { return }
        tableView.reloadData()
    }

    private func translateTitle() async {
        if let english = details.titleEN {
            setTranslation(.done(english))
            return
        }
        guard translation == .idle,
              let title = details.title,
              ClipTitleTranslator.needsTranslation(title),
              ClipTitleTranslator.isAvailable else { return }
        setTranslation(.translating)
        if let english = await ClipTitleTranslator.translate(title) {
            setTranslation(.done(english))
        } else {
            setTranslation(.idle)
        }
    }

    private func setTranslation(_ value: ClipDetailsTitleCell.Translation) {
        guard value != translation else { return }
        translation = value
        titleCell.configure(details: details, translation: value)
        guard tableView.window != nil else { return }
        UIView.animate(withDuration: 0.25) {
            self.tableView.performBatchUpdates(nil)
            self.titleCell.layoutIfNeeded()
        }
    }

    fileprivate static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Cells

/// The video's title, its English (Studio's or translated on device), channel,
/// and a note when the clip is retired.
private final class ClipDetailsTitleCell: UITableViewCell {
    enum Translation: Equatable {
        case idle
        case translating
        case done(String)
    }

    private let titleLabel = UILabel()
    private let translatingRow = UIStackView()
    private let englishLabel = UILabel()
    private let channelRow = UIStackView()
    private let channelLabel = UILabel()
    private let retiredRow = UIStackView()

    init() {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        spinner.startAnimating()
        let translatingLabel = Self.secondaryLabel(text: "Translating…", style: .subheadline)
        translatingRow.addArrangedSubview(spinner)
        translatingRow.addArrangedSubview(translatingLabel)
        translatingRow.spacing = 6
        translatingRow.alignment = .center

        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.adjustsFontForContentSizeCategory = true
        englishLabel.textColor = .secondaryLabel
        englishLabel.numberOfLines = 0

        channelLabel.font = .preferredFont(forTextStyle: .subheadline)
        channelLabel.adjustsFontForContentSizeCategory = true
        channelLabel.textColor = .secondaryLabel
        channelLabel.numberOfLines = 0
        Self.configureIconRow(channelRow, symbol: "person.crop.circle", label: channelLabel, style: .subheadline)

        let retiredLabel = Self.secondaryLabel(
            text: "Retired clip — the video may no longer be available.",
            style: .footnote
        )
        retiredLabel.textColor = .systemOrange
        Self.configureIconRow(retiredRow, symbol: "exclamationmark.triangle", label: retiredLabel, style: .footnote)
        retiredRow.tintColor = .systemOrange

        let stack = UIStackView(arrangedSubviews: [titleLabel, translatingRow, englishLabel, channelRow, retiredRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(8, after: englishLabel)
        stack.setCustomSpacing(8, after: translatingRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: margins.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(details: ClipDetails, translation: Translation) {
        titleLabel.text = details.title ?? "Untitled video"
        titleLabel.textColor = details.title == nil ? .secondaryLabel : .label
        translatingRow.isHidden = translation != .translating
        if case .done(let english) = translation {
            englishLabel.text = english
            englishLabel.accessibilityLabel = "English title: \(english)"
            englishLabel.isHidden = false
        } else {
            englishLabel.isHidden = true
        }
        channelLabel.text = details.channelName
        channelRow.isHidden = details.channelName == nil
        retiredRow.isHidden = !details.isDeprecated
    }

    private static func secondaryLabel(text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private static func configureIconRow(_ row: UIStackView, symbol: String, label: UILabel, style: UIFont.TextStyle) {
        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(textStyle: style)
        ))
        icon.tintColor = label.textColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        row.spacing = 6
        row.alignment = .firstBaseline
    }
}

/// The clip's catalog tags as a wrapping flow of glass hashtag pills.
private final class ClipDetailsTagsCell: UITableViewCell {
    private static let insets = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
    private let flow = GlassTagFlowView()

    /// Off: the pills only display.
    var isInteractive = true {
        didSet { flow.isUserInteractionEnabled = isInteractive }
    }

    init(filters: [ClipTagFilter], onTap: @escaping (ClipTagFilter) -> Void) {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        backgroundConfiguration = .clear()
        flow.setTags(filters.map { filter in
            let pill = GlassTagControl(title: filter.hashtag)
            pill.isToggleable = false
            pill.addAction(UIAction { _ in onTap(filter) }, for: .primaryActionTriggered)
            return pill
        })
        contentView.addSubview(flow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        flow.frame = contentView.bounds.inset(by: Self.insets)
    }

    /// The flow's wrapped height at the table's width (it lays out by frame, not constraints).
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width - Self.insets.left - Self.insets.right
        let height = flow.sizeThatFits(CGSize(width: width, height: 0)).height
        return CGSize(width: targetSize.width, height: height + Self.insets.top + Self.insets.bottom)
    }
}

/// "Good clip for learning?" with the glass thumbs; a thank-you once rated.
private final class ClipDetailsRatingCell: UITableViewCell {
    var onRated: (() -> Void)?

    private let clipID: String
    private let label = UILabel()
    private let thumbs = LLMFeedbackRow()
    private var isRated = false
    private var didPresentThumbs = false

    init(clipID: String) {
        self.clipID = clipID
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        thumbs.setContentHuggingPriority(.required, for: .horizontal)
        thumbs.setContentCompressionResistancePriority(.required, for: .horizontal)
        thumbs.onVisibilityChange = { [weak self] in
            guard let self, self.thumbs.isHidden, ClipRatingMemory.hasRated(clipID) else { return }
            self.onRated?()
        }

        let row = UIStackView(arrangedSubviews: [label, thumbs])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: margins.topAnchor),
            row.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: LLMFeedbackRow.diameter),
        ])
        applyRated()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRated(_ rated: Bool, animated: Bool) {
        guard rated != isRated else { return }
        isRated = rated
        guard animated else { return applyRated() }
        UIView.transition(with: contentView, duration: 0.25, options: .transitionCrossDissolve) {
            self.applyRated()
        }
    }

    private func applyRated() {
        label.text = isRated ? "Thanks for rating this clip" : "Good clip for learning?"
        label.textColor = isRated ? .secondaryLabel : .label
        if isRated { thumbs.isHidden = true }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didPresentThumbs, !isRated else { return }
        didPresentThumbs = true
        // After the first layout, so the thumbs' split animation has a frame to run in.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRated else { return }
            self.thumbs.present(subject: ClipFeedbackClient.ratingSubject(clipID: self.clipID))
        }
    }
}

/// One of the video's clips, numbered in video order; the current one is marked in place.
private final class ClipDetailsClipCell: UITableViewCell {
    static let reuseID = "clip"

    private let numberLabel = UILabel()
    private let currentLabel = UILabel()
    private let previewLabel = UILabel()
    private let detailLabel = UILabel()
    private var isCurrent = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        numberLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        )
        numberLabel.textAlignment = .center
        numberLabel.layer.cornerRadius = 14
        numberLabel.layer.masksToBounds = true

        currentLabel.text = "CURRENT CLIP"
        currentLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        currentLabel.adjustsFontForContentSizeCategory = true
        currentLabel.textColor = .tintColor

        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.numberOfLines = 2

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel

        let text = UIStackView(arrangedSubviews: [currentLabel, previewLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(numberLabel)
        contentView.addSubview(text)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            numberLabel.heightAnchor.constraint(equalToConstant: 28),

            text.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            text.topAnchor.constraint(equalTo: margins.topAnchor),
            text.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(clip: ClipSummary, number: Int, of total: Int, isCurrent: Bool) {
        self.isCurrent = isCurrent
        let preview = clip.previewJP.isEmpty ? clip.clipID : clip.previewJP
        numberLabel.text = "\(number)"
        currentLabel.isHidden = !isCurrent
        previewLabel.text = preview
        detailLabel.text = [
            "\(ClipDetailsViewController.formatTime(clip.startSec))–\(ClipDetailsViewController.formatTime(clip.endSec))",
            clip.jlptLevel.map { "N\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        accessoryType = isCurrent ? .none : .disclosureIndicator
        selectionStyle = isCurrent ? .none : .default
        accessibilityLabel = "Clip \(number) of \(total)\(isCurrent ? ", current clip" : ""), " + preview
        accessibilityTraits = isCurrent ? .none : .button
        applyTint()
        setNeedsUpdateConfiguration()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTint()
        setNeedsUpdateConfiguration()
    }

    private func applyTint() {
        numberLabel.textColor = isCurrent ? .white : .secondaryLabel
        numberLabel.backgroundColor = isCurrent ? tintColor : .tertiarySystemFill
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        if isCurrent { background.backgroundColor = tintColor.withAlphaComponent(0.12) }
        backgroundConfiguration = background
    }
}

// MARK: - CSFeedbackKit context

/// The clip being looked at, as declared fields (see CSFeedback.json).
extension ClipDetailsViewController: FeedbackContextProvider {
    func feedbackValues() -> FeedbackValues {
        let details = self.details
        var values: FeedbackValues = [
            "qaSource": .string("screen"),
            "focusTitle": .string("Clip"),
            "clipId": .string(details.clipID),
            "videoId": .string(details.videoID),
            "studioLink": .string(details.studioLink),
            "focus": .strings(details.feedbackFocusLines),
        ]
        if let title = details.title { values["videoTitle"] = .string(title) }
        if let channel = details.channelName { values["channelName"] = .string(channel) }
        if let url = details.channelURL { values["channelURL"] = .string(url.absoluteString) }
        if let url = details.videoURL { values["youtubeLink"] = .string(url.absoluteString) }
        return values
    }
}

extension ClipDetails {
    /// Readable lines for the note body ("Looking at: Clip" + these).
    var feedbackFocusLines: [String] {
        let time: (Double) -> String = { seconds in
            let total = max(0, Int(seconds.rounded(.down)))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        var lines = ["Clip: \(clipID)"]
        lines.append("Video: \(title ?? "Untitled") (\(videoID))")
        if let titleEN { lines.append("Video (EN): \(titleEN)") }
        if let channelName { lines.append("Channel: \(channelName)") }
        lines.append("In the video: \(time(startSec))–\(time(endSec))")
        lines.append("Level: \(jlptLevel.map { "N\($0)" } ?? "Not rated")")
        if !tagFilters.isEmpty {
            lines.append("Tags: " + tagFilters.map { "\($0.facet.title): \($0.value)" }.joined(separator: ", "))
        }
        if isDeprecated { lines.append("Retired clip") }
        if let videoURL { lines.append("YouTube: \(videoURL.absoluteString)") }
        return lines
    }
}

/// What the details screen shows, read once from the payload.
struct ClipDetails {
    let clipID: String
    let videoID: String
    let title: String?
    /// From Studio; nil when there is none (the screen then translates on device).
    let titleEN: String?
    let channelName: String?
    let channelURL: URL?
    let isPortrait: Bool
    let startSec: Double
    let endSec: Double
    let lineCount: Int
    let vocabularyCount: Int
    let grammarCount: Int
    let jlptLevel: Int?
    /// Catalog tags as filters (format, topics, style, pace, series); empty until tagged.
    let tagFilters: [ClipTagFilter]
    let pace: ClipPace?
    let isDeprecated: Bool
    /// The full video on YouTube, opened at the clip's start.
    let videoURL: URL?
    /// This clip's editor in Studio (not the YouTube video).
    var studioLink: String { ContentCMSClient.studioClipEditorLink(clipID: clipID) }

    init(payload: ClipPayload) {
        let media = payload.media
        let trimmed: (String?) -> String? = { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        clipID = payload.clipID
        videoID = media.videoID
        title = trimmed(media.title)
        titleEN = trimmed(media.titleEN)
        channelName = trimmed(media.channelName)
        channelURL = trimmed(media.channelURL).flatMap(URL.init(string:))
        isPortrait = media.isPortrait
        startSec = media.startSec
        endSec = media.endSec
        lineCount = payload.sentences.count
        vocabularyCount = payload.highlights?.vocabulary?.count ?? 0
        grammarCount = payload.highlights?.grammarPatterns?.count ?? 0
        jlptLevel = payload.jlptLevel
        tagFilters = payload.tags?.filters(pace: payload.pace) ?? []
        pace = payload.pace
        isDeprecated = payload.isDeprecated
        let start = Int(media.startSec.rounded(.down))
        videoURL = URL(string: "https://www.youtube.com/watch?v=\(media.videoID)&t=\(start)s")
    }
}

/// English for a Japanese video title, via Apple's on-device model. Results are
/// cached for the session; any failure just means no translation is shown.
enum ClipTitleTranslator {
    private static let instructions = """
    You translate YouTube video titles from Japanese into natural English. \
    Keep names, hashtags, and emoji as they are. \
    Reply with only the English title: no quotes, notes, or romaji.
    """

    @MainActor private static var cache: [String: String] = [:]

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// True when the title has kana or kanji worth translating.
    static func needsTranslation(_ title: String) -> Bool {
        title.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xFF66...0xFF9F: true
            default: false
            }
        }
    }

    @MainActor
    static func translate(_ title: String) async -> String? {
        if let cached = cache[title] { return cached }
        guard isAvailable else { return nil }
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(
                to: Prompt("Title: \(title)"),
                options: GenerationOptions(sampling: .greedy)
            )
            let english = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”「」"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, english != title else { return nil }
            cache[title] = english
            return english
        } catch {
            return nil
        }
    }
}
