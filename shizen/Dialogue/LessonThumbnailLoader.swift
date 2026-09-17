//
//  LessonThumbnailLoader.swift
//  shizen
//
//  Downsampled, disk-cached lesson thumbnails with in-flight coalescing.
//

import ImageIO
import UIKit

enum LessonThumbnailLoader {

    enum Variant: String {
        case color
        case grayscale
    }

    private static let lock = NSLock()
    private static var inFlightCompletions: [String: [(UIImage?) -> Void]] = [:]
    private static let decodeQueue = DispatchQueue(
        label: "shizen.LessonThumbnailLoader.decode",
        qos: .utility,
        attributes: .concurrent
    )

    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    private static let session: URLSession = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LessonThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: directory
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    static func cachedImage(for url: URL) -> UIImage? {
        cachedImage(for: url, targetPixelSize: nil, variant: .color)
    }

    static func cachedImage(
        for url: URL,
        targetPixelSize: CGFloat?,
        variant: Variant
    ) -> UIImage? {
        memoryCache.object(forKey: cacheKey(url: url, targetPixelSize: targetPixelSize, variant: variant) as NSString)
    }

    static func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        load(url: url, targetPixelSize: nil, variant: .color, completion: completion)
    }

    static func load(
        url: URL,
        targetPixelSize: CGFloat?,
        variant: Variant,
        completion: @escaping (UIImage?) -> Void
    ) {
        let key = cacheKey(url: url, targetPixelSize: targetPixelSize, variant: variant)
        if let cached = memoryCache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        lock.lock()
        if inFlightCompletions[key] != nil {
            inFlightCompletions[key, default: []].append(completion)
            lock.unlock()
            return
        }
        inFlightCompletions[key] = [completion]
        lock.unlock()

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        session.dataTask(with: request) { data, response, _ in
            decodeQueue.async {
                let image: UIImage?
                let httpOK = (response as? HTTPURLResponse).map { (200 ... 299).contains($0.statusCode) } ?? true
                if let data, !data.isEmpty, httpOK {
                    image = decodeImage(data: data, targetPixelSize: targetPixelSize, variant: variant)
                    if let image {
                        store(image, key: key)
                    }
                } else {
                    image = nil
                }
                finish(key: key, image: image)
            }
        }.resume()
    }

    static func prefetch(_ urls: [URL], targetPixelSize: CGFloat?) {
        for url in urls {
            load(url: url, targetPixelSize: targetPixelSize, variant: .color) { _ in }
        }
    }

    static func bundledImage(
        named name: String,
        targetPixelSize: CGFloat?,
        variant: Variant
    ) -> UIImage? {
        let key = cacheKey(asset: name, targetPixelSize: targetPixelSize, variant: variant)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        guard let image = UIImage(named: name) else { return nil }
        let processed = process(image, targetPixelSize: targetPixelSize, variant: variant)
        store(processed, key: key)
        return processed
    }

    private static func finish(key: String, image: UIImage?) {
        lock.lock()
        let completions = inFlightCompletions.removeValue(forKey: key) ?? []
        lock.unlock()
        DispatchQueue.main.async {
            for completion in completions {
                completion(image)
            }
        }
    }

    private static func store(_ image: UIImage, key: String) {
        let cost: Int
        if let cgImage = image.cgImage {
            cost = cgImage.bytesPerRow * cgImage.height
        } else {
            cost = 0
        }
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private static func cacheKey(url: URL, targetPixelSize: CGFloat?, variant: Variant) -> String {
        "\(url.absoluteString)|\(pixelToken(targetPixelSize))|\(variant.rawValue)"
    }

    private static func cacheKey(asset name: String, targetPixelSize: CGFloat?, variant: Variant) -> String {
        "asset:\(name)|\(pixelToken(targetPixelSize))|\(variant.rawValue)"
    }

    private static func pixelToken(_ targetPixelSize: CGFloat?) -> String {
        targetPixelSize.map { String(Int($0.rounded())) } ?? "full"
    }

    private static func decodeImage(
        data: Data,
        targetPixelSize: CGFloat?,
        variant: Variant
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let targetPixelSize, targetPixelSize > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = Int(targetPixelSize.rounded())
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        return variant == .grayscale ? makeGrayscale(image) : image
    }

    private static func process(
        _ image: UIImage,
        targetPixelSize: CGFloat?,
        variant: Variant
    ) -> UIImage {
        let sized: UIImage
        if let targetPixelSize,
           let cgImage = image.cgImage,
           max(cgImage.width, cgImage.height) > Int(targetPixelSize.rounded()),
           let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92),
           let downsampled = decodeImage(data: data, targetPixelSize: targetPixelSize, variant: .color)
        {
            sized = downsampled
        } else {
            sized = image
        }
        return variant == .grayscale ? makeGrayscale(sized) : sized
    }

    private static func makeGrayscale(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let gray = context.makeImage() else { return image }
        return UIImage(cgImage: gray, scale: image.scale, orientation: image.imageOrientation)
    }
}
