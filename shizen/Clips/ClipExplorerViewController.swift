//
//  ClipExplorerViewController.swift
//  shizen
//
//  Debug: explore the clip catalog. Search (title, channel, first line, tag
//  values) and filter by Studio's catalog tags (format, topic, register,
//  speakers, dialect, pace, series) with the QA note's glass hashtag pills.
//  Tap a clip, or Play All, for a feed of the results. Also opened from a tag
//  in Clip Details, with that tag selected.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class ClipExplorerModel {
    private(set) var facets: [ClipTagFilter.Facet: [ContentCMSClient.ClipFacetValue]] = [:]
    private(set) var clips: [ClipSummary] = []
    private(set) var isLoading = false
    private(set) var errorText: String?
    var selected: Set<ClipTagFilter> {
        didSet { if selected != oldValue { reload() } }
    }
    var search = "" {
        didSet { if search != oldValue { reload(debounce: true) } }
    }

    private var loadTask: Task<Void, Never>?

    init(selected: Set<ClipTagFilter>) {
        self.selected = selected
    }

    /// Facet sections in display order; register, speakers and dialect share "Style".
    var sections: [(title: String, chips: [ClipTagChip])] {
        let groups: [(String, [ClipTagFilter.Facet])] = [
            ("Format", [.format]),
            ("Topic", [.topic]),
            ("Style", [.register, .speakers, .dialect]),
            ("Pace", [.pace]),
            ("Series", [.series]),
        ]
        return groups.compactMap { title, facetList in
            var chips: [ClipTagChip] = []
            for facet in facetList {
                let values = facets[facet] ?? []
                chips += values.map { value in
                    let filter = ClipTagFilter(facet: facet, value: value.value)
                    return ClipTagChip(filter: filter, count: value.count, isSelected: selected.contains(filter))
                }
                // A selected tag the counts don't list (e.g. opened from Clip Details) still shows.
                for filter in selected where filter.facet == facet && !values.contains(where: { $0.value == filter.value }) {
                    chips.append(ClipTagChip(filter: filter, isSelected: true))
                }
            }
            return chips.isEmpty ? nil : (title, chips)
        }
    }

    func toggle(_ filter: ClipTagFilter) {
        if selected.contains(filter) { selected.remove(filter) } else { selected.insert(filter) }
    }

    func loadFacets() async {
        guard facets.isEmpty else { return }
        facets = (try? await ContentCMSClient.fetchClipFacets()) ?? [:]
    }

    func reload(debounce: Bool = false) {
        loadTask?.cancel()
        let filters = Array(selected)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        loadTask = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let result: Result<[ClipSummary], Error>
            do {
                result = .success(try await ContentCMSClient.fetchClipList(filters: filters, search: query))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let clips):
                self.clips = Self.locallyFiltered(clips, filters: filters, search: query)
                self.errorText = nil
            case .failure(let error):
                self.errorText = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    /// The server already filters; this repeats it so a server from before
    /// search and tags (which ignores the params) still shows the right clips.
    private static func locallyFiltered(_ clips: [ClipSummary], filters: [ClipTagFilter], search: String) -> [ClipSummary] {
        let byFacet = Dictionary(grouping: filters, by: \.facet)
        return clips.filter { clip in
            for (facet, wanted) in byFacet {
                let values = Set(wanted.map(\.value))
                let has: [String] = switch facet {
                case .format: [clip.tags?.format].compactMap { $0 }
                case .topic: clip.tags?.topics ?? []
                case .register: [clip.tags?.register].compactMap { $0 }
                case .speakers: [clip.tags?.speakers].compactMap { $0 }
                case .dialect: [clip.tags?.dialect].compactMap { $0 }
                case .pace: [clip.pace?.label].compactMap { $0 }
                case .series: [clip.tags?.series].compactMap { $0 }
                }
                if values.isDisjoint(with: has) { return false }
            }
            guard !search.isEmpty else { return true }
            let haystack = [clip.title, clip.channelName, clip.previewJP, clip.clipID]
                + (clip.tags.map { $0.filters(pace: clip.pace).map(\.value) } ?? [])
            return haystack.contains { $0?.localizedCaseInsensitiveContains(search) == true }
        }
    }
}

final class ClipExplorerViewController: UIHostingController<ClipExplorerView>, UISearchResultsUpdating {
    private let model: ClipExplorerModel
    private let onPlay: (([ClipSummary], Int) -> Void)?

    /// `selected`: tags to start filtered by. `onPlay`: play the results as a feed,
    /// starting at the given clip; nil pushes the feed on this navigation stack.
    init(selected: [ClipTagFilter] = [], onPlay: (([ClipSummary], Int) -> Void)? = nil) {
        let model = ClipExplorerModel(selected: Set(selected))
        self.model = model
        self.onPlay = onPlay
        super.init(rootView: ClipExplorerView(model: model, onPlay: { _, _ in }))
        rootView = ClipExplorerView(model: model) { [weak self] clips, start in
            self?.play(clips, startingAt: start)
        }
        title = selected.count == 1 ? selected[0].hashtag : "Explore Clips"
    }

    private func play(_ clips: [ClipSummary], startingAt start: Int) {
        if let onPlay {
            onPlay(clips, start)
        } else {
            navigationController?.pushViewController(
                ClipFeedViewController(clips: clips, startingAt: start),
                animated: true
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Title, channel, line or tag"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        model.reload()
    }

    func updateSearchResults(for searchController: UISearchController) {
        model.search = searchController.searchBar.text ?? ""
    }
}

struct ClipExplorerView: View {
    let model: ClipExplorerModel
    var onPlay: ([ClipSummary], Int) -> Void

    var body: some View {
        List {
            ForEach(model.sections, id: \.title) { section in
                Section(section.title) {
                    ClipTagFlow(chips: section.chips, toggles: true) { model.toggle($0) }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
            }

            Section {
                if !model.clips.isEmpty {
                    Button {
                        onPlay(model.clips, 0)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.headline)
                    }
                }
                ForEach(Array(model.clips.enumerated()), id: \.element.clipID) { index, clip in
                    Button {
                        onPlay(model.clips, index)
                    } label: {
                        ClipExplorerRow(clip: clip)
                    }
                    .tint(.primary)
                }
            } header: {
                HStack {
                    Text(resultsTitle)
                    if model.isLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
            } footer: {
                if let error = model.errorText {
                    Text("Couldn’t load clips. \(error)")
                } else if !model.isLoading, model.clips.isEmpty {
                    Text("No clips match. Clear a tag or the search.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: model.clips.map(\.clipID))
        .task { await model.loadFacets() }
        .toolbar {
            if !model.selected.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { model.selected = [] }
                }
            }
        }
    }

    private var resultsTitle: String {
        model.clips.count == 1 ? "1 clip" : "\(model.clips.count) clips"
    }
}

private struct ClipExplorerRow: View {
    let clip: ClipSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(clip.title ?? clip.clipID)
                .font(.body)
                .lineLimit(2)
            Text(clip.previewJP)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts: [String] = []
        if let level = clip.jlptLevel { parts.append("N\(level)") }
        if let tags = clip.tags {
            parts.append(([tags.format] + tags.topics).map { "#\($0.replacingOccurrences(of: "-", with: " "))" }.joined(separator: " "))
        }
        if let pace = clip.pace { parts.append(pace.label) }
        if let channel = clip.channelName { parts.append(channel) }
        return parts.joined(separator: " · ")
    }
}
