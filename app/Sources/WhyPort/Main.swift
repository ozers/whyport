import AppKit
import Combine
import SwiftUI

@main
enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let value = { (flag: String) in arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } }
            let options = Snapshot.Options(
                path: arguments[index + 1],
                port: value("--port").flatMap(Int.init),
                page: value("--page"),
                dark: arguments.contains("--dark"),
                demo: arguments.contains("--demo")
            )
            MainActor.assumeIsolated { Snapshot.render(options) }
            return
        }

        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences = Preferences.shared
    private lazy var store = PortStore(preferences: preferences)
    private let navigation = Navigation()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "point.3.filled.connected.trianglepath.dotted", accessibilityDescription: "WhyPort")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: ContentView.width, height: ContentView.height)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(store: store, preferences: preferences, navigation: navigation)
        )

        hotKey = HotKey { [weak self] in self?.togglePopover() }
        preferences.$hotKeyEnabled
            .sink { [weak self] enabled in
                if enabled { self?.hotKey?.register() } else { self?.hotKey?.unregister() }
            }
            .store(in: &subscriptions)

        store.$entries
            .combineLatest(preferences.$hidden, preferences.$memoryLimitMB, preferences.$showCount)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &subscriptions)
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let count = store.entries.filter { $0.kind.isProject && !preferences.hidden.contains($0.identity) }.count
        button.title = count > 0 && preferences.showCount ? " \(count)" : ""
        button.contentTintColor = store.overLimit.isEmpty ? nil : .systemRed
        button.toolTip = store.overLimit.isEmpty
            ? "WhyPort · \(count) project server\(count == 1 ? "" : "s")"
            : "WhyPort · \(store.overLimit.map(\.title).joined(separator: ", ")) over the memory limit"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open WhyPort", action: #selector(openPopover), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Rescan", action: #selector(rescan), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit WhyPort", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPopover() {
        if !popover.isShown { togglePopover() }
    }

    @objc private func rescan() {
        store.refresh()
    }

    @objc private func openSettings() {
        navigation.page = .settings
        openPopover()
    }

    func popoverDidShow(_ notification: Notification) {
        store.setVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        store.setVisible(false)
    }
}
