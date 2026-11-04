import AppKit
import SwiftUI

/// Open on mouse-up so the first click can activate the accessory app before
/// AppKit starts tracking the menu. A menu opened on mouse-down loses that click.
struct PanelMenuButton<Items: View>: NSViewRepresentable {
    let title: String
    let symbol: String
    @ViewBuilder let items: () -> Items

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.menuButton)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.setAccessibilityLabel(title)
        context.coordinator.items = items
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: () -> Items

        init(items: @escaping () -> Items) { self.items = items }

        @objc func open(_ button: NSButton) {
            let menu = NSHostingMenu(rootView: items())
            button.menu = menu
            defer { button.menu = nil }
            let y = button.isFlipped ? button.bounds.maxY + 3 : button.bounds.minY - 3
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: y), in: button)
        }
    }
}
