import SwiftUI
import WhyPortCore

struct SettingsView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var preferences: Preferences
    let back: () -> Void

    @State private var update: UpdateState = .idle

    static let repository = URL(string: "https://github.com/ozers/whyport")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    Label("All ports", systemImage: "chevron.left").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 70, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            Form {
                general
                list
                openIn
                notifications
                hiddenAndPinned
                about
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var general: some View {
        Section("General") {
            Toggle("Open at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { _ in store.toggleLaunchAtLogin() }
            ))
            Toggle(isOn: $preferences.hotKeyEnabled) {
                HStack(spacing: 6) {
                    Text("Global shortcut")
                    Keycaps(HotKey.label)
                }
            }
            Toggle("Show server count in the menu bar", isOn: $preferences.showCount)
            Toggle(isOn: $preferences.confirmServers) {
                Text("Ask before stopping project servers")
                Text("Databases, apps and containers always ask.")
            }
        }
    }

    private var list: some View {
        Section("List") {
            Toggle(isOn: $preferences.hideHighPorts) {
                Text("Hide temporary ports in Everything")
                Text("Ports 49152 and up are usually picked at random by the system or an app.")
            }
        }
    }

    private var openIn: some View {
        Section("Open in") {
            picker("Editor", selection: $preferences.editorID, targets: LaunchTarget.editors)
            picker("Terminal", selection: $preferences.terminalID, targets: LaunchTarget.terminals)
        }
    }

    private var notifications: some View {
        Section("Notifications") {
            Toggle("A project server starts or stops", isOn: $preferences.notifyStartStop)
            Toggle("A port becomes reachable from the network", isOn: $preferences.notifyExposed)
            Toggle("Memory goes over the limit", isOn: $preferences.notifyMemory)
            LabeledContent("Memory limit") {
                HStack(spacing: 6) {
                    Text(Explain.memory(preferences.memoryLimitMB * 1024))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Memory limit", value: $preferences.memoryLimitMB, in: 256...16384, step: 256)
                        .labelsHidden()
                }
            }
        }
    }

    private var hiddenAndPinned: some View {
        Section {
            if preferences.pinned.isEmpty && preferences.hidden.isEmpty {
                Text("Right-click a row to pin it to the top or hide it from Projects.")
                    .foregroundStyle(.secondary)
            }
            ForEach(preferences.pinned.sorted(), id: \.self) { identity in
                identityRow(identity, symbol: "pin.fill", action: "Unpin") { preferences.togglePinned(identity) }
            }
            ForEach(preferences.hidden.sorted(), id: \.self) { identity in
                identityRow(identity, symbol: "eye.slash", action: "Show") { preferences.toggleHidden(identity) }
            }
        } header: {
            Text("Pinned and hidden")
        }
    }

    private var about: some View {
        Section("About") {
            LabeledContent("Version") {
                HStack(spacing: 8) {
                    updateStatus
                    Text(verbatim: version).monospacedDigit()
                }
            }
            HStack {
                Button("Check for updates") { Task { await checkForUpdates() } }
                    .disabled(update == .checking)
                Spacer()
                Button("Restart logs") { Actions.reveal(PortStore.logDirectory.path) }
                    .help("Output of servers restarted from WhyPort")
            }
            HStack {
                Link("github.com/ozers/whyport", destination: Self.repository)
                Spacer()
                Button("Quit WhyPort") { NSApp.terminate(nil) }
            }
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch update {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .current:
            Text("Up to date").foregroundStyle(.secondary)
        case .available(let latest, let url):
            Link("\(latest) available", destination: url)
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary)
        }
    }

    private func identityRow(_ identity: String, symbol: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            Text(Preferences.label(for: identity)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action, action: perform).controlSize(.small)
        }
    }

    private func picker(_ title: String, selection: Binding<String>, targets: [LaunchTarget]) -> some View {
        let installed = targets.filter(\.isInstalled)
        return Group {
            if installed.isEmpty {
                LabeledContent(title) { Text("None found").foregroundStyle(.secondary) }
            } else {
                Picker(title, selection: selection) {
                    ForEach(installed) { target in Text(target.name).tag(target.id) }
                }
            }
        }
    }

    private func checkForUpdates() async {
        update = .checking
        let api = URL(string: "https://api.github.com/repos/ozers/whyport/releases/latest")!
        do {
            let (data, response) = try await URLSession.shared.data(from: api)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                update = .current
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let newer = latest.compare(version, options: .numeric) == .orderedDescending
            update = newer ? .available(latest, release.htmlURL) : .current
        } catch {
            update = .failed("Couldn't reach GitHub")
        }
    }
}

private enum UpdateState: Equatable {
    case idle, checking, current
    case available(String, URL)
    case failed(String)
}

private struct Release: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct Keycaps: View {
    let keys: [String]

    init(_ label: String) {
        keys = label.map(String.init)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .frame(minWidth: 16, minHeight: 16)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Palette.well))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
            }
        }
    }
}
