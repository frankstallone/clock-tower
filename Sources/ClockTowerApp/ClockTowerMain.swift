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
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var timer: Timer?
    private var titleSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if #available(macOS 27, *) {
            item.expandedInterfaceDelegate = self
        } else {
            item.button?.target = self
            item.button?.action = #selector(togglePanel)
        }
        item.button?.toolTip = "Clock Tower"
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        popover.behavior = .transient
        popover.delegate = self
        let panel = PanelView(model: model) { [weak self] in self?.showSettings() }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                guard let self, size.width > 0, size.height > 0, self.popover.contentSize != size else { return }
                self.popover.contentSize = size
            }
        let controller = NSHostingController(rootView: panel)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
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

    // Accessory apps need a main menu to route editing and window shortcuts.
    private func installMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Clock Tower")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clock Tower", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = appMenu
        menu.addItem(applicationItem)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Add City…", action: #selector(addCity), keyEquivalent: "n").target = self
        file.addItem(withTitle: "Close", action: #selector(closeWindow), keyEquivalent: "w").target = self
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        menu.addItem(fileItem)

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
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        window?.autorecalculatesKeyViewLoop = true
        window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    @objc private func addCity() {
        if !popover.isShown { showPanel() }
        model.preview = nil
        model.isAddingCity = true
    }

    @objc private func closeWindow() {
        if popover.isShown { popover.performClose(nil) } else { NSApp.keyWindow?.performClose(nil) }
    }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable]
            window.title = "Clock Tower Settings"
            window.isReleasedWhenClosed = false
            window.autorecalculatesKeyViewLoop = true
            window.center()
            window.setFrameAutosaveName("Clock Tower Settings")
            settingsWindow = window
        }
        model.refreshLogin()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshLogin()
    }

    func popoverDidShow(_ notification: Notification) {
        guard #available(macOS 27, *), outsideClickMonitor == nil else { return }
        // A click in the system menu bar doesn't activate another app, so
        // NSPopover's transient behavior alone doesn't dismiss it there.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        model.preview = nil
        model.isAddingCity = false
        if #available(macOS 27, *) { item.expandedInterfaceSession?.cancel() }
    }
}

@available(macOS 27, *)
extension AppDelegate: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        showPanel()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        popover.performClose(nil)
    }
}
