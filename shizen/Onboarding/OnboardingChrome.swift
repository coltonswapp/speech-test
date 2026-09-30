import UIKit

enum OnboardingChrome {
    static let backButtonSize: CGFloat = 44
    static let horizontalInset: CGFloat = 24
    static let titleHorizontalInset: CGFloat = 28
    static let titleTopInset: CGFloat = 76
    static let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    static let subtitleFont = UIFont.preferredFont(forTextStyle: .subheadline)

    @discardableResult
    static func makeCircularIconButton(symbolName: String) -> GlassIconButton {
        let button = GlassIconButton(
            symbolName: symbolName,
            pointSize: 17,
            tintColor: .label
        )
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: backButtonSize),
            button.heightAnchor.constraint(equalToConstant: backButtonSize),
        ])
        return button
    }

    static func makeGlassPlayButton(size: CGFloat = 56, glyphPointSize: CGFloat = 22) -> GlassIconButton {
        let button = GlassIconButton(
            symbolName: "play.fill",
            pointSize: glyphPointSize,
            tintColor: .systemYellow,
            accessibilityLabel: "Play"
        )
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
        return button
    }

    static func makeDialogueBubble(
        text: String,
        font: UIFont,
        side: DialogueSpeakerSide? = nil,
        showsTail: Bool = false,
        emphasis: CGFloat = 1
    ) -> DialogueJapaneseBubbleView {
        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .natural
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: label,
            text: text,
            font: font,
            textColor: .label
        )

        let bubble = DialogueJapaneseBubbleView(label: label)
        bubble.setBackgroundStyle(.glass)
        bubble.setEmphasis(emphasis)
        if let side {
            bubble.setUnderglowConfiguration(.forSpeaker(side))
            if showsTail {
                bubble.setTailEdge(side == .leading ? .leading : .trailing)
            }
        } else {
            bubble.setUnderglowConfiguration(.default)
        }
        return bubble
    }
}
