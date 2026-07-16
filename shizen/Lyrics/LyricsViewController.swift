//
//  LyricsViewController.swift
//  shizen
//
//  Fullscreen, lyrics-style view of a TTS utterance.
//
//  White background, sentences stacked in large bold text. The sentence that's
//  currently playing is rendered in full black; every other sentence is faded
//  to a low-opacity black, mimicking the Apple Music "now-playing lyrics"
//  treatment. Each line includes a smaller English subtitle translated with the
//  system Translation framework (on-device). Playback is driven by an external
//  `TextToSpeechService`; this controller listens to playback advancement and
//  animates emphasis as the playhead moves between sentences.
//

import NaturalLanguage
import SwiftUI
import Translation
import TTSCore
import UIKit

final class LyricsViewController: UIViewController {

  // MARK: - Dependencies

  private let tts: TextToSpeechService

  // MARK: - UI

  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private var contentStackTopConstraint: NSLayoutConstraint!
  private let closeButton = UIButton(type: .system)
  private let playPauseButton = UIButton(type: .system)
  private let footerBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))

  /// Vertical stack per sentence: primary line + English subtitle.
  private var sentenceLineRows: [UIStackView] = []
  private var sentenceLabels: [UILabel] = []
  private var translationLabels: [UILabel] = []
  private var activeSentenceIndex: Int?

  /// The delegate that was attached to `tts` before we presented; we forward every
  /// callback to it so the underlying TTS view controller keeps updating its own UI
  /// while the lyrics screen is layered on top.
  private weak var previousDelegate: TextToSpeechServiceDelegate?

  /// Runs SwiftUI `.translationTask` so `translate(_:)` uses the same session pipeline as
  /// `SentenceScrubExperimentViewController` (UIKit `TranslationSession(installedSource:)`
  /// alone does not behave the same).
  private var translationBatchHost: UIHostingController<LyricsTranslationRunnerView>?
  /// Ignores completions from superseded translation runs.
  private var translationRequestSerial = 0
  /// `translationTask` may not run until the VC is in a window (modal first layout).
  private var didRerunTranslationAfterAppear = false

  // MARK: - Init

  init(service: TextToSpeechService) {
    self.tts = service
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
    overrideUserInterfaceStyle = .light
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white
    title = "Lyrics"
    previousDelegate = tts.delegate
    tts.delegate = self
    scrollView.delegate = self

    configureScrollView()
    configureCloseButton()
    configureFooter()
    rebuildSentenceLabels()

    syncActiveSentenceFromCurrentPlayback()
    updatePlayPauseButton()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if navigationController?.viewControllers.count == 1 {
      navigationController?.setNavigationBarHidden(true, animated: animated)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !didRerunTranslationAfterAppear {
      didRerunTranslationAfterAppear = true
      if !tts.sentences.isEmpty {
        scheduleTranslationsForAllSentences()
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    DefinitionTipPresenter.dismiss(animateOut: true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || isMovingFromParent {
      removeTranslationBatchHost()
      if tts.delegate === self {
        tts.delegate = previousDelegate
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    contentStackTopConstraint.constant = view.safeAreaInsets.top + 12
    applyVerticalContentInset()
    applyRowLabelStylesForActiveIndex(activeSentenceIndex)
    if let idx = activeSentenceIndex,
      let offset = centeredContentOffset(forActiveIndex: idx)
    {
      scrollView.setClampedContentOffsetY(offset.y, allowsScrollCallback: false)
    }
  }

  // MARK: - Setup

  private func configureScrollView() {
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.alwaysBounceVertical = true
    scrollView.contentInsetAdjustmentBehavior = .never
    view.addSubview(scrollView)

    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.alignment = .fill
    contentStack.spacing = 24
    contentStack.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
    contentStack.isLayoutMarginsRelativeArrangement = true
    scrollView.addSubview(contentStack)

    contentStackTopConstraint = contentStack.topAnchor.constraint(
      equalTo: scrollView.contentLayoutGuide.topAnchor,
      constant: 0)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      contentStackTopConstraint,
      contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
    ])
  }

  private func configureCloseButton() {
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    applyCloseButtonListAppearance()
    closeButton.addAction(
      UIAction { [weak self] _ in
        self?.topChevronTapped()
      }, for: .primaryActionTriggered)
    closeButton.accessibilityLabel = "Close"

    view.addSubview(closeButton)
    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      closeButton.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
    ])
  }

  private func configureFooter() {
    footerBlur.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(footerBlur)

    playPauseButton.translatesAutoresizingMaskIntoConstraints = false
    var cfg = UIButton.Configuration.plain()
    cfg.image = UIImage(
      systemName: "play.circle.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
    )
    cfg.baseForegroundColor = .black
    cfg.contentInsets = .zero
    playPauseButton.configuration = cfg
    playPauseButton.accessibilityLabel = "Play / Pause"
    playPauseButton.addAction(
      UIAction { [weak self] _ in
        self?.togglePlayPause()
      }, for: .primaryActionTriggered)

    footerBlur.contentView.addSubview(playPauseButton)

    NSLayoutConstraint.activate([
      footerBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      footerBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      footerBlur.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      footerBlur.heightAnchor.constraint(equalToConstant: 120),

      playPauseButton.centerXAnchor.constraint(equalTo: footerBlur.centerXAnchor),
      playPauseButton.topAnchor.constraint(equalTo: footerBlur.topAnchor, constant: 14),
    ])
  }

  private func rebuildSentenceLabels() {
    for v in contentStack.arrangedSubviews {
      contentStack.removeArrangedSubview(v)
      v.removeFromSuperview()
    }
    sentenceLineRows.removeAll()
    sentenceLabels.removeAll()
    translationLabels.removeAll()
    applyCloseButtonListAppearance()

    for (idx, sentence) in tts.sentences.enumerated() {
      let lineRow = UIStackView()
      lineRow.translatesAutoresizingMaskIntoConstraints = false
      lineRow.clipsToBounds = false
      lineRow.axis = .vertical
      lineRow.alignment = .fill
      lineRow.spacing = 2

      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.numberOfLines = 0
      label.lineBreakMode = .byWordWrapping
      label.font = Self.lyricFont
      label.textColor = Self.inactiveColor
      label.text = sentence.text
      label.setContentHuggingPriority(.defaultLow, for: .horizontal)
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      let translationLabel = UILabel()
      translationLabel.translatesAutoresizingMaskIntoConstraints = false
      translationLabel.numberOfLines = 0
      translationLabel.lineBreakMode = .byWordWrapping
      translationLabel.font = Self.translationFontLoose
      translationLabel.textColor = Self.inactiveColor
      translationLabel.text = ""
      translationLabel.isHidden = true
      translationLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
      translationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      lineRow.addArrangedSubview(label)
      lineRow.addArrangedSubview(translationLabel)
      contentStack.addArrangedSubview(lineRow)

      lineRow.isUserInteractionEnabled = true
      lineRow.tag = idx
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleLineRowTap(_:)))
      lineRow.addGestureRecognizer(tap)

      sentenceLineRows.append(lineRow)
      sentenceLabels.append(label)
      translationLabels.append(translationLabel)
    }

    closeButton.isHidden = false
    closeButton.accessibilityLabel = "Close"

    scheduleTranslationsForAllSentences()
  }

  /// Apply a uniform scale to `view` while keeping its leading edge (and vertical
  /// center) fixed in place. `UIView.transform` scales from the view's center by
  /// default, so a plain `scaleBy` makes the content slide right as it shrinks.
  private func applyScaleKeepingLeading(_ view: UIView, scale: CGFloat) {
    if abs(scale - 1) < .ulpOfOne {
      view.transform = .identity
      return
    }
    let width = view.bounds.width
    let dx = -width * (1 - scale) / 2
    view.transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale)
  }

  private func applyVerticalContentInset() {
    // Pad with roughly half of the viewport so the first and last sentence can be centered.
    let inset = max(0, view.bounds.height * 0.40)
    scrollView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset + 120, right: 0)
  }

  // MARK: - Dismiss

  private func topChevronTapped() {
    dismiss(animated: true)
  }

  private func applyCloseButtonListAppearance() {
    var cfg = closeButton.configuration ?? .plain()
    cfg.image = UIImage(
      systemName: "chevron.down",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    )
    cfg.baseForegroundColor = UIColor.black.withAlphaComponent(0.6)
    cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    closeButton.configuration = cfg
  }

  // MARK: - Playback

  @objc private func handleLineRowTap(_ gesture: UITapGestureRecognizer) {
    guard let row = gesture.view else { return }
    let idx = row.tag
    guard tts.sentences.indices.contains(idx) else { return }
    let s = tts.sentences[idx]
    guard case .ready = s.state, s.sampleCount > 0 else { return }
    tts.play(sentenceAt: idx)
  }

  // MARK: - Translation (system Translation framework)

  private func scheduleTranslationsForAllSentences() {
    let snapshot = tts.sentences.enumerated().map { ($0.offset, $0.element.text) }
    guard !snapshot.isEmpty else { return }
    runTranslations(for: snapshot)
  }

  private func scheduleTranslation(forSentenceAt index: Int) {
    guard tts.sentences.indices.contains(index) else { return }
    runTranslations(for: [(index, tts.sentences[index].text)])
  }

  private func runTranslations(for items: [(Int, String)]) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      await Task.yield()

      self.translationRequestSerial += 1
      let requestID = self.translationRequestSerial
      let batchID = UUID()

      for (idx, _) in items {
        guard self.translationLabels.indices.contains(idx) else { continue }
        self.translationLabels[idx].isHidden = false
        self.translationLabels[idx].text = "…"
      }

      let indicesNeedingSubtitle = items.compactMap { pair -> Int? in
        lyricsTranslationRoute(for: pair.1) != nil ? pair.0 : nil
      }

      #if targetEnvironment(simulator)
      self.applyTranslationResults(
        requestID: requestID,
        outgoing: [:],
        hideIndices: Set(indicesNeedingSubtitle)
      )
      return
      #endif

      guard !indicesNeedingSubtitle.isEmpty else {
        self.applyTranslationResults(
          requestID: requestID,
          outgoing: [:],
          hideIndices: Set(items.map(\.0))
        )
        return
      }

      let runner = LyricsTranslationRunnerView(
        batchID: batchID,
        items: items,
        requestID: requestID
      ) { [weak self] rid, outgoing, hideIndices in
        self?.applyTranslationResults(
          requestID: rid,
          outgoing: outgoing,
          hideIndices: hideIndices
        )
      }

      if let host = self.translationBatchHost {
        host.rootView = runner
      } else {
        let host = UIHostingController(rootView: runner)
        self.translationBatchHost = host
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        self.addChild(host)
        self.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          host.view.widthAnchor.constraint(equalToConstant: 1),
          host.view.heightAnchor.constraint(equalToConstant: 1),
          host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
          host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
        ])
        host.didMove(toParent: self)
      }
    }
  }

  private func removeTranslationBatchHost() {
    guard let host = translationBatchHost else { return }
    host.willMove(toParent: nil)
    host.view.removeFromSuperview()
    host.removeFromParent()
    translationBatchHost = nil
  }

  private func applyTranslationResults(
    requestID: Int,
    outgoing: [Int: String],
    hideIndices: Set<Int>
  ) {
    guard requestID == translationRequestSerial else { return }
    for idx in hideIndices {
      guard translationLabels.indices.contains(idx) else { continue }
      translationLabels[idx].text = ""
      translationLabels[idx].isHidden = true
    }
    for (idx, translated) in outgoing {
      guard translationLabels.indices.contains(idx) else { continue }
      if translated.isEmpty {
        translationLabels[idx].text = ""
        translationLabels[idx].isHidden = true
      } else {
        translationLabels[idx].isHidden = false
        translationLabels[idx].text = translated
      }
    }
    applyRowLabelStylesForActiveIndex(activeSentenceIndex)
  }

  private func applyRowLabelStylesForActiveIndex(_ newIndex: Int?) {
    for (i, lineRow) in sentenceLineRows.enumerated() {
      let isActive = newIndex.map { $0 == i } ?? false
      sentenceLabels[i].textColor = isActive ? Self.activeColor : Self.inactiveColor
      if !translationLabels[i].isHidden {
        translationLabels[i].textColor = isActive ? Self.activeColor : Self.inactiveColor
        translationLabels[i].font =
          isActive ? Self.translationFontEmphasis : Self.translationFontLoose
      }
      let scale: CGFloat = isActive ? 1 : Self.inactiveScale
      applyScaleKeepingLeading(lineRow, scale: scale)
    }
  }

  private func togglePlayPause() {
    switch tts.state {
    case .playing:
      tts.pause()
    case .paused:
      tts.resume()
    case .readyForReplay:
      tts.replayAll()
    case .idle, .streaming:
      break
    }
  }

  private func updatePlayPauseButton() {
    let isPlaying = tts.state == .playing
    var cfg = playPauseButton.configuration ?? .plain()
    cfg.image = UIImage(
      systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
    )
    cfg.baseForegroundColor = .black
    playPauseButton.configuration = cfg
  }

  private func syncActiveSentenceFromCurrentPlayback() {
    // If audio isn't playing, clear any highlight so everything reads as faded.
    guard tts.state == .playing else {
      setActiveSentence(nil, animated: false)
      return
    }
  }

  // MARK: - Active sentence

  private func setActiveSentence(_ newIndex: Int?, animated: Bool) {
    guard newIndex != activeSentenceIndex else { return }
    activeSentenceIndex = newIndex

    // Force a layout pass so row widths are correct before we compute the
    // leading-edge-preserving transform, and so scroll frames are up to date.
    scrollView.layoutIfNeeded()

    // Compute the scroll target BEFORE we trigger layout changes so we're measuring
    // frames that match what's currently on screen. `nil` means "leave the scroll
    // position alone" (e.g. content shorter than the viewport).
    let targetOffset: CGPoint? = newIndex.flatMap {
      self.targetContentOffsetCenteringActiveSentence(at: $0)
    }

    let applyStyles: () -> Void = { [weak self] in
      guard let self else { return }
      self.applyRowLabelStylesForActiveIndex(newIndex)
      if let targetOffset {
        self.scrollView.setClampedContentOffsetY(targetOffset.y, allowsScrollCallback: false)
      }
    }

    if animated {
      UIView.animate(
        withDuration: 0.55,
        delay: 0,
        usingSpringWithDamping: 0.88,
        initialSpringVelocity: 0.2,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
        animations: applyStyles
      )
    } else {
      applyStyles()
    }
  }

  /// Vertical offset that places `labelMidY` (in scroll content coordinates) at the
  /// vertical center of the viewport, clamped to allowed scroll range. Returns `nil` if
  /// the content does not scroll.
  private func clampedCenteredOffsetY(labelMidY: CGFloat) -> CGFloat? {
    let viewportHeight = scrollView.bounds.height
    let targetY = labelMidY - viewportHeight * 0.5
    return scrollView.clampedContentOffsetY(targetY, allowNoScroll: true)
  }

  /// Row bounds converted to `contentStack` — same axis as `contentOffset` (not
  /// `convert(..., to: scrollView)`, which is viewport/on-screen and breaks centering math).
  private func rowBoundsInScrollableContent(_ row: UIView) -> CGRect {
    contentStack.convert(row.bounds, from: row)
  }

  /// Scroll offset so the active sentence's midpoint is vertically centered. Returns
  /// `nil` when there is nothing to scroll or the offset would not change meaningfully.
  private func targetContentOffsetCenteringActiveSentence(at index: Int) -> CGPoint? {
    guard sentenceLineRows.indices.contains(index) else { return nil }
    let row = sentenceLineRows[index]
    guard row.bounds.height > 0 else { return nil }
    let midY = rowBoundsInScrollableContent(row).midY
    guard let y = clampedCenteredOffsetY(labelMidY: midY) else { return nil }
    if abs(y - scrollView.contentOffset.y) < 1 { return nil }
    return CGPoint(x: 0, y: y)
  }

  /// Same centering as `targetContentOffsetCenteringActiveSentence`, without the
  /// no-op threshold — used after layout so rotation/size changes always re-apply.
  private func centeredContentOffset(forActiveIndex index: Int) -> CGPoint? {
    guard sentenceLineRows.indices.contains(index) else { return nil }
    let row = sentenceLineRows[index]
    guard row.bounds.height > 0 else { return nil }
    let midY = rowBoundsInScrollableContent(row).midY
    guard let y = clampedCenteredOffsetY(labelMidY: midY) else { return nil }
    return CGPoint(x: 0, y: y)
  }

  // MARK: - Type + color tokens

  private static let lyricFont: UIFont = {
    let base = UIFont.systemFont(ofSize: 32, weight: .heavy)
    return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base)
  }()

  private static let translationFontLoose: UIFont = {
    let base = UIFont.systemFont(ofSize: 17, weight: .regular)
    return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: base)
  }()

  private static let translationFontEmphasis: UIFont = {
    let base = UIFont.systemFont(ofSize: 17, weight: .semibold)
    return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: base)
  }()

  /// Applied to inactive rows so the active row visually pops without needing a font
  /// swap (font swaps reflow text and can't be interpolated smoothly — `transform` can).
  /// The actual transform is built per-row by `applyScaleKeepingLeading(_:scale:)`
  /// so the leading edge stays pinned as the row grows.
  private static let inactiveScale: CGFloat = 0.88

  private static let activeColor: UIColor = .black
  private static let inactiveColor: UIColor = UIColor.black.withAlphaComponent(0.22)
}

