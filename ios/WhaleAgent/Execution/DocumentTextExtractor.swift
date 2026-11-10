import Foundation
import PDFKit
import UIKit
import Vision

struct ExtractedDocument: Sendable {
    let text: String
    let pageCount: Int
    let kind: String
    let truncated: Bool

    var summary: String {
        let kindText = kind == "pdf" ? "PDF" : "图片"
        let pages = kind == "pdf" ? " · \(pageCount) 页" : ""
        return "识别\(kindText)\(pages) · \(text.count) 字" + (truncated ? "（已截断）" : "")
    }
}

enum DocumentTextExtractor {
    private static let maxCharacters = 6000
    private static let maxPDFPages = 8

    static func extract(url: URL) async throws -> ExtractedDocument {
        try await Task.detached(priority: .userInitiated) {
            try extractSync(url: url)
        }.value
    }

    private static func extractSync(url: URL) throws -> ExtractedDocument {
        if let document = PDFDocument(url: url), document.pageCount > 0 {
            return try extractPDF(document: document)
        }
        if CGImageSourceCreateWithURL(url as CFURL, nil) != nil {
            let text = try recognizeImage(url: url)
            return finish(text: text, pageCount: 1, kind: "image")
        }
        throw ToolExecutionError(code: "unsupported_document", message: "只支持图片和 PDF")
    }

    private static func extractPDF(document: PDFDocument) throws -> ExtractedDocument {
        let pageCount = min(document.pageCount, maxPDFPages)
        guard pageCount > 0 else {
            throw ToolExecutionError(code: "empty_pdf", message: "PDF 没有可识别的页面")
        }
        var pages: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let image = render(page: page)
            let text = try recognize(image: image)
            if !text.isEmpty { pages.append(text) }
        }
        return finish(text: pages.joined(separator: "\n\n"), pageCount: pageCount, kind: "pdf")
    }

    private static func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private static func recognizeImage(url: URL) throws -> String {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ToolExecutionError(code: "image_open_failed", message: "图片无法读取")
        }
        return try recognize(cgImage: image)
    }

    private static func recognize(image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else {
            throw ToolExecutionError(code: "image_open_failed", message: "图片无法转换")
        }
        return try recognize(cgImage: cgImage)
    }

    private static func recognize(cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ToolExecutionError(code: "ocr_failed", message: "文字识别失败：\(error.localizedDescription)")
        }
        let observations = (request.results ?? []).sorted { left, right in
            if abs(left.boundingBox.midY - right.boundingBox.midY) > 0.02 {
                return left.boundingBox.midY > right.boundingBox.midY
            }
            return left.boundingBox.minX < right.boundingBox.minX
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func finish(text: String, pageCount: Int, kind: String) -> ExtractedDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = trimmed.count > maxCharacters
        let clipped = truncated ? String(trimmed.prefix(maxCharacters)) : trimmed
        return ExtractedDocument(text: clipped, pageCount: pageCount, kind: kind, truncated: truncated)
    }
}
