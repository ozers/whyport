import AppKit
import Foundation

struct LaunchTarget: Identifiable, Hashable {
    let id: String
    let name: String

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    var isInstalled: Bool { url != nil }

    static let editors = [
        LaunchTarget(id: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        LaunchTarget(id: "com.microsoft.VSCode", name: "VS Code"),
        LaunchTarget(id: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        LaunchTarget(id: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        LaunchTarget(id: "dev.zed.Zed", name: "Zed"),
        LaunchTarget(id: "com.sublimetext.4", name: "Sublime Text"),
        LaunchTarget(id: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    static let terminals = [
        LaunchTarget(id: "com.apple.Terminal", name: "Terminal"),
        LaunchTarget(id: "com.googlecode.iterm2", name: "iTerm"),
        LaunchTarget(id: "com.mitchellh.ghostty", name: "Ghostty"),
        LaunchTarget(id: "dev.warp.Warp-Stable", name: "Warp"),
        LaunchTarget(id: "net.kovidgoyal.kitty", name: "kitty"),
    ]

    func open(_ folder: String) {
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: url, configuration: configuration)
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var editorID: String { didSet { defaults.set(editorID, forKey: "editor") } }
    @Published var terminalID: String { didSet { defaults.set(terminalID, forKey: "terminal") } }
    @Published var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKey") } }
    @Published var notifyStartStop: Bool { didSet { defaults.set(notifyStartStop, forKey: "notifyStartStop") } }
    @Published var notifyExposed: Bool { didSet { defaults.set(notifyExposed, forKey: "notifyExposed") } }
    @Published var notifyMemory: Bool { didSet { defaults.set(notifyMemory, forKey: "notifyMemory") } }
    @Published var memoryLimitMB: Int { didSet { defaults.set(memoryLimitMB, forKey: "memoryLimitMB") } }
    @Published var hidden: Set<String> { didSet { defaults.set(Array(hidden), forKey: "hidden") } }
    @Published var pinned: Set<String> { didSet { defaults.set(Array(pinned), forKey: "pinned") } }
    @Published var showCount: Bool { didSet { defaults.set(showCount, forKey: "showCount") } }
    @Published var confirmServers: Bool { didSet { defaults.set(confirmServers, forKey: "confirmServers") } }
    @Published var hideHighPorts: Bool { didSet { defaults.set(hideHighPorts, forKey: "hideHighPorts") } }

    init() {
        defaults.register(defaults: [
            "hotKey": true,
            "notifyStartStop": false,
            "notifyExposed": true,
            "notifyMemory": true,
            "memoryLimitMB": 2048,
            "showCount": true,
            "confirmServers": false,
            "hideHighPorts": true,
        ])
        showCount = defaults.bool(forKey: "showCount")
        confirmServers = defaults.bool(forKey: "confirmServers")
        hideHighPorts = defaults.bool(forKey: "hideHighPorts")
        editorID = defaults.string(forKey: "editor")
            ?? LaunchTarget.editors.first(where: \.isInstalled)?.id
            ?? LaunchTarget.editors[0].id
        terminalID = defaults.string(forKey: "terminal") ?? LaunchTarget.terminals[0].id
        hotKeyEnabled = defaults.bool(forKey: "hotKey")
        notifyStartStop = defaults.bool(forKey: "notifyStartStop")
        notifyExposed = defaults.bool(forKey: "notifyExposed")
        notifyMemory = defaults.bool(forKey: "notifyMemory")
        memoryLimitMB = defaults.integer(forKey: "memoryLimitMB")
        hidden = Set(defaults.stringArray(forKey: "hidden") ?? [])
        pinned = Set(defaults.stringArray(forKey: "pinned") ?? [])
    }

    var editor: LaunchTarget? { LaunchTarget.editors.first { $0.id == editorID && $0.isInstalled } }
    var terminal: LaunchTarget? { LaunchTarget.terminals.first { $0.id == terminalID && $0.isInstalled } }

    func toggleHidden(_ identity: String) {
        if hidden.contains(identity) { hidden.remove(identity) } else { hidden.insert(identity) }
    }

    func togglePinned(_ identity: String) {
        if pinned.contains(identity) { pinned.remove(identity) } else { pinned.insert(identity) }
    }

    static func label(for identity: String) -> String {
        guard let colon = identity.firstIndex(of: ":") else { return identity }
        let kind = identity[..<colon]
        let rest = identity[identity.index(after: colon)...]
        let parts = rest.split(separator: "|", maxSplits: 1).map(String.init)
        switch kind {
        case "container": return String(rest)
        case "project":
            let name = ((parts.first ?? "") as NSString).lastPathComponent
            return parts.count > 1 ? "\(name) · \(parts[1])" : name
        default:
            return parts.last ?? String(rest)
        }
    }
}