// MARK: - Scroll: clamped offset

extension LyricsViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    let y = scrollView.contentOffset.y
    let c = scrollView.clampedContentOffsetY(y, allowNoScroll: false) ?? y
    if abs(c - y) > 0.5 {
      scrollView.setClampedContentOffsetY(c, allowsScrollCallback: false)
    }
  }
}

private extension UIScrollView {
  /// Returns `nil` when there is no vertical scroll range and `allowNoScroll` is `true` (keeps
  /// `centeredContentOffset` / “don’t move scroll” behavior). Otherwise always returns a finite Y in `[min, max]`.
  func clampedContentOffsetY(_ y: CGFloat, allowNoScroll: Bool) -> CGFloat? {
    let ai = adjustedContentInset
    let h = bounds.height
    let ch = contentSize.height
    let minY = -ai.top
    let maxY = max(minY, ch - h + ai.bottom)
    if maxY <= minY {
      if allowNoScroll { return nil }
      return minY
    }
    return min(max(y, minY), maxY)
  }

  /// Keeps `contentOffset.y` within the scrollable range. Pass `allowsScrollCallback: false`
  /// when the change must not re-enter `scrollViewDidScroll` (layout, programmatic updates, clamp).
  func setClampedContentOffsetY(_ y: CGFloat, allowsScrollCallback: Bool) {
    let prev = delegate
    if !allowsScrollCallback { delegate = nil }
    let clampedY = clampedContentOffsetY(y, allowNoScroll: false) ?? y
    contentOffset = CGPoint(x: 0, y: clampedY)
    if !allowsScrollCallback { delegate = prev }
  }
}

