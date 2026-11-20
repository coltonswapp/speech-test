//
//  ClipLinkOpener.swift
//  shizen
//
//  Debug: open a clip from a link. Paste a Studio clip URL, a public API URL,
//  a YouTube link, a bare clip id, or search text (Settings → Debug → Clips →
//  Open clip link), or tap a `shizen://clip/<id>` link anywhere on the phone.
//  Recent entries are kept so they're one tap away next time.
//

import UIKit

// MARK: - Parsing

/// What a pasted string or opened URL points at.
nonisolated enum ClipLink: Equatable, Sendable {
    /// A clip id taken from a URL, so certainly a clip.
    case clip(String)
    /// Every clip cut from one YouTube video.
    case video(String)
    /// Bare text that looks like a clip id: tried as an id, searched if no clip has it.
    case clipOrSearch(String)
    case search(String)

    /// Same rule as Studio's `CLIP_ID_PATTERN` (`webapp/lib/experiments/clips/types.ts`).
    static func isClipID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 64
            && text.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }

    /// Accepts:
    /// - `shizen://clip/<id>`, `shizen://video/<youtubeID>`, `shizen://search?q=…`
    /// - Studio `…/experiments/clips/<id>` and `…/experiments/clips/video/<youtubeID>`
    /// - Public API `…/api/public/clips/<id>`
    /// - YouTube `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/` links
    /// - a bare clip id, or anything else as search text
    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.scheme != nil, let link = ClipLink(url: url) {
            self = link
        } else if Self.isClipID(text) {
            self = .clipOrSearch(text)
        } else {
            self = .search(text)
        }
    }

    init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if scheme == "shizen" {
            // shizen://clip/<id> puts "clip" in the host.
            let segments = [host] + parts
            switch segments.first {
            case "clip" where segments.count >= 2 && Self.isClipID(segments[1]):
                self = .clip(segments[1])
            case "video" where segments.count >= 2:
                self = .video(segments[1])
            case "search":
                guard let q = query.first(where: { $0.name == "q" })?.value, !q.isEmpty else { return nil }
                self = .search(q)
            default:
                return nil
            }
            return
        }

        guard scheme == "http" || scheme == "https" else { return nil }

        if host.hasSuffix("youtube.com") || host == "youtu.be" {
            if host == "youtu.be", let id = parts.first {
                self = .video(id)
            } else if let v = query.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                self = .video(v)
            } else if parts.count >= 2, ["shorts", "embed", "live"].contains(parts[0]) {
                self = .video(parts[1])
            } else {
                return nil
            }
            return
        }

        // Studio and public API paths: …/clips/<id> or …/clips/video/<youtubeID>.
        guard let clipsIndex = parts.lastIndex(of: "clips"), clipsIndex + 1 < parts.count else { return nil }
        let next = parts[clipsIndex + 1]
        if next == "video", clipsIndex + 2 < parts.count {
            self = .video(parts[clipsIndex + 2])
        } else if Self.isClipID(next), next != "queue", next != "facets" {
            self = .clip(next)
        } else {
            return nil
        }
    }
}

// MARK: - History

