//
//  MascotPlaygroundViewController.swift
//  shizen
//
//  Live tuner for the flower mascot. The preview stays pinned while the
//  controls scroll underneath. Pick a preset, nudge any knob, tune the spring,
//  then copy the result as Swift.
//

import UIKit

final class MascotPlaygroundViewController: UIViewController {

    private let mascot = MascotView()
    private let previewCard = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let copyItem = UIBarButtonItem()

    /// Preset plus slider tweaks: what the mascot rests on when no finger is down.
    private var base = MascotPreset.neutral.expression
    private var selectedPreset: MascotPreset? = .neutral
    private var sliders: [MascotParam: UISlider] = [:]
    private var presetButtons: [MascotPreset: UIButton] = [:]
    private var themeButtons: [(theme: MascotTheme, button: UIButton)] = []
    private let themeHeader = UIButton(type: .system)
    private let themeGrid = UIStackView()
    private static let themeCollapsedKey = "MascotPlayground.themeCollapsed"

    private var mascotWidth: NSLayoutConstraint!
    private var isShrunk = false
    private let fullSize: CGFloat = 262
    private let shrunkSize: CGFloat = 110
    private var isSyncingSliders = false
    private var followsTouch = true

    private let stiffnessSlider = UISlider()
    private let dampingSlider = UISlider()
    private let petalSpreadSlider = UISlider()
    private let petalWobbleSlider = UISlider()
    private let petalScaleSlider = UISlider()
    private let idleSwitch = UISwitch()
    private let blinkSwitch = UISwitch()
    private let touchSwitch = UISwitch()
    private let solidEyesSwitch = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mascot"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        let reset = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(resetTapped))
        copyItem.image = UIImage(systemName: "doc.on.doc")
        copyItem.target = self
        copyItem.action = #selector(copyTapped)
        navigationItem.rightBarButtonItems = [reset, copyItem]

