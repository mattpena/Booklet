import AppKit
import SwiftUI

struct ArrowKeyNavigation: NSViewRepresentable {
    let onMove: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onMove = onMove
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onMove: @MainActor (Int) -> Void
        private var monitor: Any?

        init(onMove: @escaping @MainActor (Int) -> Void) {
            self.onMove = onMove
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                guard !(event.window?.firstResponder is NSTextView) else { return event }

                let direction: Int
                switch event.specialKey {
                case .leftArrow, .upArrow:
                    direction = -1
                case .rightArrow, .downArrow:
                    direction = 1
                default:
                    return event
                }

                Task { @MainActor [weak self] in
                    self?.onMove(direction)
                }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

    }
}
