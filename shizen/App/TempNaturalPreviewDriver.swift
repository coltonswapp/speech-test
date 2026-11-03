// TEMP-PREVIEW: delete before committing.
import UIKit

enum TempNaturalPreviewDriver {
    static func run(from root: UIViewController) {
        guard let script = ProcessInfo.processInfo.environment["NATURAL_PREVIEW"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let host: UIViewController = ProcessInfo.processInfo.environment["NATURAL_PREVIEW_V2"] != nil ? ListenFirstOnboardingHostController() : NaturalOnboardingHostController()
            root.present(host, animated: false)
            var t: Double = 1.0
            for command in script.split(separator: ",") {
                let parts = command.split(separator: ":")
                t += Double(parts.count > 1 ? String(parts[1]) : "1") ?? 1
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { perform(String(parts[0]), in: host) }
            }
        }
    }

    static func perform(_ command: String, in host: UIViewController) {
        let all = views(in: host.view)
        switch command {
        case "name":
            if let field = all.compactMap({ $0 as? UITextField }).first {
                field.text = "Colton"
                field.sendActions(for: .editingChanged)
                _ = field.delegate?.textFieldShouldReturn?(field)
            }
        case "next":
            topStep(host)?.ctaTapped()
        case "card":
            all.compactMap { $0 as? TutorGoalCard }.first(where: { $0.window != nil && $0.tag == 1 })?.sendActions(for: .touchUpInside)
        case "nextex":
            all.compactMap { $0 as? GlassIconButton }.first(where: { $0.accessibilityLabel == "Next example" && $0.window != nil })?.sendActions(for: .touchUpInside)
        case "play":
            all.compactMap { $0 as? GlassIconButton }.first(where: { $0.accessibilityLabel == "Play conversation" && $0.window != nil })?.sendActions(for: .touchUpInside)
        case "wrong":
            all.compactMap { $0 as? NaturalGistOption }.first(where: { $0.tag == 0 })?.sendActions(for: .touchUpInside)
        case "plan":
            all.compactMap { $0 as? OnboardingSummaryCard }.first(where: { $0.tag == 1 })?.sendActions(for: .touchUpInside)
        default: break
        }
    }

    static func topStep(_ host: UIViewController) -> OnboardingViewController? {
        views(in: host.view).lazy.compactMap { $0.next as? OnboardingViewController }.first { $0.view.window != nil && $0.navigationController?.topViewController === $0 }
    }

    static func views(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap { views(in: $0) }
    }
}
