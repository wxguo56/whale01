import SwiftUI
import UIKit

/// Left-edge swipe-back for the conversation. The conversation lives inside the
/// root pager instead of a `NavigationStack`, so the system pop gesture is not
/// available; this installs the same screen-edge recognizer on the content.
struct ConversationBackSwipe: UIViewRepresentable {
    var isEnabled: Bool = true
    let onBack: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBack: (() -> Void)?
        weak var gesture: UIScreenEdgePanGestureRecognizer?

        @objc func handle(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            guard translation.x > 40, abs(translation.x) > abs(translation.y) else { return }
            onBack?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    /// Only the left edge is hit-testable, so message taps elsewhere stay intact.
    final class EdgeView: UIView {
        var edgeWidth: CGFloat = 22

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard point.x <= edgeWidth, point.x >= 0 else { return nil }
            return self
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> EdgeView {
        let view = EdgeView()
        view.backgroundColor = .clear

        let recognizer = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.edges = .left
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        view.addGestureRecognizer(recognizer)

        context.coordinator.onBack = onBack
        context.coordinator.gesture = recognizer
        return view
    }

    func updateUIView(_ uiView: EdgeView, context: Context) {
        context.coordinator.onBack = onBack
        context.coordinator.gesture?.isEnabled = isEnabled
    }
}