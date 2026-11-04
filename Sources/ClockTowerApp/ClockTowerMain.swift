import AppKit
import ClockTowerCore
import Combine
import SwiftUI

@main
@MainActor
enum ClockTowerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var item: NSStatusItem!
    private var timer: Timer?
    private var titleSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "Clock Tower"
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        titleSubscription = model.$settings.combineLatest(model.$now).sink { [weak self] settings, now in
            guard let button = self?.item.button else { return }
            let title = ClockTime.menuTitle(settings, at: now)
            button.title = title
            button.image = settings.clocks.contains(where: \.isPinned) ? nil
                : NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            button.imagePosition = button.image == nil ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
            button.setAccessibilityLabel(title.isEmpty ? "Clock Tower" : "Clock Tower, " + title)
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resync),
                                                              name: name, object: nil)
        }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(resync), name: name, object: nil)
        }
        resync()
    }

    // Route standard shortcuts to the field editor in this accessory app.
    private func installEditMenu() {
        let menu = NSMenu()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    @objc private func resync() {
        timer?.invalidate()
        let now = Date()
        model.now = now
        let next = Timer(fireAt: ClockTime.nextMinute(after: now), interval: 0,
                         target: self, selector: #selector(resync), userInfo: nil, repeats: false)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    private func showPanel() {
        guard let button = item?.button else { return }
        resync()
        model.refreshLogin()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func popoverDidClose(_ notification: Notification) { model.preview = nil }
}
