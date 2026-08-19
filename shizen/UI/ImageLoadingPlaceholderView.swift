//
//  ImageLoadingPlaceholderView.swift
//  shizen
//
//  ChatGPT-style image loading placeholder backed by a SwiftUI shader view.
//

import SwiftUI
import UIKit

enum ImageLoadingPlaceholderMetrics {
    static let defaultCornerRadius: CGFloat = 20
}

@Observable
final class ImageLoadingPlaceholderModel {
    var message: String?
    var isAnimating = false
    var cornerRadius: CGFloat = ImageLoadingPlaceholderMetrics.defaultCornerRadius
    var isDarkMode = true
}

struct ImageLoadingPlaceholderContent: View {
    var model: ImageLoadingPlaceholderModel

    @State private var referenceDate = Date()

    private var surfaceColor: Color {
        model.isDarkMode
            ? Color(red: 0.184, green: 0.184, blue: 0.184)
            : Color(red: 0.949, green: 0.949, blue: 0.949)
    }

    private var labelColor: Color {
        model.isDarkMode
            ? Color.white.opacity(0.72)
            : Color.black.opacity(0.55)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !model.isAnimating)) { timeline in
            // Anchor to a small elapsed value; the raw timeIntervalSinceReferenceDate
            // is large enough (hundreds of millions of seconds) that casting straight
            // to Float quantizes to ~1-minute steps and the shader appears frozen.
            let time = Float(timeline.date.timeIntervalSince(referenceDate))

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(surfaceColor)
                        .colorEffect(
                            ShaderLibrary.loadingDotField(
                                .float(time),
                                .float2(
                                    Float(geometry.size.width),
                                    Float(geometry.size.height)
                                ),
                                .float(model.isDarkMode ? 1 : 0)
                            )
                        )

                    if let message = model.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(labelColor)
                            .padding(.top, 14)
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
        )
        .background(surfaceColor)
    }
}

final class ImageLoadingPlaceholderView: UIView {

    var message: String? {
        get { model.message }
        set { model.message = newValue }
    }

    var cornerRadius: CGFloat {
        get { model.cornerRadius }
        set { applyCornerRadius(newValue) }
    }

    private let model = ImageLoadingPlaceholderModel()
    private var hostingController: UIHostingController<ImageLoadingPlaceholderContent>?
    private var wantsAnimating = false
    private weak var cornerRadiusSourceView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var isHidden: Bool {
        didSet {
            guard oldValue != isHidden else { return }
            if isHidden {
                model.isAnimating = false
            } else if wantsAnimating {
                model.isAnimating = window != nil
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            model.isDarkMode = traitCollection.userInterfaceStyle == .dark
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let source = cornerRadiusSourceView {
            applyCornerRadius(source.layer.cornerRadius, cornerCurve: source.layer.cornerCurve)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        model.isAnimating = window != nil && wantsAnimating && !isHidden
        model.isDarkMode = traitCollection.userInterfaceStyle == .dark
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            wantsAnimating = false
            model.isAnimating = false
        }
    }

    /// Keeps the placeholder corner radius aligned with an image host view.
    func syncCornerRadius(with sourceView: UIView) {
        cornerRadiusSourceView = sourceView
        applyCornerRadius(sourceView.layer.cornerRadius, cornerCurve: sourceView.layer.cornerCurve)
    }

    func startAnimating() {
        wantsAnimating = true
        isHidden = false
        model.isAnimating = window != nil
    }

    func stopAnimating() {
        wantsAnimating = false
        model.isAnimating = false
    }

    private func configureView() {
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
        applyCornerRadius(ImageLoadingPlaceholderMetrics.defaultCornerRadius)
        model.isDarkMode = traitCollection.userInterfaceStyle == .dark

        let host = UIHostingController(
            rootView: ImageLoadingPlaceholderContent(model: model)
        )
        hostingController = host
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func applyCornerRadius(
        _ radius: CGFloat,
        cornerCurve: CALayerCornerCurve = .continuous
    ) {
        model.cornerRadius = radius
        layer.cornerRadius = radius
        layer.cornerCurve = cornerCurve
        clipsToBounds = true
    }
}
