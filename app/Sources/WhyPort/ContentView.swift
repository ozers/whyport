import AppKit
import SwiftUI
import WhyPortCore

@MainActor
final class Navigation: ObservableObject {
    enum Page: Equatable {
        case list
        case detail(String)
        case settings
    }

    @Published var page: Page = .list
    @Published var selecting = false
    @Published var checked: Set<String> = []
    @Published var exposedOnly = false
}

struct ContentView: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 580

    @ObservedObject var store: PortStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation: Navigation
    @AppStorage("showEverything") private var showEverything = false
    @State private var query = ""
    @State private var confirmingBulk = false

    var body: some View {
        VStack(spacing: 0) {
            switch navigation.page {
            case .detail(let id):
                if let entry = store.entries.first(where: { $0.id == id }) {
                    DetailView(store: store, preferences: preferences, entry: entry) { navigation.page = .list }
                } else {
                    list
                }
            case .settings:
                SettingsView(store: store, preferences: preferences) { navigation.page = .list }
            case .list:
                list
            }
            if let message = store.message {
                MessageBar(text: message) { store.message = nil }
            }
        }
        .frame(width: Self.width, height: Self.height)
    }

    private var scoped: [PortEntry] {
        guard showEverything else {
            return store.entries.filter { $0.kind.isProject && !preferences.hidden.contains($0.identity) }
        }
        guard preferences.hideHighPorts else { return store.entries }
        return store.entries.filter { $0.kind.isProject || $0.ports.contains { $0 < 49152 } }
    }

    private var visible: [PortEntry] {
        var base = scoped
        if navigation.exposedOnly { base = base.filter(\.exposed) }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            base = base.filter { entry in
                entry.ports.contains { String($0).hasPrefix(needle) }
                    || entry.title.lowercased().contains(needle)
                    || entry.role.lowercased().contains(needle)
                    || entry.processName.lowercased().contains(needle)
                    || (entry.project?.branch?.lowercased().contains(needle) ?? false)
            }
        }
        let pinned = base.filter { preferences.pinned.contains($0.identity) }
        return pinned + base.filter { !preferences.pinned.contains($0.identity) }
    }

    private var exposedCount: Int { scoped.filter(\.exposed).count }
    private var idle: [PortEntry] { visible.filter(\.isIdle) }
    private var checkedEntries: [PortEntry] { store.entries.filter { navigation.checked.contains($0.id) } }

    private var list: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visible.isEmpty {
                EmptyState(filtered: !showEverything && !store.entries.isEmpty, searching: !query.isEmpty || navigation.exposedOnly) {
                    showEverything = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visible) { entry in
                            PortRow(
                                store: store,
                                preferences: preferences,
                                entry: entry,
                                selecting: navigation.selecting,
                                checked: navigation.checked.contains(entry.id)
                            ) {
                                if navigation.selecting {
                                    if navigation.checked.contains(entry.id) {
                                        navigation.checked.remove(entry.id)
                                    } else {
                                        navigation.checked.insert(entry.id)
                                    }
                                } else {
                                    navigation.page = .detail(entry.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            Divider()
            if navigation.selecting { bulkFooter } else { footer }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("whyport").font(.system(size: 15, weight: .semibold))
                Text(countLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(navigation.selecting ? "Done" : "Select") {
                    navigation.selecting.toggle()
                    navigation.checked = []
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                Picker("", selection: $showEverything) {
                    Text("Projects").tag(false)
                    Text("Everything").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Port, project, branch or process", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                if exposedCount > 0 || navigation.exposedOnly {
                    Button { navigation.exposedOnly.toggle() } label: {
                        Label("\(exposedCount)", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.exposure.opacity(navigation.exposedOnly ? 0.3 : 0.12)))
                            .foregroundStyle(Palette.exposure)
                    }
                    .buttonStyle(.plain)
                    .help("\(exposedCount) reachable from your network. Click to show only those.")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var countLabel: String {
        let ports = visible.reduce(0) { $0 + $1.ports.count }
        return "\(ports) port\(ports == 1 ? "" : "s")"
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let scannedAt = store.scannedAt {
                Text(scannedAt, style: .time).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Rescan")
            Button { navigation.page = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var bulkFooter: some View {
        HStack(spacing: 10) {
            Button("Select idle (\(idle.count))") {
                navigation.checked = Set(idle.map(\.id))
            }
            .disabled(idle.isEmpty)
            .help("Project servers with no connections, no CPU use and more than 30 minutes of uptime")
            Spacer()
            Button("Stop \(navigation.checked.count)", role: .destructive) { confirmingBulk = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.danger)
                .disabled(navigation.checked.isEmpty)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .confirmationDialog("Stop \(navigation.checked.count) server\(navigation.checked.count == 1 ? "" : "s")?", isPresented: $confirmingBulk) {
            Button("Stop", role: .destructive) {
                store.stop(checkedEntries)
                navigation.checked = []
                navigation.selecting = false
            }
        } message: {
            Text(checkedEntries.map(\.title).joined(separator: ", "))
        }
    }
}

struct PortRow: View {
    @ObservedObject var store: PortStore
    @ObservedObject var preferences: Preferences
    let entry: PortEntry
    let selecting: Bool
    let checked: Bool
    let open: () -> Void
    @State private var hovering = false
    @State private var confirming = false

    private var hidden: Bool { preferences.hidden.contains(entry.identity) }
    private var pinned: Bool { preferences.pinned.contains(entry.identity) }
    private var overLimit: Bool { (entry.memoryKB ?? 0) > preferences.memoryLimitMB * 1024 }

    var body: some View {
        HStack(spacing: 10) {
            if selecting {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(checked ? Color.accentColor : .secondary)
            }
            PortBadge(port: entry.ports.first ?? 0, extra: entry.ports.count - 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if entry.exposed {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.exposure)
                            .help("Reachable from your network")
                    }
                    if !entry.connections.isEmpty {
                        Circle().fill(Palette.live).frame(width: 6, height: 6)
                            .help("\(entry.connections.count) open connection\(entry.connections.count == 1 ? "" : "s")")
                    }
                }
                HStack(spacing: 0) {
                    Text(Explain.summary(entry))
                    if let memory = entry.memoryKB, memory > 0 {
                        Text(" · ")
                        Text(Explain.memory(memory))
                            .foregroundStyle(overLimit ? Palette.memory : .secondary)
                            .fontWeight(overLimit ? .semibold : .regular)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !selecting && (hovering || store.busy.contains(entry.id)) {
                actions
            } else {
                Text(Explain.uptime(entry.uptime))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(hidden ? 0.5 : 1)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering || checked ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu { menu }
        .confirmationDialog(StopCopy.title(entry), isPresented: $confirming) {
            Button(StopCopy.button(entry), role: .destructive) { store.stop(entry) }
        } message: {
            Text(StopCopy.message(entry))
        }
    }

    @ViewBuilder private var menu: some View {
        Button(pinned ? "Unpin" : "Pin to top") { preferences.togglePinned(entry.identity) }
        Button(hidden ? "Unhide" : "Hide \(entry.title)") { preferences.toggleHidden(entry.identity) }
        Divider()
        Button("Open in browser") { Actions.openInBrowser(entry) }
        Button("Copy URL") { Actions.copy("http://localhost:\(entry.ports.first ?? 0)") }
        if let folder = Actions.folder(entry) {
            if let editor = preferences.editor {
                Button("Open in \(editor.name)") { editor.open(folder) }
            }
            if let terminal = preferences.terminal {
                Button("Open in \(terminal.name)") { terminal.open(folder) }
            }
        }
        Divider()
        Button("Restart") { store.restart(entry) }
        Button(StopCopy.button(entry)) { confirming = true }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if store.busy.contains(entry.id) {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "safari", help: "Open localhost:\(entry.ports.first ?? 0)") {
                    Actions.openInBrowser(entry)
                }
                IconButton(symbol: "arrow.clockwise", help: "Restart") { store.restart(entry) }
                IconButton(symbol: "stop.circle", help: StopCopy.button(entry), tint: Palette.danger) {
                    if StopCopy.needsConfirmation(entry, preferences) { confirming = true } else { store.stop(entry) }
                }
            }
        }
    }
}

struct PortBadge: View {
    let port: Int
    var extra = 0

    var body: some View {
        VStack(spacing: 1) {
            Text(String(port))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.port(port))
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 34)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.port(port).opacity(0.12)))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct EmptyState: View {
    let filtered: Bool
    let searching: Bool
    let showEverything: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(searching ? "No match" : "No project servers are running")
                .font(.system(size: 13, weight: .medium))
            if filtered && !searching {
                Text("Apps, build daemons and hidden servers are left out.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Show everything", action: showEverything)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct MessageBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Palette.danger.opacity(0.1))
    }
}

enum StopCopy {
    @MainActor
    static func needsConfirmation(_ entry: PortEntry, _ preferences: Preferences) -> Bool {
        entry.kind != .server || preferences.confirmServers
    }

    static func button(_ entry: PortEntry) -> String {
        entry.container == nil ? "Stop" : "Stop container"
    }

    static func title(_ entry: PortEntry) -> String {
        "Stop \(entry.title)?"
    }

    static func message(_ entry: PortEntry) -> String {
        if let container = entry.container {
            return "Runs docker stop \(container.name). Its data volumes are kept."
        }
        switch entry.kind {
        case .database: return "Anything connected to this database will lose its connection."
        case .app: return "This quits \(entry.processName) itself, not just the port."
        case .daemon: return "The build tool starts a new one on the next build."
        default: return "Sends a stop request to pid \(entry.pid)."
        }
    }
}

enum Actions {
    static func openInBrowser(_ entry: PortEntry) {
        guard let port = entry.ports.first, let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func folder(_ entry: PortEntry) -> String? {
        entry.project?.root ?? entry.cwd
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
