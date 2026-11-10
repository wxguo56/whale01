import SwiftUI
import UIKit

/// Re-enables the system left-edge swipe-back gesture on screens that hide
/// the navigation bar. SwiftUI disables `interactivePopGestureRecognizer` when
/// the bar is hidden, so the gesture is restored without adding a custom
/// transition or faking the system animation.
struct SwipeBackEnabler: UIViewRepresentable {
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            attach(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            attach(from: uiView, coordinator: context.coordinator)
        }
    }

    private func attach(from view: UIView, coordinator: Coordinator) {
        var responder: UIResponder? = view
        while let current = responder {
            if let navigation = current as? UINavigationController {
                guard let gesture = navigation.interactivePopGestureRecognizer else { return }
                if (gesture.delegate as AnyObject?) !== coordinator {
                    gesture.delegate = coordinator
                }
                gesture.isEnabled = true
                coordinator.navigationController = navigation
                return
            }
            responder = current.next
        }
    }
}
