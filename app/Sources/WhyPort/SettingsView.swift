import SwiftUI
import WhyPortCore

struct SettingsView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var preferences: Preferences
    let back: () -> Void

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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("General") {
                        Toggle("Open at login", isOn: Binding(
                            get: { store.launchAtLogin },
                            set: { _ in store.toggleLaunchAtLogin() }
                        ))
                        Toggle("Open WhyPort with \(HotKey.label) from anywhere", isOn: $preferences.hotKeyEnabled)
                        picker("Editor", selection: $preferences.editorID, targets: LaunchTarget.editors)
                        picker("Terminal", selection: $preferences.terminalID, targets: LaunchTarget.terminals)
                    }

                    group("Notifications") {
                        Toggle("When a project server starts or stops", isOn: $preferences.notifyStartStop)
                        Toggle("When a port becomes reachable from the network", isOn: $preferences.notifyExposed)
                        Toggle("When memory goes over the limit", isOn: $preferences.notifyMemory)
                        HStack {
                            Text("Memory limit")
                            Spacer()
                            Text(verbatim: "\(preferences.memoryLimitMB) MB").monospacedDigit().foregroundStyle(.secondary)
                            Stepper("", value: $preferences.memoryLimitMB, in: 256...16384, step: 256).labelsHidden()
                        }
                    }

                    group("Hidden and pinned") {
                        HStack {
                            Text(verbatim: "\(preferences.hidden.count) hidden")
                            Spacer()
                            Button("Show all again") { preferences.hidden = [] }.disabled(preferences.hidden.isEmpty)
                        }
                        HStack {
                            Text(verbatim: "\(preferences.pinned.count) pinned")
                            Spacer()
                            Button("Unpin all") { preferences.pinned = [] }.disabled(preferences.pinned.isEmpty)
                        }
                        Text("Right-click a row to pin or hide it.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    group("About") {
                        HStack {
                            Text(verbatim: "WhyPort \(version) · MIT")
                            Spacer()
                            Button("Restart logs") { Actions.reveal(PortStore.logDirectory.path) }
                        }
                    }
                }
                .font(.system(size: 12))
                .padding(14)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    private func picker(_ title: String, selection: Binding<String>, targets: [LaunchTarget]) -> some View {
        let installed = targets.filter(\.isInstalled)
        return HStack {
            Text(title)
            Spacer()
            if installed.isEmpty {
                Text("None found").foregroundStyle(.secondary)
            } else {
                Picker(title, selection: selection) {
                    ForEach(installed) { target in Text(target.name).tag(target.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