// MARK: - TextToSpeechServiceDelegate
//
// Every callback is forwarded to `previousDelegate` (the sheet's TTS view controller)
// so its own UI stays live while the lyrics screen is on top.

extension LyricsViewController: TextToSpeechServiceDelegate {

  func textToSpeechService(_ service: TextToSpeechService, didAdvancePlaybackTo sampleOffset: Int) {
    let idx = service.sentenceIndex(forSampleOffset: sampleOffset)
    setActiveSentence(idx, animated: true)
    previousDelegate?.textToSpeechService(service, didAdvancePlaybackTo: sampleOffset)
  }

  func textToSpeechService(_ service: TextToSpeechService, didChangeState state: TTSPlaybackState) {
    updatePlayPauseButton()
    switch state {
    case .idle, .readyForReplay:
      setActiveSentence(nil, animated: true)
    case .paused, .playing, .streaming:
      break
    }
    previousDelegate?.textToSpeechService(service, didChangeState: state)
  }

  func textToSpeechService(_ service: TextToSpeechService, didUpdateSentenceAt index: Int) {
    if sentenceLabels.count != service.sentences.count {
      rebuildSentenceLabels()
    } else if sentenceLabels.indices.contains(index) {
      sentenceLabels[index].text = service.sentences[index].text
      scheduleTranslation(forSentenceAt: index)
    }
    previousDelegate?.textToSpeechService(service, didUpdateSentenceAt: index)
  }

