import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    struct Options {
        var path: String
        var port: Int?
        var page: String?
        var dark: Bool
    }

    static func render(_ options: Options) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let store = PortStore(autostart: false)
        store.scanNow()
        if options.port != nil || options.page == "charts" {
            for _ in 0..<5 {
                RunLoop.main.run(until: Date().addingTimeInterval(1))
                store.scanNow()
            }
        }

        let navigation = Navigation()
        if let port = options.port, let entry = store.entries.first(where: { $0.ports.contains(port) }) {
            navigation.page = .detail(entry.id)
        }
        switch options.page {
        case "settings": navigation.page = .settings
        case "select":
            navigation.selecting = true
            navigation.checked = Set(store.entries.filter(\.isIdle).map(\.id))
        case "exposed": navigation.exposedOnly = true
        default: break
        }

        let view = ContentView(store: store, preferences: .shared, navigation: navigation)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: ContentView.width, height: ContentView.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try data.write(to: URL(fileURLWithPath: options.path))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