        configureLayout()
        select(.neutral)
    }

    // MARK: - Layout

    private func configureLayout() {
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.backgroundColor = ExperimentPalette.cardSurface
        previewCard.layer.cornerRadius = 22
        previewCard.layer.cornerCurve = .continuous
        previewCard.clipsToBounds = true
        view.addSubview(previewCard)

        mascot.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(mascot)

        let caption = UILabel()
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.font = .preferredFont(forTextStyle: .caption1)
        caption.textColor = .tertiaryLabel
        caption.textAlignment = .center
        caption.text = "Drag on the card and the eyes follow your finger."
        previewCard.addSubview(caption)

        let track = UILongPressGestureRecognizer(target: self, action: #selector(trackTouch(_:)))
        track.minimumPressDuration = 0
        track.allowableMovement = .greatestFiniteMagnitude
        previewCard.addGestureRecognizer(track)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 32, right: 20)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeActionRow())

        contentStack.addArrangedSubview(makeHeader("Expressions"))
        contentStack.addArrangedSubview(makePresetGrid())

        contentStack.addArrangedSubview(themeHeader)
        contentStack.addArrangedSubview(makeThemeGrid())
        configureThemeHeader()
        contentStack.addArrangedSubview(makeToggleRow(title: "Solid white eyes", toggle: solidEyesSwitch, isOn: mascot.solidWhiteEyes) { [weak self] on in
            self?.mascot.solidWhiteEyes = on
            // Saved, so onboarding and every other Hana pick it up too.
            MascotView.savedSolidWhiteEyes = on
        })

        for group in MascotParam.Group.allCases {
            contentStack.addArrangedSubview(makeHeader(group.title))
            for param in MascotParam.allCases where param.group == group {
                contentStack.addArrangedSubview(makeSliderRow(for: param))
            }
        }

        contentStack.addArrangedSubview(makeHeader("Spring"))
        stiffnessSlider.minimumValue = 60
        stiffnessSlider.maximumValue = 600
        stiffnessSlider.value = Float(mascot.stiffness)
        stiffnessSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.mascot.stiffness = CGFloat(self.stiffnessSlider.value)
        }, for: .valueChanged)
        contentStack.addArrangedSubview(ExperimentSliderRow.make(title: "Stiffness", slider: stiffnessSlider, format: "%.0f"))

        dampingSlider.minimumValue = 0.15
        dampingSlider.maximumValue = 1.2
        dampingSlider.value = Float(mascot.dampingRatio)
        dampingSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.mascot.dampingRatio = CGFloat(self.dampingSlider.value)
        }, for: .valueChanged)
        contentStack.addArrangedSubview(ExperimentSliderRow.make(title: "Damping ratio (1 = no bounce)", slider: dampingSlider, format: "%.2f"))

        contentStack.addArrangedSubview(makeHeader("Petals"))
        petalSpreadSlider.minimumValue = 0
        petalSpreadSlider.maximumValue = 1
        petalSpreadSlider.value = Float(mascot.petalSpread)
        petalSpreadSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.mascot.petalSpread = CGFloat(self.petalSpreadSlider.value)
        }, for: .valueChanged)
        contentStack.addArrangedSubview(ExperimentSliderRow.make(title: "Notch depth", slider: petalSpreadSlider, format: "%.2f"))

        petalWobbleSlider.minimumValue = 0
        petalWobbleSlider.maximumValue = 1
        petalWobbleSlider.value = Float(mascot.petalWobble)
        petalWobbleSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.mascot.petalWobble = CGFloat(self.petalWobbleSlider.value)
        }, for: .valueChanged)
        contentStack.addArrangedSubview(ExperimentSliderRow.make(title: "Imperfection", slider: petalWobbleSlider, format: "%.2f"))

        petalScaleSlider.minimumValue = 0.6
        petalScaleSlider.maximumValue = 1.1
        petalScaleSlider.value = Float(mascot.petalScale)
        petalScaleSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.mascot.petalScale = CGFloat(self.petalScaleSlider.value)
        }, for: .valueChanged)
        contentStack.addArrangedSubview(ExperimentSliderRow.make(title: "Petal size (vs face)", slider: petalScaleSlider, format: "%.2f"))

        contentStack.addArrangedSubview(makeHeader("Behavior"))
        contentStack.addArrangedSubview(makeToggleRow(title: "Idle motion (sway, breathe)", toggle: idleSwitch, isOn: true) { [weak self] on in
            self?.mascot.idleMotionEnabled = on
        })
        contentStack.addArrangedSubview(makeToggleRow(title: "Auto blink", toggle: blinkSwitch, isOn: true) { [weak self] on in
            self?.mascot.autoBlinkEnabled = on
        })
        contentStack.addArrangedSubview(makeToggleRow(title: "Eyes follow touch", toggle: touchSwitch, isOn: true) { [weak self] on in
            self?.followsTouch = on
        })

        mascotWidth = mascot.widthAnchor.constraint(equalToConstant: fullSize)
        NSLayoutConstraint.activate([
            previewCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            previewCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewCard.heightAnchor.constraint(equalToConstant: 300),

            mascot.centerYAnchor.constraint(equalTo: previewCard.topAnchor, constant: 4 + fullSize / 2),
            mascot.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            mascotWidth,
            mascot.heightAnchor.constraint(equalTo: mascot.widthAnchor),

            caption.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            caption.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            caption.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func makeHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    private func makePresetGrid() -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 8

        let presets = MascotPreset.allCases
        let columns = 3
        for start in stride(from: 0, to: presets.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for preset in presets[start..<min(start + columns, presets.count)] {
                let button = UIButton(type: .system)
                button.addAction(UIAction { [weak self] _ in self?.select(preset) }, for: .touchUpInside)
                presetButtons[preset] = button
                styleButton(button, for: preset)
                row.addArrangedSubview(button)
            }
            while row.arrangedSubviews.count < columns {
                row.addArrangedSubview(UIView())
            }
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func makeActionRow() -> UIView {
        let actions: [(String, String, (UIButton) -> Void)] = [
            ("Blink", "eye", { [weak self] _ in self?.mascot.blink() }),
            ("Spin", "arrow.trianglehead.clockwise", { [weak self] _ in self?.mascot.spinPetals() }),
            ("Shrink", "arrow.down.right.and.arrow.up.left", { [weak self] button in self?.toggleShrink(button) }),
        ]
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (title, symbol, handler) in actions {
            var config = UIButton.Configuration.tinted()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 6
            config.cornerStyle = .capsule
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak button] _ in
                guard let button else { return }
                handler(button)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    /// Flips between full size and decorator size. The mascot re-renders at the real
    /// size right away (so you see true small-size line weights) and a scale transform
    /// animates the change.
    private func toggleShrink(_ button: UIButton) {
        let from = mascotWidth.constant
        isShrunk.toggle()
        let to = isShrunk ? shrunkSize : fullSize
        mascotWidth.constant = to
        previewCard.layoutIfNeeded()

        mascot.transform = CGAffineTransform(scaleX: from / to, y: from / to)
        UIView.animate(springDuration: 0.5, bounce: 0.2) {
            self.mascot.transform = .identity
        }

        button.configuration?.title = isShrunk ? "Grow" : "Shrink"
        button.configuration?.image = UIImage(
            systemName: isShrunk ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        )
    }

    private func makeThemeGrid() -> UIView {
        let grid = themeGrid
        grid.axis = .vertical
        grid.spacing = 8

        let themes = MascotTheme.all
        let columns = 4
        for start in stride(from: 0, to: themes.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for theme in themes[start..<min(start + columns, themes.count)] {
                let button = UIButton(type: .system)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.mascot.theme = theme
                    MascotTheme.saved = theme
                    self.refreshThemeButtons()
                }, for: .touchUpInside)
                themeButtons.append((theme, button))
                row.addArrangedSubview(button)
            }
            grid.addArrangedSubview(row)
        }
        refreshThemeButtons()
        return grid
    }

    /// Section header that folds the theme grid away. Collapsed state is remembered.
    private func configureThemeHeader() {
        themeGrid.isHidden = UserDefaults.standard.bool(forKey: Self.themeCollapsedKey)
        themeHeader.contentHorizontalAlignment = .leading
        themeHeader.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let collapse = !self.themeGrid.isHidden
            UserDefaults.standard.set(collapse, forKey: Self.themeCollapsedKey)
            UIView.animate(springDuration: 0.35, bounce: 0) {
                self.themeGrid.isHidden = collapse
                self.themeGrid.alpha = collapse ? 0 : 1
                self.contentStack.layoutIfNeeded()
            }
            self.refreshThemeHeader()
        }, for: .touchUpInside)
        refreshThemeHeader()
    }

    private func refreshThemeHeader() {
        let collapsed = themeGrid.isHidden
        var config = UIButton.Configuration.plain()
        // Collapsed, the header still says which theme is on.
        config.title = collapsed ? "THEME · \(mascot.theme.name.uppercased())" : "THEME"
        config.image = UIImage(systemName: collapsed ? "chevron.right" : "chevron.down")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 12, weight: .semibold)
            return attributes
        }
        themeHeader.configuration = config
    }

    /// Petal-colored capsule with a face-colored dot; the selected one gets a ring.
    private func refreshThemeButtons() {
        for (theme, button) in themeButtons {
            let isSelected = theme == mascot.theme
            var config = UIButton.Configuration.filled()
            config.title = theme.name
            config.image = UIImage(systemName: "circle.fill")?
                .withTintColor(theme.face.uiColor, renderingMode: .alwaysOriginal)
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10)
            config.imagePadding = 4
            config.baseBackgroundColor = theme.petal.uiColor
            config.baseForegroundColor = UIColor(white: 0.1, alpha: 1)
            config.cornerStyle = .capsule
            config.buttonSize = .small
            config.titleLineBreakMode = .byTruncatingTail
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
            config.background.strokeColor = isSelected ? .label : .clear
            config.background.strokeWidth = 2
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .medium)
                return attributes
            }
            button.configuration = config
        }
    }

    private func styleButton(_ button: UIButton, for preset: MascotPreset) {
        var config: UIButton.Configuration = preset == selectedPreset ? .filled() : .gray()
        config.title = preset.title
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.titleLineBreakMode = .byTruncatingTail
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13, weight: .medium)
            return attributes
        }
        button.configuration = config
    }

    private func refreshPresetButtons() {
        for (preset, button) in presetButtons {
            styleButton(button, for: preset)
        }
    }

    private func makeSliderRow(for param: MascotParam) -> UIView {
        let slider = UISlider()
        slider.minimumValue = Float(param.range.lowerBound)
        slider.maximumValue = Float(param.range.upperBound)
        slider.value = Float(param.defaultValue)
        slider.addAction(UIAction { [weak self, weak slider] _ in
            guard let self, let slider, !self.isSyncingSliders else { return }
            self.base[param] = CGFloat(slider.value)
            self.selectedPreset = nil
            self.refreshPresetButtons()
            self.mascot.set(self.base)
        }, for: .valueChanged)
        sliders[param] = slider
        return ExperimentSliderRow.make(title: param.title, slider: slider, format: "%.2f")
    }

    private func makeToggleRow(
        title: String,
        toggle: UISwitch,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)

        toggle.isOn = isOn
        toggle.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }
            onChange(toggle.isOn)
        }, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    // MARK: - Actions

    private func select(_ preset: MascotPreset) {
        selectedPreset = preset
        base = preset.expression
        syncSliders()
        refreshPresetButtons()
        mascot.play(preset)
    }

    /// Moves every slider to `base`. The flag keeps the slider handlers from re-applying it.
    private func syncSliders() {
        isSyncingSliders = true
        for (param, slider) in sliders {
            slider.setValue(Float(base[param]), animated: true)
            slider.sendActions(for: .valueChanged)
        }
        isSyncingSliders = false
    }

    @objc private func trackTouch(_ gesture: UILongPressGestureRecognizer) {
        guard followsTouch else { return }
        switch gesture.state {
        case .began, .changed:
            mascot.look(at: gesture.location(in: mascot))
        case .ended, .cancelled, .failed:
            mascot.set(base)
        default:
            break
        }
    }

    @objc private func resetTapped() {
        select(.neutral)

        stiffnessSlider.setValue(220, animated: true)
        stiffnessSlider.sendActions(for: .valueChanged)
        dampingSlider.setValue(0.62, animated: true)
        dampingSlider.sendActions(for: .valueChanged)
        petalSpreadSlider.setValue(0.6, animated: true)
        petalSpreadSlider.sendActions(for: .valueChanged)
        petalWobbleSlider.setValue(0.6, animated: true)
        petalWobbleSlider.sendActions(for: .valueChanged)
        petalScaleSlider.setValue(0.88, animated: true)
        petalScaleSlider.sendActions(for: .valueChanged)

        for toggle in [idleSwitch, blinkSwitch, touchSwitch] {
            toggle.setOn(true, animated: true)
            toggle.sendActions(for: .valueChanged)
        }
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = "static let custom = \(base.swiftSnippet)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copyItem.image = UIImage(systemName: "checkmark")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyItem.image = UIImage(systemName: "doc.on.doc")
        }
    }
}
