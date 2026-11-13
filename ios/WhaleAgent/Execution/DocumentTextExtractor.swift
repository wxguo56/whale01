import Foundation
import PDFKit
import UIKit
import Vision

struct ExtractedDocument: Sendable {
    let text: String
    let pageCount: Int
    let kind: String
    let truncated: Bool
    var totalPages: Int? = nil

    var summary: String {
        let kindText = kind == "pdf" ? "PDF" : "图片"
        let pages = kind == "pdf" ? " · 已处理前 \(pageCount) / \(totalPages ?? pageCount) 页" : ""
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
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 25 * 1024 * 1024 else {
            throw ToolExecutionError(code: "document_too_large", message: "文件超过 25 MB，请先缩小或拆分后导入。")
        }
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
        var processed = 0
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let text = try autoreleasepool { () throws -> String in
                if let layer = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !layer.isEmpty { return layer }
                return try recognize(image: render(page: page))
            }
            processed += 1
            if !text.isEmpty { pages.append(text) }
            if pages.reduce(0, { $0 + $1.count }) >= maxCharacters { break }
        }
        var result = finish(text: pages.joined(separator: "\n\n"), pageCount: processed, kind: "pdf", omittedPages: processed < document.pageCount)
        result.totalPages = document.pageCount
        return result
    }

    private static func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let longest = max(bounds.width, bounds.height)
        let scale: CGFloat = min(2.0, 2048 / max(longest, 1))
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
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
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ] as CFDictionary)
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

    private static func finish(text: String, pageCount: Int, kind: String, omittedPages: Bool = false) -> ExtractedDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = trimmed.count > maxCharacters || omittedPages
        let clipped = truncated ? String(trimmed.prefix(maxCharacters)) : trimmed
        return ExtractedDocument(text: clipped, pageCount: pageCount, kind: kind, truncated: truncated)
    }
}
