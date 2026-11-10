import Combine
import SwiftUI
import UIKit

/// Tracks the keyboard top edge in window coordinates.
///
/// The horizontal pager ignores the keyboard safe area on purpose. Letting the
/// pager itself resize makes every page relayout whenever the IME candidate
/// bar changes height, which shows up as the chat list jumping up and down
/// while the user is typing. Each page applies the keyboard inset locally.
final class KeyboardObserver: ObservableObject {
    @Published private(set) var top: CGFloat?

    var isVisible: Bool { top != nil }

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.apply(notification)
            }
        )
        observers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    self?.top = nil
                }
            }
        )
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func apply(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = Self.activeWindow
        else {
            top = nil
            return
        }

        let frame = window.convert(endFrame, from: nil)
        if frame.minY >= window.bounds.maxY - 1 {
            withAnimation(.easeOut(duration: 0.18)) {
                top = nil
            }
            return
        }

        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            top = frame.minY
        }
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}