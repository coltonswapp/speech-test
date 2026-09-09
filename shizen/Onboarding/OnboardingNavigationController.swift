import UIKit

final class OnboardingNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = nil
        view.backgroundColor = ExperimentPalette.pageBackground
    }
}
