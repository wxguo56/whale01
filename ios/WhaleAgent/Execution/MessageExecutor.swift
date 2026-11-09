import Contacts
import Foundation
import MessageUI
import UIKit

@MainActor
final class MessageExecutor {
    private struct ResolvedRecipient {
        let value: String
        let name: String?
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
        if channel == "sms" && looksLikePhone(raw) {
            return ResolvedRecipient(value: raw, name: nil)
        }
        if channel == "email" && raw.contains("@") {
            return ResolvedRecipient(value: raw, name: nil)
        }

        if
            let contact = try? contactStore.unifiedContact(withIdentifier: raw, keysToFetch: contactKeys),
            let value = preferredValue(for: contact, channel: channel)
        {
            return ResolvedRecipient(value: value, name: displayName(contact))
        }

        let predicate = CNContact.predicateForContacts(matchingName: raw)
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: contactKeys)
        for contact in contacts {
            if let value = preferredValue(for: contact, channel: channel) {
                return ResolvedRecipient(value: value, name: displayName(contact))
            }
        }

        throw ToolExecutionError(
            code: "contact_not_found",
            message: "通讯录里没有找到 \(raw) 的\(channel == "sms" ? "电话" : "邮箱")"
        )
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

    private func preferredValue(for contact: CNContact, channel: String) -> String? {
        if channel == "sms" {
            return contact.phoneNumbers.first?.value.stringValue
        }
        return contact.emailAddresses.first.map { String($0.value) }
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
    }

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
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