/// The last few things opened from the Open Clip screen or a `shizen://` link, newest first.
nonisolated enum ClipLinkHistory {
    static let limit = 20
    private static let key = "clipLinkHistory.v1"

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var list = entries.filter { $0 != text }
        list.insert(text, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    static func remove(_ text: String) {
        UserDefaults.standard.set(entries.filter { $0 != text }, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Opening

@MainActor
enum ClipLinkOpener {
    enum OpenError: LocalizedError {
        case noClipsForVideo(String)

        var errorDescription: String? {
            switch self {
            case .noClipsForVideo(let id): return "No listed clips come from video \(id)."
            }
        }
    }

    /// The screen a link leads to. Fetches only when the link alone can't say
    /// (a video's clips, or whether bare text is a clip id).
    static func destination(for link: ClipLink) async throws -> UIViewController {
        switch link {
        case .clip(let id):
            return ClipPlayerViewController(clipID: id)
        case .video(let videoID):
            let clips = try await ContentCMSClient.fetchClipList(videoID: videoID)
            guard let first = clips.first else { throw OpenError.noClipsForVideo(videoID) }
            if clips.count == 1 {
                return ClipPlayerViewController(clipID: first.clipID, preview: first)
            }
            return ClipFeedViewController(clips: clips)
        case .clipOrSearch(let text):
            do {
                _ = try await ContentCMSClient.fetchClip(id: text)
                return ClipPlayerViewController(clipID: text)
            } catch ContentCMSClient.CMSClientError.httpStatus(404) {
                return ClipQueryListViewController(query: .search(text))
            }
        case .search(let text):
            return ClipQueryListViewController(query: .search(text))
        }
    }

    /// A `shizen://` link opened from outside the app: shows the clip full screen
    /// over whatever is up, with ✕ to close. Returns false for links that aren't clip links.
    @discardableResult
    static func handleOpenURL(_ url: URL, in window: UIWindow?) -> Bool {
        guard url.scheme?.lowercased() == "shizen", let link = ClipLink(url: url) else { return false }
        ClipLinkHistory.record(url.absoluteString)
        Task { @MainActor in
            guard let presenter = topViewController(in: window) else { return }
            do {
                let screen = try await destination(for: link)
                let nav = UINavigationController(rootViewController: screen)
                screen.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    systemItem: .close,
                    primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
                )
                nav.modalPresentationStyle = .fullScreen
                presenter.present(nav, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: "Couldn’t open clip",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                presenter.present(alert, animated: true)
            }
        }
        return true
    }

    private static func topViewController(in window: UIWindow?) -> UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

// MARK: - Screen

/// Settings → Debug → Clips → Open clip link.
final class ClipLinkViewController: UITableViewController, UITextFieldDelegate {

    private enum Section: Int, CaseIterable {
        case input
        case recents
    }

    private let field = UITextField()
    private var recents: [String] = []
    private var isOpening = false

    init() {
        super.init(style: .insetGrouped)
        title = "Open clip link"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag

        field.placeholder = "Clip URL, YouTube link, clip id, or search"
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.returnKeyType = .go
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            primaryAction: UIAction { [weak self] _ in self?.confirmClear() }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRecents()
    }

    private func reloadRecents() {
        recents = ClipLinkHistory.entries
        navigationItem.rightBarButtonItem?.isEnabled = !recents.isEmpty
        tableView.reloadData()
    }

    // MARK: Opening

    private func open(_ raw: String) {
        guard !isOpening, let link = ClipLink(raw) else { return }
        view.endEditing(true)
        ClipLinkHistory.record(raw)
        reloadRecents()
        isOpening = true
        Task { [weak self] in
            defer { self?.isOpening = false }
            do {
                let screen = try await ClipLinkOpener.destination(for: link)
                self?.navigationController?.pushViewController(screen, animated: true)
            } catch {
                self?.showError(error)
            }
        }
    }

    private func pasteAndOpen() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showError(nil)
            return
        }
        field.text = text
        open(text)
    }

    private func showError(_ error: Error?) {
        let alert = UIAlertController(
            title: error == nil ? "Clipboard is empty" : "Couldn’t open clip",
            message: error?.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func confirmClear() {
        let alert = UIAlertController(title: "Clear recents?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            ClipLinkHistory.clear()
            self?.reloadRecents()
        })
        present(alert, animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        open(textField.text ?? "")
        return false
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .input: return 3
        case .recents: return max(recents.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .input: return nil
        case .recents: return "Recent (last \(ClipLinkHistory.limit))"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .input else { return nil }
        return "Studio /experiments/clips/<id>, /api/public/clips/<id>, YouTube links (every clip from that video), "
            + "a bare clip id, or search text. Links like shizen://clip/<id> open the app from anywhere."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentView.subviews.filter { $0 === field }.forEach { $0.removeFromSuperview() }
        cell.accessoryType = .none
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()

        switch Section(rawValue: indexPath.section)! {
        case .input:
            switch indexPath.row {
            case 0:
                cell.contentConfiguration = nil
                cell.selectionStyle = .none
                cell.contentView.addSubview(field)
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    field.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                    field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                ])
                return cell
            case 1:
                content.text = "Open"
                content.image = UIImage(systemName: "arrow.up.forward.app")
            default:
                content.text = "Paste and open"
                content.image = UIImage(systemName: "doc.on.clipboard")
            }
            content.textProperties.color = .tintColor

        case .recents:
            guard !recents.isEmpty else {
                content.text = "Nothing yet"
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
                cell.contentConfiguration = content
                return cell
            }
            let entry = recents[indexPath.row]
            content.text = entry
            content.textProperties.numberOfLines = 2
            content.textProperties.lineBreakMode = .byTruncatingMiddle
            content.secondaryText = Self.describe(ClipLink(entry))
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: Self.symbol(ClipLink(entry)))
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .input:
            switch indexPath.row {
            case 0: field.becomeFirstResponder()
            case 1: open(field.text ?? "")
            default: pasteAndOpen()
            }
        case .recents:
            guard recents.indices.contains(indexPath.row) else { return }
            open(recents[indexPath.row])
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .recents, recents.indices.contains(indexPath.row) else {
            return nil
        }
        let entry = recents[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            ClipLinkHistory.remove(entry)
            self?.reloadRecents()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard Section(rawValue: indexPath.section) == .recents, recents.indices.contains(indexPath.row) else {
            return nil
        }
        let entry = recents[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                    self?.field.text = entry
                    self?.field.becomeFirstResponder()
                },
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = entry
                },
            ])
        })
    }

    private static func describe(_ link: ClipLink?) -> String {
        switch link {
        case .clip(let id): return "Clip · \(id)"
        case .video(let id): return "Every clip from video \(id)"
        case .clipOrSearch(let text): return "Clip id or search · \(text)"
        case .search(let text): return "Search · \(text)"
        case nil: return ""
        }
    }

    private static func symbol(_ link: ClipLink?) -> String {
        switch link {
        case .clip, .clipOrSearch: return "play.rectangle"
        case .video: return "film.stack"
        case .search, nil: return "magnifyingglass"
        }
    }
}
