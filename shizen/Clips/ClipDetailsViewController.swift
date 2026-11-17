//
//  ClipDetailsViewController.swift
//  shizen
//
//  Clip Details sheet (options menu → Clip Details): the source video's title,
//  channel, and what the clip covers, with links out to YouTube, plus the
//  other clips cut from the same video, and its catalog tags (tap one for
//  more clips with that tag). A Japanese title gets an English rendering from
//  the on-device model when available.
//

import FoundationModels
import SwiftUI
import UIKit

/// Presents `ClipDetailsView` in a sheet with its own nav bar and Done button.
final class ClipDetailsViewController: UIHostingController<ClipDetailsView> {
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
        super.init(rootView: ClipDetailsView(
            details: ClipDetails(payload: payload),
            onSelectClip: onSelectClip,
            onPlayAll: onPlayAll
        ))
        if let onPlayFeed {
            rootView.onSelectTag = { [weak self] filter in
                self?.navigationController?.pushViewController(
                    ClipExplorerViewController(selected: [filter], onPlay: onPlayFeed),
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
        }
        return nav
    }
}

/// What the details screen shows, read once from the payload.
struct ClipDetails {
    let clipID: String
    let videoID: String
    let title: String?
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

    init(payload: ClipPayload) {
        let media = payload.media
        let trimmed: (String?) -> String? = { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        clipID = payload.clipID
        videoID = media.videoID
        title = trimmed(media.title)
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

struct ClipDetailsView: View {
    let details: ClipDetails
    /// A clip picked under "More From This Video". Nil hides that section.
    var onSelectClip: ((ClipSummary) -> Void)?
    /// "Play All" under "More From This Video": the whole video's clips as a feed.
    var onPlayAll: (([ClipSummary]) -> Void)?
    /// A tag tapped: more clips with it. Nil makes the tags display-only.
    var onSelectTag: ((ClipTagFilter) -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var translation: TitleTranslation = .idle
    /// The video's other clips, in video order. Empty until loaded, or if there are none.
    @State private var otherClips: [ClipSummary] = []
    /// Every clip from the video, this one included, in video order (for Play All).
    @State private var videoClips: [ClipSummary] = []

    private enum TitleTranslation: Equatable {
        case idle
        case translating
        case done(String)
        case unavailable
    }

    var body: some View {
        List {
            Section("Video") {
                titleBlock
            }

            Section("This Clip") {
                if let currentClipNumber, videoClips.count > 1 {
                    LabeledContent("Clip", value: "\(currentClipNumber) of \(videoClips.count)")
                }
                LabeledContent("Length", value: Self.formatTime(max(0, details.endSec - details.startSec)))
                LabeledContent("In the video", value: "\(Self.formatTime(details.startSec))–\(Self.formatTime(details.endSec))")
                LabeledContent("Lines", value: "\(details.lineCount)")
                if details.vocabularyCount > 0 {
                    LabeledContent("Vocabulary", value: "\(details.vocabularyCount)")
                }
                if details.grammarCount > 0 {
                    LabeledContent("Grammar", value: "\(details.grammarCount)")
                }
                LabeledContent("Level", value: details.jlptLevel.map { "N\($0)" } ?? "Not rated")
                if let pace = details.pace {
                    LabeledContent(
                        "Pace",
                        value: "\(pace.label.capitalized) · \(pace.charsPerSec.formatted(.number.precision(.fractionLength(1)))) chars/s"
                    )
                }
                LabeledContent("Format", value: details.isPortrait ? "YouTube Short" : "Video")
            }

            if !details.tagFilters.isEmpty {
                Section {
                    ClipTagFlow(chips: details.tagFilters.map { ClipTagChip(filter: $0) }) { filter in
                        onSelectTag?(filter)
                    }
                    .allowsHitTesting(onSelectTag != nil)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                } header: {
                    Text("Tags")
                } footer: {
                    if onSelectTag != nil {
                        Text("Tap a tag for more clips like this one.")
                    }
                }
            }

            if let onSelectClip, !otherClips.isEmpty {
                Section("More From This Video") {
                    if let onPlayAll, videoClips.count > 1 {
                        Button {
                            onPlayAll(videoClips)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Play All")
                                        .font(.headline)
                                    Text("\(videoClips.count) clips from this video in a feed")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "play.fill")
                            }
                        }
                    }
                    // Every clip in video order, numbered, with this one marked in place
                    // so it's clear what comes before and after it.
                    ForEach(Array(videoClips.enumerated()), id: \.element.clipID) { index, clip in
                        if clip.clipID == details.clipID {
                            clipRow(clip, number: index + 1, isCurrent: true)
                        } else {
                            Button {
                                onSelectClip(clip)
                            } label: {
                                clipRow(clip, number: index + 1, isCurrent: false)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }

            Section {
                if let url = details.videoURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in YouTube", systemImage: "play.rectangle.fill")
                    }
                }
                if let url = details.channelURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("View Channel", systemImage: "person.crop.square")
                    }
                }
                if let url = details.videoURL {
                    ShareLink(item: url) {
                        Label("Share Video", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("Opens the full video at the start of this clip.")
            }
        }
        .listStyle(.insetGrouped)
        .task { await translateTitle() }
        .task { await loadOtherClips() }
    }

    /// This clip's 1-based place among the video's clips, once they've loaded.
    private var currentClipNumber: Int? {
        videoClips.firstIndex { $0.clipID == details.clipID }.map { $0 + 1 }
    }

    private func clipRow(_ clip: ClipSummary, number: Int, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isCurrent ? Color.accentColor : Color(.tertiarySystemFill))
                )
            VStack(alignment: .leading, spacing: 2) {
                if isCurrent {
                    Text("Current Clip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .textCase(.uppercase)
                }
                Text(clip.previewJP.isEmpty ? clip.clipID : clip.previewJP)
                    .font(.body)
                    .lineLimit(2)
                Text(
                    ["\(Self.formatTime(clip.startSec))–\(Self.formatTime(clip.endSec))",
                     clip.jlptLevel.map { "N\($0)" }]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isCurrent {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Clip \(number) of \(videoClips.count)\(isCurrent ? ", current clip" : ""), "
                + (clip.previewJP.isEmpty ? clip.clipID : clip.previewJP)
        )
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : nil)
    }

    /// Best effort: on any failure the section just stays hidden.
    private func loadOtherClips() async {
        guard onSelectClip != nil, otherClips.isEmpty else { return }
        guard let clips = try? await ContentCMSClient.fetchClipList(videoID: details.videoID) else { return }
        // Checked here too: a server from before `video_id` ignores it and sends every clip.
        videoClips = clips
            .filter { $0.videoID == details.videoID }
            .sorted { $0.startSec < $1.startSec }
        otherClips = videoClips.filter { $0.clipID != details.clipID }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(details.title ?? "Untitled video")
                .font(.headline)
                .foregroundStyle(details.title == nil ? .secondary : .primary)
                .textSelection(.enabled)
            switch translation {
            case .translating:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Translating…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            case .done(let english):
                Text(english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("English title: \(english)")
            case .idle, .unavailable:
                EmptyView()
            }
            if let channel = details.channelName {
                Label(channel, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            if details.isDeprecated {
                Label("Retired clip — the video may no longer be available.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: translation)
    }

    private func translateTitle() async {
        guard translation == .idle,
              let title = details.title,
              ClipTitleTranslator.needsTranslation(title) else { return }
        guard ClipTitleTranslator.isAvailable else {
            translation = .unavailable
            return
        }
        translation = .translating
        if let english = await ClipTitleTranslator.translate(title) {
            translation = .done(english)
        } else {
            translation = .unavailable
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
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
