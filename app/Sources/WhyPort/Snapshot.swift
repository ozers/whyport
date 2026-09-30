import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    struct Options {
        var path: String
        var port: Int?
        var page: String?
        var dark: Bool
        var demo: Bool
    }

    static func render(_ options: Options) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let store = PortStore(autostart: false)
        if options.demo {
            store.show(Demo.entries, history: Demo.history)
        } else {
            store.scanNow()
        }
        if !options.demo, options.port != nil || options.page == "charts" {
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

        let size: CGSize
        switch options.page {
        case "settings-full": size = CGSize(width: ContentView.width, height: 1250)
        case "social": size = CGSize(width: 1280, height: 640)
        default: size = CGSize(width: ContentView.width, height: ContentView.height)
        }
        let view = Group {
            switch options.page {
            case "settings-full":
                SettingsView(store: store, preferences: .shared, back: {})
            case "social":
                SocialPreview(content: ContentView(store: store, preferences: .shared, navigation: navigation))
            default:
                ContentView(store: store, preferences: .shared, navigation: navigation)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.controlActiveState, .key)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
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

private struct SocialPreview<Content: View>: View {
    let content: Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Palette.port(3000))
                Text("WhyPort").font(.system(size: 64, weight: .bold))
                Text("See why a port is open,\nwho is using it,\nand stop it in one click.")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                Text("macOS menu bar app · open source")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(.leading, 80)
            .frame(maxWidth: .infinity, alignment: .leading)

            content
                .frame(width: ContentView.width, height: ContentView.height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .offset(y: 70)
                .padding(.trailing, 90)
        }
        .frame(width: 1280, height: 640)
        .clipped()
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Palette.port(3000).opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
