//
//  QuickLookPDFReproViewController.swift
//  shizen
//
//  DEBUG: reproduce QLPreviewController behavior with an app-generated PDF
//  written under Application Support (no tmp copy for the primary path).
//

import PDFKit
import QuickLook
import UIKit

final class QuickLookPDFReproViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()

    private var pdfURL: URL?
    private var lastPageCount: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "QuickLook PDF"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        configureLayout()
        refreshStatus(message: "Tap Generate, then try each preview path.")
    }

    // MARK: - UI

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        scrollView.addSubview(stack)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(makeButton("Generate PDF → Application Support", action: #selector(generatePDF)))
        stack.addArrangedSubview(makeButton("QuickLook (Application Support)", action: #selector(previewApplicationSupport)))
        stack.addArrangedSubview(makeButton("A) QuickLook (tmp copy)", action: #selector(previewTemporaryCopy)))
        stack.addArrangedSubview(makeButton("B) Share sheet", action: #selector(sharePDF)))
        stack.addArrangedSubview(makeButton("C) PDFView (PDFKit)", action: #selector(openPDFView)))

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func refreshStatus(message: String) {
        let device = UIDevice.current
        let pathLine: String
        if let pdfURL {
            pathLine = "PDF: \(pdfURL.path)\npages: \(lastPageCount)"
        } else {
            pathLine = "PDF: (none yet)"
        }
        statusLabel.text = """
        \(message)

        \(pathLine)

        Device: \(device.model) · \(device.systemName) \(device.systemVersion)
        Watch console for: “Failed to request default share mode”, file provider domain errors, LaunchServices -54 / canmaplsdatabase, CGImageSource/PDF initImage failures.
        """
    }

    private func requirePDFURL() -> URL? {
        guard let pdfURL else {
            refreshStatus(message: "Generate a PDF first.")
            return nil
        }
        return pdfURL
    }

    // MARK: - Actions

    @objc private func generatePDF() {
        do {
            let url = try Self.writeSamplePDF()
            pdfURL = url
            if let doc = PDFDocument(url: url) {
                lastPageCount = doc.pageCount
            } else {
                lastPageCount = 0
            }
            refreshStatus(message: "Generated OK. Primary test: QuickLook (Application Support) — do not copy to tmp.")
            print("[QuickLookPDFRepro] wrote \(url.path) pages=\(lastPageCount)")
        } catch {
            pdfURL = nil
            lastPageCount = 0
            refreshStatus(message: "Generate failed: \(error.localizedDescription)")
            print("[QuickLookPDFRepro] generate error: \(error)")
        }
    }

    @objc private func previewApplicationSupport() {
        guard let url = requirePDFURL() else { return }
        print("[QuickLookPDFRepro] QLPreview Application Support → \(url.path)")
        presentQuickLook(url: url)
    }

    @objc private func previewTemporaryCopy() {
        guard let source = requirePDFURL() else { return }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.removeItem(at: tmp)
            }
            try FileManager.default.copyItem(at: source, to: tmp)
            print("[QuickLookPDFRepro] QLPreview tmp copy → \(tmp.path)")
            presentQuickLook(url: tmp)
            refreshStatus(message: "Previewing tmp copy.\n\(tmp.path)")
        } catch {
            refreshStatus(message: "Tmp copy failed: \(error.localizedDescription)")
            print("[QuickLookPDFRepro] tmp copy error: \(error)")
        }
    }

    @objc private func sharePDF() {
        guard let url = requirePDFURL() else { return }
        print("[QuickLookPDFRepro] UIActivityViewController → \(url.path)")
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activity, animated: true)
        refreshStatus(message: "Presented share sheet for Application Support URL.")
    }

    @objc private func openPDFView() {
        guard let url = requirePDFURL() else { return }
        print("[QuickLookPDFRepro] PDFView → \(url.path)")
        let vc = PDFKitPreviewViewController(url: url)
        navigationController?.pushViewController(vc, animated: true)
        refreshStatus(message: "Opened PDFKit PDFView (not QuickLook).")
    }

    private func presentQuickLook(url: URL) {
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.delegate = self
        // Stash the URL the data source should return for this presentation.
        previewingURL = url
        present(preview, animated: true)
    }

    /// URL currently handed to QLPreviewController (Application Support or tmp).
    private var previewingURL: URL?

    // MARK: - PDF generation (main thread)

    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // 8.5×11 @ 72dpi

    private static func writeSamplePDF() throws -> URL {
        dispatchPrecondition(condition: .onQueue(.main))

        let qrImage = makeQRCodeImage(
            string: "https://example.com/quicklook-pdf-repro?\(UUID().uuidString)",
            logo: makeSimpleLogoImage()
        )
        let thumbA = downsample(makePlaceholderImage(color: .systemTeal, label: "A"), maxEdge: 240)
        let thumbB = downsample(makePlaceholderImage(color: .systemOrange, label: "B"), maxEdge: 240)

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            drawPage(
                context: context,
                pageIndex: 0,
                title: "QuickLook PDF Repro",
                qrImage: qrImage,
                thumbs: [thumbA, thumbB],
                includeLongContent: true
            )
            drawPage(
                context: context,
                pageIndex: 1,
                title: "Categories & Checklist",
                qrImage: qrImage,
                thumbs: [thumbA],
                includeLongContent: false
            )
            drawPage(
                context: context,
                pageIndex: 2,
                title: "More Grid Text",
                qrImage: nil,
                thumbs: [thumbB],
                includeLongContent: true
            )
        }

        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ReproError.invalidPDF
        }

        let id = UUID().uuidString
        let dir = try sessionPDFsDirectory().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func sessionPDFsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("SessionPDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func drawPage(
        context: UIGraphicsPDFRendererContext,
        pageIndex: Int,
        title: String,
        qrImage: UIImage?,
        thumbs: [UIImage],
        includeLongContent: Bool
    ) {
        context.beginPage()
        let bounds = pageBounds
        let margin: CGFloat = 36
        var y = margin

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.black,
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black,
        ]
        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.black,
        ]
        let gridAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray,
        ]

        (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
        y += 28
        let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        ("Generated \(dateText) · page \(pageIndex + 1)" as NSString)
            .draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttrs)
        y += 28

        if let qrImage {
            let qrSize: CGFloat = 120
            let qrRect = CGRect(x: bounds.width - margin - qrSize, y: margin, width: qrSize, height: qrSize)
            drawImageFlipped(qrImage, in: qrRect)
        }

        y = max(y, margin + 130)

        // Category sections
        let categories: [(String, [String])] = [
            ("Vocabulary", ["ねこ", "いぬ", "みず", "たべもの", "がっこう"]),
            ("Phrases", [
                "おはようございます",
                "ありがとうございます",
                "すみません、もう一度お願いします",
            ]),
            ("Notes", [
                "Short grid item",
                "Another short item",
                "A slightly longer grid cell that still fits a column",
            ]),
        ]

        let contentWidth = bounds.width - margin * 2
        for (sectionTitle, items) in categories {
            (sectionTitle as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 20

            // Grid of short items (2 columns)
            let colWidth = (contentWidth - 12) / 2
            var col = 0
            var rowY = y
            var maxRowY = y
            for item in items {
                let x = margin + CGFloat(col) * (colWidth + 12)
                let rect = CGRect(x: x, y: rowY, width: colWidth, height: 40)
                (item as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: gridAttrs, context: nil)
                maxRowY = max(maxRowY, rowY + 36)
                col += 1
                if col == 2 {
                    col = 0
                    rowY = maxRowY
                }
            }
            y = maxRowY + 12

            if includeLongContent {
                let long = """
                Full-width block for \(sectionTitle): this paragraph is intentionally longer so String.draw / NSString.draw wraps across the page width. QuickLook should render multi-line PDF text without hanging when the file lives under Application Support.
                """
                let longRect = CGRect(x: margin, y: y, width: contentWidth, height: 72)
                (long as NSString).draw(
                    with: longRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: bodyAttrs,
                    context: nil
                )
                y += 80
            }
        }

        // Bullet checklist
        ("Checklist" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 20
        let bullets = [
            "□ Generate PDF on main thread with UIGraphicsPDFRenderer",
            "□ Validate via PDFDocument(data:) pageCount > 0",
            "□ Write atomically under Application Support/SessionPDFs/<uuid>/<uuid>.pdf",
            "□ Preview with QLPreviewController without copying to tmp first — this line is long enough that it should wrap within the content width when drawn into the PDF page bounds",
            "□ Compare tmp copy, share sheet, and PDFKit PDFView variants",
        ]
        for bullet in bullets {
            let rect = CGRect(x: margin, y: y, width: contentWidth, height: 48)
            let used = (bullet as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: 48),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: bodyAttrs,
                context: nil
            )
            (bullet as NSString).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: bodyAttrs,
                context: nil
            )
            y += ceil(used.height) + 6
        }

        // Embedded downsampled images in rounded rects
        if !thumbs.isEmpty {
            y += 8
            ("Embedded images" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22
            var x = margin
            for thumb in thumbs {
                let rect = CGRect(x: x, y: y, width: 80, height: 80)
                drawRoundedImageFlipped(thumb, in: rect, cornerRadius: 12)
                x += 92
            }
        }
    }

    /// Draw a UIImage into PDF space with a flipped CGContext (UIKit → PDF coords).
    private static func drawImageFlipped(_ image: UIImage, in rect: CGRect) {
        guard let cg = image.cgImage, let ctx = UIGraphicsGetCurrentContext() else {
            image.draw(in: rect)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private static func drawRoundedImageFlipped(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        path.addClip()
        drawImageFlipped(image, in: rect)
        ctx.restoreGState()
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func makeQRCodeImage(string: String, logo: UIImage?) -> UIImage {
        let data = Data(string.utf8)
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            return makePlaceholderImage(color: .black, label: "QR")
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else {
            return makePlaceholderImage(color: .black, label: "QR")
        }
        let qr = UIImage(cgImage: cgImage)
        guard let logo else { return qr }

        let size = qr.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            qr.draw(in: CGRect(origin: .zero, size: size))
            let logoSide = min(size.width, size.height) * 0.22
            let logoRect = CGRect(
                x: (size.width - logoSide) / 2,
                y: (size.height - logoSide) / 2,
                width: logoSide,
                height: logoSide
            )
            UIColor.white.setFill()
            UIBezierPath(roundedRect: logoRect.insetBy(dx: -4, dy: -4), cornerRadius: 6).fill()
            logo.draw(in: logoRect)
        }
    }

    private static func makeSimpleLogoImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white,
            ]
            let text = "S" as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }

    private static func makePlaceholderImage(color: UIColor, label: String) -> UIImage {
        let size = CGSize(width: 320, height: 320)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            color.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.white,
            ]
            let text = label as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }

    private static func downsample(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxEdge else { return image }
        let scale = maxEdge / maxDim
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private enum ReproError: LocalizedError {
        case invalidPDF

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "PDFDocument validation failed (pageCount == 0)."
            }
        }
    }
}

// MARK: - QuickLook

extension QuickLookPDFReproViewController: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewingURL ?? pdfURL)! as NSURL
    }

    func previewControllerWillDismiss(_ controller: QLPreviewController) {
        print("[QuickLookPDFRepro] QLPreviewController will dismiss")
    }
}

// MARK: - PDFKit fallback

private final class PDFKitPreviewViewController: UIViewController {
    private let url: URL
    private let pdfView = PDFView()

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PDFView"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        pdfView.document = PDFDocument(url: url)
        print("[QuickLookPDFRepro] PDFView loaded pageCount=\(pdfView.document?.pageCount ?? -1)")
    }
}
