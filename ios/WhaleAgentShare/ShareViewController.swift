import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textView = UITextView()
    private let statusLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var sharedURL: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        loadSharedContent()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "发给鲸鱼"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        subtitleLabel.text = "确认内容后打开鲸鱼，让它总结或接着安排。"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 14
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        sendButton.setTitle("总结并打开鲸鱼", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        sendButton.backgroundColor = UIColor(red: 0.06, green: 0.55, blue: 0.58, alpha: 1)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.layer.cornerRadius = 14
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, textView, statusLabel, sendButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            sendButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func loadSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            statusLabel.text = "没有收到可分享的内容。"
            sendButton.isEnabled = false
            return
        }

        let group = DispatchGroup()
        var texts: [String] = []
        var urls: [String] = []
        let lock = NSLock()

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                        defer { group.leave() }
                        var value: String?
                        if let string = data as? String { value = string }
                        if let data = data as? Data { value = String(data: data, encoding: .utf8) }
                        if let value, !value.isEmpty { lock.lock(); texts.append(value); lock.unlock() }
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                        defer { group.leave() }
                        var value: String?
                        if let url = data as? URL { value = url.absoluteString }
                        if let string = data as? String { value = string }
                        if let value, !value.isEmpty { lock.lock(); urls.append(value); lock.unlock() }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.sharedURL = urls.first
            let text = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && urls.isEmpty {
                self.statusLabel.text = "没有取到可分享的文本或链接。"
                self.sendButton.isEnabled = false
                return
            }
            self.textView.text = text.isEmpty ? (urls.first ?? "") : text
            if text.isEmpty {
                self.statusLabel.text = "只收到了链接，正文可能不完整；鲸鱼会如实说明，不会编造摘要。"
            } else {
                self.statusLabel.text = "已取到分享内容，可以补充一句要求。"
            }
        }
    }

    @objc private func send() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let item = SharedItem(
            id: UUID().uuidString,
            text: text,
            url: sharedURL,
            title: nil,
            createdAt: Date()
        )
        SharedInbox.save(item)

        var components = URLComponents()
        components.scheme = "whaleagent"
        components.host = "share"
        var query: [URLQueryItem] = []
        if text.count <= 1500 {
            query.append(URLQueryItem(name: "text", value: text))
        }
        if let sharedURL, sharedURL.count <= 500 {
            query.append(URLQueryItem(name: "url", value: sharedURL))
        }
        query.append(URLQueryItem(name: "id", value: item.id))
        components.queryItems = query

        guard let url = components.url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        if openInHostApp(url) {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(url) { [weak self] opened in
            if opened {
                self?.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self?.statusLabel.text = "内容已保存。请返回主屏打开鲸鱼，会自动接着总结。"
                self?.sendButton.isEnabled = false
            }
        }
    }

    /// Share extensions are not allowed to use `extensionContext.open` in practice,
    /// so walk the responder chain to the host application.
    private func openInHostApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "WhaleAgentShare", code: -1))
    }
}
