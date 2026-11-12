import SwiftUI
import UIKit

/// Remembers the enclosing vertical scroll view's content offset per key.
/// Attach with `.background(ScrollOffsetMemory(key: "channel"))` on a ScrollView.
struct ScrollOffsetMemory: UIViewRepresentable {
    let key: String

    final class Coordinator {
        let key: String
        var observation: NSKeyValueObservation?
        var saveWork: DispatchWorkItem?
        weak var scrollView: UIScrollView?
        var lastOffset: CGFloat = 0
        var isRestoring = false

        init(key: String) {
            self.key = key
        }

        deinit {
            saveWork?.cancel()
            if !isRestoring {
                persist(lastOffset)
            }
        }

        func persist(_ offset: CGFloat) {
            UserDefaults.standard.set(Double(offset), forKey: "whale.scroll." + key)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(key: key)
    }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
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
        guard let scrollView = Self.findScrollView(near: view),
              coordinator.scrollView !== scrollView else { return }
        coordinator.observation = nil
        coordinator.scrollView = scrollView
        coordinator.lastOffset = scrollView.contentOffset.y
        restore(on: scrollView, coordinator: coordinator)
        coordinator.observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak coordinator] scrollView, _ in
            guard let coordinator, !coordinator.isRestoring else { return }
            coordinator.lastOffset = scrollView.contentOffset.y
            coordinator.saveWork?.cancel()
            let work = DispatchWorkItem { [weak coordinator] in
                guard let coordinator, !coordinator.isRestoring else { return }
                coordinator.persist(coordinator.lastOffset)
            }
            coordinator.saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func restore(on scrollView: UIScrollView, coordinator: Coordinator) {
        let stored = UserDefaults.standard.double(forKey: "whale.scroll." + key)
        guard stored > 1 else { return }
        coordinator.isRestoring = true

        func attempt(_ remaining: Int) {
            let maxOffset = max(0, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
            if maxOffset < CGFloat(stored) * 0.6, remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { attempt(remaining - 1) }
                return
            }
            let target = min(CGFloat(stored), maxOffset)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                coordinator.isRestoring = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { attempt(4) }
    }

    private static func findScrollView(near view: UIView) -> UIScrollView? {
        var node: UIView? = view
        for _ in 0..<6 {
            guard let current = node else { break }
            if let found = largestScrollView(in: current) { return found }
            node = current.superview
        }
        return nil
    }

    private static func largestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ node: UIView) {
            if let scroll = node as? UIScrollView,
               scroll.bounds.height > 160,
               scroll.contentSize.height > scroll.bounds.height {
                if best == nil || scroll.bounds.height > best!.bounds.height {
                    best = scroll
                }
            }
            for child in node.subviews {
                walk(child)
            }
        }
        walk(root)
        return best
    }
}

private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}