import SwiftUI
import AppKit

/// Resizes the hosting window when the content's desired size changes, keeping
/// the top-left corner where it is. AppKit anchors a resize to the bottom-left,
/// which would make the title bar jump every time the tracker panel is toggled.
struct WindowSizer: NSViewRepresentable {

    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resize(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { resize(nsView.window) }
    }

    private func resize(_ window: NSWindow?) {
        guard let window else { return }

        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let current = window.frame
        guard abs(current.height - target.height) > 0.5 || abs(current.width - target.width) > 0.5 else {
            return
        }

        let top = current.maxY
        let frame = NSRect(x: current.minX,
                           y: top - target.height,
                           width: target.width,
                           height: target.height)
        window.setFrame(frame, display: true, animate: false)
    }
}
