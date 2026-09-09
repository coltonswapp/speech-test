import UIKit

final class OnboardingFinishViewController: OnboardingViewController {

    private let config: BasicStepConfig
    private var hasStartedFinish = false

    init(config: BasicStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(
            title: config.title ?? "You're in",
            subtitle: config.subtitle
        )
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStartedFinish else { return }
        hasStartedFinish = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.coordinator?.finishSetup()
        }
    }
}
