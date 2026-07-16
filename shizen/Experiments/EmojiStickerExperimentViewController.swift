//
//  EmojiStickerExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: emoji “stickers” with a die-cut white halo and soft shadow.


import UIKit

// MARK: - Rendering

private enum EmojiStickerRenderer {
    /// Max edge length (pixels) output will produce; avoids huge textures during slider drags.
    private static let maxRasterDimension = 6144

    /// Text/emoji rasterization (CoreText). Call on the **main** queue.
    static func rasterStickerSource(trimmedEmoji: String, fontSize: CGFloat, displayScale: CGFloat) -> UIImage? {
        guard !trimmedEmoji.isEmpty else { return nil }
        let scale = max(displayScale, 2)
        let baseOuterPadPx = ceil(4 * scale)
        return rasterizeEmoji(trimmedEmoji, fontSize: fontSize, scale: scale, outerPadPixels: baseOuterPadPx)?
            .fixedOrientationUIImage()
    }

    /// CPU-heavy halo + padded face synthesis. Safe to call off the main thread (no UIKit text rendering here).
    ///
    /// Halo outline uses **circular (Euclidean) dilation** via a squared distance transform — offsets stay rounded instead of Chebyshev “square metric” corners.
    static func composeStickerLayers(
        raster: UIImage,
        borderWidthPoints: CGFloat,
        displayScale: CGFloat
    ) -> (halo: UIImage, face: UIImage)? {
        let scale = max(displayScale, 2)
        let borderPx = max(1, Int(round(borderWidthPoints * scale)))
        let shadowPadPoints: CGFloat = 28
        let shadowPadPx = Int(ceil(shadowPadPoints * scale))

        guard let unpacked = unpackCoverageAlpha(from: raster) else { return nil }
        let emojiW = unpacked.width
        let emojiH = unpacked.height
        guard emojiW > 1, emojiH > 1 else { return nil }

        let extraPadPx = borderPx + shadowPadPx
        let outW = emojiW + (extraPadPx * 2)
        let outH = emojiH + (extraPadPx * 2)
        guard outW > 1, outH > 1, outW <= maxRasterDimension, outH <= maxRasterDimension else { return nil }

        var paddedAlpha = [UInt8](repeating: 0, count: outW * outH)

        paddedAlpha.withUnsafeMutableBufferPointer { padded in
            unpacked.alpha.withUnsafeBufferPointer { srcAlpha in
                for y in 0 ..< emojiH {
                    let dstRow = (y + extraPadPx) * outW + extraPadPx
                    let srcRow = y * emojiW
                    padded.baseAddress!.advanced(by: dstRow)
                        .update(from: srcAlpha.baseAddress!.advanced(by: srcRow), count: emojiW)
                }
            }
        }

        dilateCircularMaskInPlace(alpha: &paddedAlpha, width: outW, height: outH, radiusPx: borderPx)

        guard let haloCG = cgImagePremultipliedWhite(fromAlphaPlane: paddedAlpha, width: outW, height: outH),
              let faceCG = cgImageDrawingFaceRaster(raster, outWidth: outW, outHeight: outH, insetPx: extraPadPx)
        else { return nil }

        return (
            UIImage(cgImage: haloCG, scale: scale, orientation: .up).withRenderingMode(.alwaysOriginal),
            UIImage(cgImage: faceCG, scale: scale, orientation: .up).withRenderingMode(.alwaysOriginal)
        )
    }

