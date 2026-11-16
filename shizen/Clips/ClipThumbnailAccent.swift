//
//  ClipThumbnailAccent.swift
//  shizen
//
//  Experiment: tint the clip player's karaoke highlight from the video's
//  thumbnail instead of the app-wide yellow. Toggle from a clip's options menu →
//  Experiments; saturation and opacity are on the ambient tuning sheet.
//

import UIKit

// MARK: - Thumbnail cache

/// YouTube's hqdefault frame per video, fetched once and shared by the ambient
/// backdrop and the highlight accent.
@MainActor
enum ClipThumbnail {
    private static var images: [String: UIImage] = [:]
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    static func cached(videoID: String) -> UIImage? { images[videoID] }

    static func image(videoID: String) async -> UIImage? {
        if let image = images[videoID] { return image }
        if let task = inFlight[videoID] { return await task.value }
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard let url = URL(string: "https://i.ytimg.com/vi/\(safeID)/hqdefault.jpg") else { return nil }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[videoID] = task
        let image = await task.value
        inFlight[videoID] = nil
        if let image { images[videoID] = image }
        return image
    }
}

// MARK: - Accent

@MainActor
enum ClipThumbnailAccent {
    /// The app-wide playback marker, used when the experiment is off or a
    /// thumbnail has no usable color.
    static let fallback = FuriganaTranscriptLabel.tokenSyncHighlightColor

    /// Hue (degrees) per video; nil means "no usable color, use the fallback".
    private static var hues: [String: Double?] = [:]

    /// Already computed for this video (so callers can skip the yellow flash).
    static func cachedColor(videoID: String) -> UIColor? {
        guard let entry = hues[videoID] else { return nil }
        return color(hue: entry)
    }

    static func color(videoID: String) async -> UIColor {
        if let cached = cachedColor(videoID: videoID) { return cached }
        guard let image = await ClipThumbnail.image(videoID: videoID) else { return fallback }
        let hue = hues[videoID] ?? dominantHue(in: image).map(avoidingSelectionBlue)
        hues[videoID] = hue
        return color(hue: hue)
    }

    /// The extracted hue at a fixed saturation and full brightness, so every clip's
    /// marker is equally light and the glyphs on top stay readable.
    private static func color(hue: Double?) -> UIColor {
        guard let hue else { return fallback }
        return UIColor(
            hue: hue / 360,
            saturation: CGFloat(ClipAmbientSettings[.highlightSaturation]),
            brightness: 1,
            alpha: CGFloat(ClipAmbientSettings[.highlightOpacity])
        )
    }

    // MARK: Extraction

    private static let sampleSide = 24
    private static let hueBins = 24
    /// Pixels grayer or darker than this don't vote (skies, walls, shadows).
    private static let minSaturation = 0.3
    private static let minBrightness = 0.25
    /// Below this share of voting pixels the thumbnail counts as gray: keep yellow.
    private static let minChromaticShare = 0.06

    /// The most vivid hue that covers a real area of the frame, not the average
    /// (averages of thumbnails come out brown). Votes are weighted by saturation²
    /// × brightness and smoothed over neighbor bins so a hue on a bin edge isn't split.
    static func dominantHue(in image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var weights = [Double](repeating: 0, count: hueBins)
        var vectors = [(x: Double, y: Double)](repeating: (0, 0), count: hueBins)
        var chromatic = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            guard maxC >= minBrightness, delta > 0 else { continue }
            let saturation = delta / maxC
            guard saturation >= minSaturation else { continue }
            var hue: Double
            if maxC == r { hue = (g - b) / delta }
            else if maxC == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue = (hue * 60).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
            let weight = saturation * saturation * maxC
            let bin = min(hueBins - 1, Int(hue / 360 * Double(hueBins)))
            let radians = hue * .pi / 180
            weights[bin] += weight
            vectors[bin].x += cos(radians) * weight
            vectors[bin].y += sin(radians) * weight
            chromatic += 1
        }
        guard Double(chromatic) / Double(side * side) >= minChromaticShare else { return nil }

        let neighbors = { (bin: Int) in [(bin + hueBins - 1) % hueBins, bin, (bin + 1) % hueBins] }
        guard let best = (0 ..< hueBins).max(by: { a, b in
            neighbors(a).reduce(0) { $0 + weights[$1] } < neighbors(b).reduce(0) { $0 + weights[$1] }
        }) else { return nil }
        let x = neighbors(best).reduce(0) { $0 + vectors[$1].x }
        let y = neighbors(best).reduce(0) { $0 + vectors[$1].y }
        guard x != 0 || y != 0 else { return nil }
        let hue = atan2(y, x) * 180 / .pi
        return hue < 0 ? hue + 360 : hue
    }

    /// systemBlue's hue: the definition-tip selection. Too close and "now playing"
    /// and "selected word" look the same, so push the marker out to teal or indigo.
    private static let selectionHue = 211.0
    private static let selectionClearance = 28.0

    private static func avoidingSelectionBlue(_ hue: Double) -> Double {
        let offset = hue - selectionHue
        guard abs(offset) < selectionClearance else { return hue }
        return offset < 0 ? selectionHue - selectionClearance : selectionHue + selectionClearance
    }
}