  func textToSpeechService(_ service: TextToSpeechService, didStartStreamingFor text: String) {
    rebuildSentenceLabels()
    previousDelegate?.textToSpeechService(service, didStartStreamingFor: text)
  }

  func textToSpeechServiceDidFinish(_ service: TextToSpeechService) {
    if sentenceLabels.count != service.sentences.count {
      rebuildSentenceLabels()
    }
    previousDelegate?.textToSpeechServiceDidFinish(service)
  }

  func textToSpeechService(_ service: TextToSpeechService, didUpdateLevel level: Float) {
    previousDelegate?.textToSpeechService(service, didUpdateLevel: level)
  }

  func textToSpeechService(_ service: TextToSpeechService, didFailWith error: Error) {
    previousDelegate?.textToSpeechService(service, didFailWith: error)
  }

  func textToSpeechServiceDidRestoreSavedUtterance(_ service: TextToSpeechService) {
    rebuildSentenceLabels()
    syncActiveSentenceFromCurrentPlayback()
    previousDelegate?.textToSpeechServiceDidRestoreSavedUtterance(service)
  }
}

// MARK: - SwiftUI translation batch (same pathway as Sentence scrub)

/// Sentence scrub uses `translationTask` + `session.translate`; lyrics uses that here too.
private struct LyricsTranslationRunnerView: View {
  let batchID: UUID
  let items: [(Int, String)]
  let requestID: Int
  let onFinish: @MainActor (Int, [Int: String], Set<Int>) -> Void

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .accessibilityHidden(true)
      .id(batchID)
      .translationTask(
        source: Locale.Language(identifier: "ja"),
        target: Locale.Language(identifier: "en")
      ) { session in
        await Self.perform(
          items: items,
          jaEnSession: session,
          requestID: requestID,
          onFinish: onFinish
        )
      }
  }

  private static func perform(
    items: [(Int, String)],
    jaEnSession: TranslationSession,
    requestID: Int,
    onFinish: @MainActor @escaping (Int, [Int: String], Set<Int>) -> Void
  ) async {
    do {
      try await jaEnSession.prepareTranslation()
    } catch {}

    var outgoing: [Int: String] = [:]
    var hideIndices: Set<Int> = []

    for (idx, text) in items {
      guard let route = lyricsTranslationRoute(for: text) else {
        hideIndices.insert(idx)
        continue
      }
      if lyricsRouteUsesJapaneseEnglishSession(route) {
        do {
          let response = try await jaEnSession.translate(text)
          outgoing[idx] = response.targetText
        } catch {
          outgoing[idx] = ""
        }
      } else {
        do {
          let s = try TranslationSession(installedSource: route.source, target: route.target)
          let response = try await s.translate(text)
          outgoing[idx] = response.targetText
        } catch {
          outgoing[idx] = ""
        }
      }
    }

    await MainActor.run {
      onFinish(requestID, outgoing, hideIndices)
    }
  }
}

/// When this returns `nil`, English copy is not shown (e.g. line is already English).
fileprivate func lyricsTranslationRoute(for text: String) -> (
  source: Locale.Language, target: Locale.Language
)? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return nil }

  let recognizer = NLLanguageRecognizer()
  recognizer.processString(trimmed)

  if let lang = recognizer.dominantLanguage, lang == .english {
    return nil
  }

  let sourceIdentifier =
    recognizer.dominantLanguage?.rawValue ?? NLLanguage.japanese.rawValue
  let source = Locale.Language(identifier: sourceIdentifier)
  let target = Locale.Language(identifier: "en")
  if source.languageCode == target.languageCode { return nil }
  return (source, target)
}

fileprivate func lyricsRouteUsesJapaneseEnglishSession(
  _ route: (source: Locale.Language, target: Locale.Language)
) -> Bool {
  let target = route.target
  guard target.languageCode == .english || target.minimalIdentifier.hasPrefix("en") else {
    return false
  }
  let source = route.source
  if source.languageCode == .japanese { return true }
  if source.minimalIdentifier.hasPrefix("ja") { return true }
  return false
}