    static func fallbackPreview(emoji: String, fontSize: CGFloat, scale: CGFloat) -> UIImage {
        let size = CGSize(width: 260, height: 260)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 2)
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 20, y: 20, width: 220, height: 220), cornerRadius: 48).fill()
            let ns = (emoji.isEmpty ? "🍣" : emoji) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: max(fontSize, 104))]
            let s = ns.size(withAttributes: attrs)
            let origin = CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2)
            ns.draw(at: origin, withAttributes: attrs)
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Seeds coverage pixels above `seedThreshold`; halo is “within `radiusPx` (Euclidean) of any seed pixel”.
    private static func dilateCircularMaskInPlace(alpha: inout [UInt8], width w: Int, height h: Int, radiusPx r: Int) {
        precondition(alpha.count == w * h)
        guard r > 0 else { return }

        let seedThreshold: UInt8 = 12
        /// Huge finite substitute for ∞ so Felzenszwalb DT stays numeric (must dominate any `(Δx)²+(Δy)²` term).
        let bgPenalty = Float(max(w, h) * max(w, h)) * Float(256)

        var tmp = [Float](repeating: bgPenalty, count: w * h)
        var seedRow = [Float](repeating: bgPenalty, count: w)

        for y in 0 ..< h {
            for x in 0 ..< w {
                let i = y * w + x
                seedRow[x] = alpha[i] >= seedThreshold ? 0 : bgPenalty
            }
            let dtRow = distanceTransform1DSquared(seedRow)
            for x in 0 ..< w { tmp[y * w + x] = dtRow[x] }
        }

        var dtSq = [Float](repeating: bgPenalty, count: w * h)
        var col = [Float](repeating: bgPenalty, count: h)
        for x in 0 ..< w {
            for y in 0 ..< h { col[y] = tmp[y * w + x] }
            let dtCol = distanceTransform1DSquared(col)
            for y in 0 ..< h { dtSq[y * w + x] = dtCol[y] }
        }

        let radius = Float(r)
        /// Narrow anti‑alias band only at the cutoff — avoids stair‑steps without widened semi‑transparent halos.
        let aaHalfWidth = Float(0.55)
        let innerCutoff = max(radius - aaHalfWidth, 0)
        let outerCutoff = radius + aaHalfWidth
        let innerSq = innerCutoff * innerCutoff
        let outerSq = outerCutoff * outerCutoff
        let denomBand = 2 * aaHalfWidth

        for i in 0 ..< (w * h) {
            let d2 = dtSq[i]
            guard d2.isFinite else {
                alpha[i] = 0
                continue
            }

            if d2 <= innerSq {
                alpha[i] = 255
            } else if d2 >= outerSq {
                alpha[i] = 0
            } else {
                let d = sqrt(d2)
                let t = (outerCutoff - d) / denomBand
                alpha[i] = UInt8(min(255, max(0, Int(round(Float(255) * t)))))
            }
        }
    }

    /// Squared distance transform along one dimension (Felzenszwalb & Huttenlocher, linear time).
    private static func distanceTransform1DSquared(_ f: [Float]) -> [Float] {
        let n = f.count
        guard n > 0 else { return [] }

        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 2)

        var k = 0
        v[0] = 0
        z[0] = -Float.greatestFiniteMagnitude
        z[1] = Float.greatestFiniteMagnitude

        var q = 1
        while q < n {
            let fq = f[q] + Float(q * q)
            let fvk = f[v[k]] + Float(v[k] * v[k])
            let denom = Float(2 * q - 2 * v[k])
            var s = denom != 0 ? (fq - fvk) / denom : Float.greatestFiniteMagnitude

            while k > 0, s <= z[k] {
                k -= 1
                let fvk2 = f[v[k]] + Float(v[k] * v[k])
                let denom2 = Float(2 * q - 2 * v[k])
                s = denom2 != 0 ? (fq - fvk2) / denom2 : Float.greatestFiniteMagnitude
            }

            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = Float.greatestFiniteMagnitude
            q += 1
        }

        k = 0
        for q in 0 ..< n {
            while k + 1 < z.count, z[k + 1] < Float(q) {
                k += 1
            }
            let vk = v[k]
            let dx = Float(q - vk)
            d[q] = f[vk] + dx * dx
        }

        return d
    }

    private struct CoverageUnpack {
        var width: Int
        var height: Int
        var alpha: ContiguousArray<UInt8>
    }

    /// Extracts opacity/coverage compatible with emoji premultiplied edges (handles premultiplied BGRA / RGBA).
    private static func unpackCoverageAlpha(from image: UIImage) -> CoverageUnpack? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return nil }

        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let bpp = 4
        var rgba = Data(count: w * h * bpp)

        guard
            let ctx = CGContext(
                data: rgba.withUnsafeMutableBytes { ptr in ptr.bindMemory(to: UInt8.self).baseAddress },
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * bpp,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var alpha = ContiguousArray<UInt8>()
        alpha.reserveCapacity(w * h)
        rgba.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            stride(from: 0, to: p.count, by: bpp).forEach { idx in
                let rPx = p[idx]
                let gPx = p[idx + 1]
                let bPx = p[idx + 2]
                let aPx = p[idx + 3]
                alpha.append(max(rPx, max(gPx, max(bPx, aPx))))
            }
        }

        return CoverageUnpack(width: w, height: h, alpha: alpha)
    }

    private static func cgImagePremultipliedWhite(fromAlphaPlane alpha: [UInt8], width w: Int, height h: Int) -> CGImage? {
        precondition(alpha.count == w * h)
        let bpp = 4
        var rgba = Data(count: w * h * bpp)
        rgba.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: UInt8.self)
            stride(from: 0, to: alpha.count, by: 1).forEach {
                let a = alpha[$0]
                let o = $0 * bpp
                dst[o] = a
                dst[o + 1] = a
                dst[o + 2] = a
                dst[o + 3] = a
            }
        }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: rgba as CFData),
            let out = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: bpp * 8,
                bytesPerRow: w * bpp,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Little),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { return nil }

        return out
    }

    private static func cgImageDrawingFaceRaster(_ raster: UIImage, outWidth w: Int, outHeight h: Int, insetPx pad: Int) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let size = CGSize(width: w, height: h)
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = raster.cgImage.map { CGRect(x: pad, y: pad, width: $0.width, height: $0.height) }
                ?? CGRect(x: CGFloat(pad), y: CGFloat(pad), width: raster.size.width, height: raster.size.height)
            raster.draw(in: rect)
        }
        return img.cgImage
    }

    private static func rasterizeEmoji(
        _ text: String,
        fontSize: CGFloat,
        scale: CGFloat,
        outerPadPixels: CGFloat
    ) -> UIImage? {
        let font = UIFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let str = NSAttributedString(string: text, attributes: attrs)

        // Emoji measurement can occasionally report zero via boundingRect; use multiple strategies.
        var usedFallbackMeasurement = false
        var textBounds = str.boundingRect(
            with: CGSize(width: 4096, height: 4096),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        if textBounds.width < 1 || textBounds.height < 1 {
            usedFallbackMeasurement = true
            let ns = text as NSString
            let s = ns.size(withAttributes: attrs)
            textBounds = CGRect(origin: .zero, size: s)
        }

        let textW = ceil(max(textBounds.width, fontSize * 0.55))
        let textH = ceil(max(textBounds.height, fontSize * 0.85))
        guard textW > 0, textH > 0 else { return nil }

        let padPoints = outerPadPixels / scale
        let canvasW = textW + 2 * padPoints
        let canvasH = textH + 2 * padPoints
        guard canvasW.isFinite, canvasH.isFinite, canvasW > 0.5, canvasH > 0.5 else { return nil }

        let maxCanvasPts = CGFloat(maxRasterDimension) / max(scale, 1)
        guard canvasW <= maxCanvasPts, canvasH <= maxCanvasPts else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasW, height: canvasH), format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: canvasW, height: canvasH)).fill()

            let drawOrigin = CGPoint(
                x: padPoints + -textBounds.origin.x,
                y: padPoints + -textBounds.origin.y
            )
            let drawRect = CGRect(origin: drawOrigin, size: CGSize(width: textW, height: textH))
            if usedFallbackMeasurement {
                (text as NSString).draw(at: drawOrigin, withAttributes: attrs)
            } else {
                str.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
        }
    }
}

