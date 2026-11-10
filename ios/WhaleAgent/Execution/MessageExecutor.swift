import Contacts
import Foundation
import MessageUI
import UIKit

extension Notification.Name {
    static let whaleComposerFinished = Notification.Name("whale.composer.finished")
}

@MainActor
final class MessageExecutor {
    private struct ResolvedRecipient {
        let value: String
        let name: String?
    }

    private struct RecipientCandidate {
        let value: String
        let name: String?
        let identifier: String
    }

    private let contactStore = CNContactStore()

    func prepare(arguments: [String: JSONValue]) async throws -> JSONValue {
        let channel = try arguments.requiredString("channel")
        guard channel == "sms" || channel == "email" else {
            throw ToolExecutionError(code: "invalid_channel", message: "channel 只能是 sms 或 email")
        }
        let recipientId = try arguments.requiredString("recipientId")
        let body = try arguments.requiredString("body")
        let subject = arguments.optionalString("subject") ?? ""
        let recipient = try await resolveRecipient(recipientId, channel: channel)

        switch channel {
        case "sms":
            guard MFMessageComposeViewController.canSendText() else {
                throw ToolExecutionError(
                    code: "messages_unavailable",
                    message: "当前设备不能发送短信（模拟器或未配置信息账户）"
                )
            }
            guard SystemComposerPresenter.shared.presentMessage(recipients: [recipient.value], body: body) else {
                throw ToolExecutionError(code: "messages_present_failed", message: "无法打开系统短信界面")
            }
            return .object([
                "draft": .string("opened"),
                "channel": .string("sms"),
                "recipient": .string(recipient.value),
                "recipientName": recipient.name.map { JSONValue.string($0) } ?? .null,
                "body": .string(body),
                "sent": .bool(false),
                "note": .string("已打开系统短信界面；发送结果以系统回调为准"),
                "source": .string("messageui"),
                "simulated": .bool(false)
            ])
        default:
            guard MFMailComposeViewController.canSendMail() else {
                throw ToolExecutionError(code: "mail_unavailable", message: "当前设备没有配置邮件账户")
            }
            guard SystemComposerPresenter.shared.presentMail(
                recipients: [recipient.value],
                subject: subject,
                body: body
            ) else {
                throw ToolExecutionError(code: "mail_present_failed", message: "无法打开系统邮件界面")
            }
            return .object([
                "draft": .string("opened"),
                "channel": .string("email"),
                "recipient": .string(recipient.value),
                "recipientName": recipient.name.map { JSONValue.string($0) } ?? .null,
                "subject": .string(subject),
                "body": .string(body),
                "sent": .bool(false),
                "note": .string("已打开系统邮件界面；发送结果以系统回调为准"),
                "source": .string("messageui"),
                "simulated": .bool(false)
            ])
        }
    }

