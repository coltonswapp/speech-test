import UIKit

enum OnboardingChrome {
    static let backButtonSize: CGFloat = 44
    static let horizontalInset: CGFloat = 24
    static let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
    static let subtitleFont = UIFont.preferredFont(forTextStyle: .subheadline)

    @discardableResult
    static func makeCircularIconButton(symbolName: String) -> UIButton {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        let button = UIButton(type: .system)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UIImageView()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        glyph.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyph.tintColor = .label
        glyph.preferredSymbolConfiguration = symbolConfig
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyph)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: backButtonSize),
            button.heightAnchor.constraint(equalToConstant: backButtonSize),
            glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        return button
    }

    static func makeGlassPlayButton(size: CGFloat = 56, glyphPointSize: CGFloat = 22) -> UIButton {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        let button = UIButton(type: .system)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Play"

        let glyph = UIImageView()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyph.image = UIImage(systemName: "play.fill", withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyph.tintColor = .systemYellow
        glyph.preferredSymbolConfiguration = symbolConfig
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyph)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
            glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: glyphPointSize + 6),
            glyph.heightAnchor.constraint(equalToConstant: glyphPointSize + 6),
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