private extension UIImage {
    func fixedOrientationUIImage() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - View controller

final class EmojiStickerExperimentViewController: UIViewController {

    private static let presetEmojis = ["🍣", "🥢", "🍛", "🚃", "🍙", "🍜", "🍱", "🚇", "🎋", "🐱", "✨", "❤️"]

    private let stickerCompose = UIView()
    private let haloPreview = UIImageView()
    private let facePreview = UIImageView()
    private let previewContainer = UIView()
    private let textField = UITextField()
    private let borderLabel = UILabel()
    private let borderSlider = UISlider()
    private let sizeLabel = UILabel()
    private let sizeSlider = UISlider()
    private let hintLabel = UILabel()
    private var presetButtons: [UIButton] = []

    private var selectedEmoji: String = "🍣"
    private var borderWidth: CGFloat = 14
    private var emojiFontSize: CGFloat = 108

    private var renderGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Emoji stickers"
        navigationItem.largeTitleDisplayMode = .never

        view.backgroundColor = ExperimentPalette.pageBackground

        stickerCompose.translatesAutoresizingMaskIntoConstraints = false
        for iv in [haloPreview, facePreview] {
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.contentMode = .scaleAspectFit
            iv.accessibilityIgnoresInvertColors = true
            iv.backgroundColor = .clear
            stickerCompose.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: stickerCompose.topAnchor),
                iv.leadingAnchor.constraint(equalTo: stickerCompose.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: stickerCompose.trailingAnchor),
                iv.bottomAnchor.constraint(equalTo: stickerCompose.bottomAnchor),
            ])
        }

        haloPreview.layer.shadowColor = UIColor.black.cgColor
        haloPreview.layer.shadowOffset = CGSize(width: 0, height: 5)
        haloPreview.layer.shadowRadius = 12
        haloPreview.layer.shadowOpacity = 0.28
        haloPreview.layer.masksToBounds = false

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(stickerCompose)
        NSLayoutConstraint.activate([
            stickerCompose.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            stickerCompose.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            stickerCompose.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            stickerCompose.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -12),
            stickerCompose.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        textField.borderStyle = .roundedRect
        textField.placeholder = "Type or paste an emoji"
        textField.text = selectedEmoji
        textField.font = .systemFont(ofSize: 28)
        textField.textAlignment = .center
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = 16
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)

        borderLabel.font = .preferredFont(forTextStyle: .subheadline)
        borderLabel.textColor = .secondaryLabel
        borderSlider.minimumValue = 4
        borderSlider.maximumValue = 32
        borderSlider.value = Float(borderWidth)
        borderSlider.addTarget(self, action: #selector(borderSliderChanged), for: .valueChanged)

        sizeLabel.font = .preferredFont(forTextStyle: .subheadline)
        sizeLabel.textColor = .secondaryLabel
        sizeSlider.minimumValue = 64
        sizeSlider.maximumValue = 180
        sizeSlider.value = Float(emojiFontSize)
        sizeSlider.addTarget(self, action: #selector(sizeSliderChanged), for: .valueChanged)

        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.text = "White halo grows outward with a circular offset (Euclidean dilation), so corners stay rounded instead of square‑metric spikes. Shadow stays on the halo layer only."

        updateMetricLabels()

        let presetScroll = UIScrollView()
        presetScroll.showsHorizontalScrollIndicator = false
        presetScroll.alwaysBounceHorizontal = true
        presetScroll.translatesAutoresizingMaskIntoConstraints = false

        let presetStack = UIStackView()
        presetStack.axis = .horizontal
        presetStack.spacing = 8
        presetStack.translatesAutoresizingMaskIntoConstraints = false

        for s in Self.presetEmojis {
            var cfg = UIButton.Configuration.plain()
            cfg.title = s
            cfg.baseForegroundColor = .label
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 36)
                return out
            }
            let b = UIButton(configuration: cfg)
            b.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            b.layer.cornerRadius = 10
            b.backgroundColor = UIColor.secondarySystemGroupedBackground
            presetStack.addArrangedSubview(b)
            presetButtons.append(b)
        }

        presetScroll.addSubview(presetStack)
        NSLayoutConstraint.activate([
            presetStack.topAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.topAnchor),
            presetStack.leadingAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.leadingAnchor),
            presetStack.trailingAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.trailingAnchor),
            presetStack.bottomAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.bottomAnchor),
            presetStack.heightAnchor.constraint(equalTo: presetScroll.frameLayoutGuide.heightAnchor),
        ])

        let mainStack = UIStackView(arrangedSubviews: [
            hintLabel,
            textField,
            presetScroll,
            borderLabel,
            borderSlider,
            sizeLabel,
            sizeSlider,
            previewContainer,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.setCustomSpacing(20, after: presetScroll)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true

        view.addSubview(scroll)
        scroll.addSubview(mainStack)

        previewContainer.backgroundColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor.tertiarySystemGroupedBackground
            } else {
                UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
            }
        }
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.cornerRadius = 12

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mainStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            mainStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            mainStack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            mainStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),

            presetScroll.heightAnchor.constraint(equalToConstant: 56),
            previewContainer.heightAnchor.constraint(equalToConstant: 280),
        ])

        refreshPresetSelection()
        scheduleRender()
    }

    private func updateMetricLabels() {
        borderLabel.text = String(format: "Border · %.0f pt", borderWidth)
        sizeLabel.text = String(format: "Emoji size · %.0f pt", emojiFontSize)
    }

    @objc private func borderSliderChanged() {
        borderWidth = CGFloat(round(borderSlider.value))
        updateMetricLabels()
        scheduleRender()
    }

    @objc private func sizeSliderChanged() {
        emojiFontSize = CGFloat(round(sizeSlider.value))
        updateMetricLabels()
        scheduleRender()
    }

    @objc private func textFieldChanged() {
        selectedEmoji = textField.text ?? ""
        refreshPresetSelection()
        scheduleRender()
    }

    @objc private func presetTapped(_ sender: UIButton) {
        guard let t = buttonEmojiTitle(sender) else { return }
        selectedEmoji = t
        textField.text = t
        refreshPresetSelection()
        scheduleRender()
    }

    private func buttonEmojiTitle(_ button: UIButton) -> String? {
        if let t = button.configuration?.title, !t.isEmpty { return t }
        return button.title(for: .normal)
    }

    private func refreshPresetSelection() {
        let current = selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        for b in presetButtons {
            let isMatch = buttonEmojiTitle(b) == current
            b.layer.borderWidth = isMatch ? 2 : 0
            b.layer.borderColor = isMatch ? UIColor.systemBlue.cgColor : nil
        }
    }

    private func scheduleRender() {
        renderGeneration += 1
        let token = renderGeneration
        let emoji = selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let border = borderWidth
        let fontSize = emojiFontSize
        let rawScale = traitCollection.displayScale
        let displayScale =
            rawScale > 0 ? rawScale : (view.window?.screen.scale ?? UIScreen.main.scale)
        let cappedScale = max(displayScale, 2)

        let debounce: TimeInterval = 0.08

        DispatchQueue.main.asyncAfter(deadline: .now() + debounce) { [weak self] in
            guard let self else { return }
            guard token == self.renderGeneration else { return }

            if emoji.isEmpty {
                self.haloPreview.image = EmojiStickerRenderer.fallbackPreview(
                    emoji: "🍣",
                    fontSize: max(fontSize, 96),
                    scale: cappedScale
                )
                self.facePreview.image = nil
                return
            }

            guard let raster = EmojiStickerRenderer.rasterStickerSource(
                trimmedEmoji: emoji,
                fontSize: fontSize,
                displayScale: cappedScale
            ) else {
                self.haloPreview.image = EmojiStickerRenderer.fallbackPreview(
                    emoji: emoji,
                    fontSize: max(fontSize, 96),
                    scale: cappedScale
                )
                self.facePreview.image = nil
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let pieces = EmojiStickerRenderer.composeStickerLayers(
                    raster: raster,
                    borderWidthPoints: border,
                    displayScale: cappedScale
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard token == self.renderGeneration else { return }

                    if let pieces {
                        self.haloPreview.image = pieces.halo
                        self.facePreview.image = pieces.face
                    } else {
                        self.haloPreview.image = EmojiStickerRenderer.fallbackPreview(
                            emoji: emoji,
                            fontSize: max(fontSize, 96),
                            scale: cappedScale
                        )
                        self.facePreview.image = nil
                    }
                }
            }
        }
    }
}

extension EmojiStickerExperimentViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