    private func resolveRecipient(_ raw: String, channel: String) async throws -> ResolvedRecipient {
        let requested = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if channel == "sms" && looksLikePhone(requested) {
            return ResolvedRecipient(value: requested, name: nil)
        }
        if channel == "email" && requested.contains("@") {
            return ResolvedRecipient(value: requested, name: nil)
        }

        if
            let contact = try? contactStore.unifiedContact(withIdentifier: requested, keysToFetch: contactKeys)
        {
            return try selectCandidate(
                from: candidates(for: contact, channel: channel),
                requested: requested,
                channel: channel
            )
        }

        let predicate = CNContact.predicateForContacts(matchingName: requested)
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: contactKeys)
        var found: [RecipientCandidate] = []
        for contact in contacts {
            found.append(contentsOf: candidates(for: contact, channel: channel))
        }
        return try selectCandidate(from: found, requested: requested, channel: channel)
    }

    private func selectCandidate(
        from candidates: [RecipientCandidate],
        requested: String,
        channel: String
    ) throws -> ResolvedRecipient {
        var seen = Set<String>()
        let unique = candidates.filter { candidate in
            let key = candidateKey(candidate.value, channel: channel)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        guard !unique.isEmpty else {
            throw ToolExecutionError(
                code: "contact_not_found",
                message: "通讯录里没有找到 \(requested) 的\(channel == "sms" ? "电话" : "邮箱")"
            )
        }
        if unique.count == 1, let candidate = unique.first {
            return ResolvedRecipient(value: candidate.value, name: candidate.name)
        }
        let labels = unique.prefix(5).map(candidateLabel).joined(separator: "、")
        throw ToolExecutionError(
            code: "ambiguous_contact",
            message: "通讯录里找到 \(unique.count) 个候选：\(labels)。请明确要发给哪一个（可直接回复完整号码或邮箱），不要直接选第一个。"
        )
    }

    private func candidates(for contact: CNContact, channel: String) -> [RecipientCandidate] {
        let name = displayName(contact)
        if channel == "sms" {
            return contact.phoneNumbers.compactMap { item in
                let value = item.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                return RecipientCandidate(value: value, name: name, identifier: contact.identifier)
            }
        }
        return contact.emailAddresses.compactMap { item in
            let value = String(item.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return RecipientCandidate(value: value, name: name, identifier: contact.identifier)
        }
    }

    private func candidateKey(_ value: String, channel: String) -> String {
        if channel == "sms" {
            return value.filter(\.isNumber)
        }
        return value.lowercased()
    }

    private func candidateLabel(_ candidate: RecipientCandidate) -> String {
        let masked = maskedValue(candidate.value)
        if let name = candidate.name, !name.isEmpty {
            return "\(name)（\(masked)）"
        }
        return masked
    }

    private func maskedValue(_ value: String) -> String {
        if value.contains("@") {
            let parts = value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return "***" }
            let prefix = parts[0].prefix(1)
            return "\(prefix)***@\(parts[1])"
        }
        let digits = value.filter(\.isNumber)
        if digits.count >= 7 {
            return "\(digits.prefix(3))****\(digits.suffix(4))"
        }
        return "***"
    }

    private var contactKeys: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
    }

    private func displayName(_ contact: CNContact) -> String? {
        CNContactFormatter.string(from: contact, style: .fullName)
    }

    private func looksLikePhone(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count >= 5
    }
}

final class SystemComposerPresenter: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    static let shared = SystemComposerPresenter()

    @MainActor
    func presentMessage(recipients: [String], body: String) -> Bool {
        guard MFMessageComposeViewController.canSendText(), let top = Self.topViewController() else {
            return false
        }
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = self
        controller.recipients = recipients
        controller.body = body
        top.present(controller, animated: true)
        return true
    }

    @MainActor
    func presentMail(recipients: [String], subject: String, body: String) -> Bool {
        guard MFMailComposeViewController.canSendMail(), let top = Self.topViewController() else {
            return false
        }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        top.present(controller, animated: true)
        return true
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
        let text: String
        switch result {
        case .sent: text = "短信已发送"
        case .cancelled: text = "短信草稿已取消，未发送"
        case .failed: text = "短信发送失败"
        @unknown default: text = "短信草稿已关闭"
        }
        NotificationCenter.default.post(name: .whaleComposerFinished, object: nil, userInfo: ["text": text])
    }

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
        let text: String
        switch result {
        case .sent: text = "邮件已发送"
        case .saved: text = "邮件已存为草稿，未发送"
        case .cancelled: text = "邮件草稿已取消，未发送"
        case .failed: text = error.map { "邮件发送失败：\($0.localizedDescription)" } ?? "邮件发送失败"
        @unknown default: text = "邮件草稿已关闭"
        }
        NotificationCenter.default.post(name: .whaleComposerFinished, object: nil, userInfo: ["text": text])
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let navigation = top as? UINavigationController {
            return navigation.visibleViewController
        }
        if let tab = top as? UITabBarController {
            return tab.selectedViewController
        }
        return top
    }
}
