import Foundation

struct MerchantPriceEvidence: Equatable, Sendable {
    let amount: Double
    let kind: String
    let context: String
    let sourceURL: String
    let sourceTitle: String
    let fetchedAt: String
    let branchMatch: String
}

/// Deterministic extraction for public-web price snippets. It only surfaces
/// lines that already contain a price signal; it never fills in a missing
/// amount or treats a brand-level page as a specific branch quotation.
enum MerchantPriceExtractor {
    private static let perPersonPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:人均(?:消费)?|平均消费|均价)\s*(?:约|为|在|仅|低至)?\s*[¥￥]?\s*(\d{1,5}(?:\.\d{1,2})?)\s*(?:元|块)?"#
    )
    private static let packagePattern = try! NSRegularExpression(
        pattern: #"(?i)(?:套餐|团购|双人餐|单人餐|代金券)[^。\n]{0,18}?(\d{1,4}(?:\.\d{1,2})?)\s*元"#
    )
    private static let labeledPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:价格|收费|套餐价|团购价|菜单价)\s*(?:约|为|在|仅|低至)?\s*[¥￥]?\s*(\d{1,5}(?:\.\d{1,2})?)\s*(?:元|块)?"#
    )
    private static let currencyPattern = try! NSRegularExpression(
        pattern: #"(?i)[¥￥]\s*(\d{1,5}(?:\.\d{1,2})?)"#
    )

    static func extract(
        text: String,
        merchant: String,
        branch: String?,
        city: String?,
        sourceURL: String,
        sourceTitle: String,
        fetchedAt: String
    ) -> [MerchantPriceEvidence] {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard merchantMentioned(in: normalized, merchant: merchant) else { return [] }
        let match = branchMatch(in: normalized, branch: branch, city: city)

        var rows: [MerchantPriceEvidence] = []
        var seen = Set<String>()

        func collect(_ regex: NSRegularExpression, fallbackKind: String, maximum: Int) {
            guard rows.count < maximum else { return }
            let ns = normalized as NSString
            let range = NSRange(location: 0, length: ns.length)
            for result in regex.matches(in: normalized, range: range) {
                guard rows.count < maximum,
                      result.numberOfRanges > 1,
                      let amountRange = Range(result.range(at: 1), in: normalized),
                      let amount = Double(String(normalized[amountRange])),
                      amount >= 0.5,
                      amount <= 9_999 else { continue }
                let context = contextText(in: ns, matchRange: result.range)
                guard !context.isEmpty else { continue }
                let kind = fallbackKind
                let key = "\(amount)-\(context.prefix(24))"
                guard seen.insert(key).inserted else { continue }
                rows.append(
                    MerchantPriceEvidence(
                        amount: amount,
                        kind: kind,
                        context: context,
                        sourceURL: sourceURL,
                        sourceTitle: sourceTitle,
                        fetchedAt: fetchedAt,
                        branchMatch: match
                    )
                )
            }
        }

        collect(perPersonPattern, fallbackKind: "per_person", maximum: 12)
        collect(packagePattern, fallbackKind: "package", maximum: 12)
        collect(labeledPattern, fallbackKind: "listed", maximum: 12)
        collect(currencyPattern, fallbackKind: "currency", maximum: 12)
        return rows
    }

    static func branchMatch(in text: String, branch: String?, city: String?) -> String {
        let haystack = text.lowercased()
        if let branch {
            let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                let lowered = value.lowercased()
                if haystack.contains(lowered) { return "matched" }
                let variants = [
                    lowered.replacingOccurrences(of: "分店", with: ""),
                    lowered.replacingOccurrences(of: "店", with: "")
                ]
                if variants.contains(where: { $0.count >= 2 && haystack.contains($0) }) {
                    return "partial"
                }
            }
        }
        if let city {
            let value = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.count >= 2 && haystack.contains(value) { return "city_only" }
        }
        return "unverified"
    }

    static func merchantMentioned(in text: String, merchant: String) -> Bool {
        let haystack = text.lowercased()
        let value = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count >= 2 else { return false }
        if haystack.contains(value) { return true }
        let core = value.components(separatedBy: CharacterSet(charactersIn: "（(")).first ?? value
        return core.count >= 2 && haystack.contains(core)
    }

    private static func contextText(in text: NSString, matchRange: NSRange) -> String {
        let radius = 46
        let start = max(0, matchRange.location - radius)
        let end = min(text.length, matchRange.location + matchRange.length + radius)
        guard end > start else { return "" }
        let raw = text.substring(with: NSRange(location: start, length: end - start))
        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class MerchantPriceExecutor {
    private let web: WebContentExecutor

    init(web: WebContentExecutor) {
        self.web = web
    }

    func search(arguments: [String: JSONValue]) async throws -> JSONValue {
        let merchant = try arguments.requiredString("merchant")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard merchant.count >= 2 else {
            throw ToolExecutionError(code: "invalid_arguments", message: "商户名至少需要 2 个字符")
        }
        let branch = clean(arguments.optionalString("branch"))
        let city = clean(arguments.optionalString("city"))
        let limit = min(max(arguments.optionalInt("limit") ?? 5, 1), 12)
        let fetchedAt = ToolDate.iso(Date())
        let query = [merchant, branch ?? city, "人均 价格 菜单"]
            .compactMap { $0 }
            .joined(separator: " ")

        var candidates: [(title: String, url: String)] = []
        var seenURLs = Set<String>()
        var searchFailure: String?
        do {
            let payload = try await web.search(query: query, limit: 8, timeout: 6)
            let results = payload.objectValue?["results"]?.arrayValue ?? []
            for result in results {
                guard let object = result.objectValue,
                      let url = object.optionalString("url"),
                      let title = object.optionalString("title"),
                      !url.contains("bing.com"),
                      seenURLs.insert(url).inserted else { continue }
                candidates.append((title, url))
            }
        } catch {
            searchFailure = error.localizedDescription
        }

        let selected = Array(candidates.prefix(3))
        var evidence: [MerchantPriceEvidence] = []
        var sources: [JSONValue] = []
        let deadline = Date().addingTimeInterval(17)
        var successfulPages = 0

        for candidate in selected where successfulPages < 2 {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 2.5 else { break }
            do {
                let page = try await web.fetch(
                    urlString: candidate.url,
                    maxChars: 8_000,
                    timeout: min(5, remaining)
                )
                guard let object = page.objectValue,
                      let text = object.optionalString("text") else { continue }
                let title = object.optionalString("title") ?? candidate.title
                let pageFetchedAt = object.optionalString("fetchedAt") ?? fetchedAt
                successfulPages += 1
                let rows = MerchantPriceExtractor.extract(
                    text: text,
                    merchant: merchant,
                    branch: branch,
                    city: city,
                    sourceURL: candidate.url,
                    sourceTitle: title,
                    fetchedAt: pageFetchedAt
                )
                evidence.append(contentsOf: rows)
                sources.append(
                    .object([
                        "title": .string(title),
                        "url": .string(candidate.url),
                        "status": .string("fetched"),
                        "fetchedAt": .string(pageFetchedAt),
                        "merchantMentioned": .bool(!rows.isEmpty || MerchantPriceExtractor.merchantMentioned(in: text, merchant: merchant)),
                        "branchMatch": .string(MerchantPriceExtractor.branchMatch(in: text, branch: branch, city: city)),
                        "textLength": .number(Double(text.count))
                    ])
                )
            } catch {
                sources.append(
                    .object([
                        "title": .string(candidate.title),
                        "url": .string(candidate.url),
                        "status": .string("failed"),
                        "error": .string(error.localizedDescription)
                    ])
                )
            }
        }

        let trimmed = Array(evidence.prefix(limit))
        let note: String
        if trimmed.isEmpty {
            note = "公开网页没有提取到可核对的价格。不要把品牌价、搜索摘要或记忆中的数字当作该商户价格。"
        } else if trimmed.allSatisfy({ $0.branchMatch == "matched" }) {
            note = "价格来自公开网页，已出现分店名称，但仍未与商家实时核对；需说明来源与取得时间。"
        } else {
            note = "价格来自公开网页，分店匹配不完整；只能作为品牌或同城参考，不能声称是该分店报价。"
        }

        return .object([
            "merchant": .string(merchant),
            "branch": branch.map { JSONValue.string($0) } ?? .null,
            "city": city.map { JSONValue.string($0) } ?? .null,
            "query": .string(query),
            "evidence": .array(trimmed.map { row in
                .object([
                    "amount": .number(row.amount),
                    "currency": .string("CNY"),
                    "kind": .string(row.kind),
                    "context": .string(row.context),
                    "sourceURL": .string(row.sourceURL),
                    "sourceTitle": .string(row.sourceTitle),
                    "fetchedAt": .string(row.fetchedAt),
                    "branchMatch": .string(row.branchMatch)
                ])
            }),
            "evidenceCount": .number(Double(trimmed.count)),
            "sources": .array(sources),
            "sourceCount": .number(Double(sources.count)),
            "searchFailure": searchFailure.map { JSONValue.string($0) } ?? .null,
            "priceDataAvailable": .bool(!trimmed.isEmpty),
            "verified": .bool(false),
            "source": .string("public_web"),
            "fetchedAt": .string(fetchedAt),
            "simulated": .bool(false),
            "note": .string(note)
        ])
    }

    private func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
