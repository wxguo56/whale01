import SafariServices
import SwiftUI

struct SafariTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// In-app browser so external articles keep the whale session in the background
/// instead of switching the whole app to Safari.
struct InAppSafari: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(WhaleTheme.accent)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}