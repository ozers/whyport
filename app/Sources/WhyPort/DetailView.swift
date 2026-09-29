import Charts
import SwiftUI
import WhyPortCore

struct DetailView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var preferences: Preferences
    let entry: PortEntry
    let back: () -> Void
    @State private var confirming = false
    @State private var showFullCommand = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    Label("All ports", systemImage: "chevron.left").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button { preferences.togglePinned(entry.identity) } label: {
                    Image(systemName: preferences.pinned.contains(entry.identity) ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(preferences.pinned.contains(entry.identity) ? "Unpin" : "Pin to top")
                Button { preferences.toggleHidden(entry.identity) } label: {
                    Image(systemName: preferences.hidden.contains(entry.identity) ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(preferences.hidden.contains(entry.identity) ? "Unhide" : "Hide from Projects")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    Text(entry.why)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.09)))
                    if entry.exposed { exposure }
                    usage
                    facts
                    if entry.group.count > 1 { processes }
                    connections
                }
                .padding(14)
            }

            Divider()
            actionBar
        }
        .confirmationDialog(StopCopy.title(entry), isPresented: $confirming) {
            Button(StopCopy.button(entry), role: .destructive) { store.stop(entry) }
        } message: {
            Text(StopCopy.message(entry))
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            PortBadge(port: entry.ports.first ?? 0, extra: entry.ports.count - 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(Explain.summary(entry)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var exposure: some View {
        let port = entry.ports.first ?? 0
        let address = Network.lanAddress().map { "http://\($0):\(port)" }
        let fix = entry.container == nil
            ? "If only this Mac needs it, bind it to 127.0.0.1."
            : "Publish it as 127.0.0.1:\(port):\(entry.bindings.first?.containerPort ?? port) to keep it local."
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Reachable from your network").font(.system(size: 12, weight: .semibold))
                Text(address.map { "Other devices on this network can open \($0). " } ?? "Other devices on this network can connect. ")
                    .font(.system(size: 12))
                    + Text(fix).font(.system(size: 12)).foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    @ViewBuilder private var usage: some View {
        let samples = store.history[entry.id] ?? []
        if entry.memoryKB != nil {
            HStack(spacing: 12) {
                UsageChart(
                    title: "Memory",
                    value: Explain.memory(entry.memoryKB),
                    samples: samples,
                    metric: \.memoryMB,
                    color: (entry.memoryKB ?? 0) > preferences.memoryLimitMB * 1024 ? .orange : .blue,
                    limit: Double(preferences.memoryLimitMB)
                )
                UsageChart(
                    title: "CPU",
                    value: String(format: "%.1f%%", entry.cpu ?? 0),
                    samples: samples,
                    metric: \.cpu,
                    color: .green,
                    limit: nil
                )
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 7) {
            Fact(label: "Ports") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.bindings) { binding in
                        HStack(spacing: 6) {
                            Text(verbatim: binding.containerPort.map { "\(binding.port) → \($0)" } ?? String(binding.port))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(PortColor.color(for: binding.port))
                            Text(binding.bind.label).foregroundStyle(binding.bind == .localhost ? Color.secondary : .orange)
                        }
                    }
                }
            }
            if let container = entry.container {
                Fact(label: "Image", value: container.image)
                Fact(label: "Container", value: String(container.id.prefix(12)), mono: true)
            } else {
                Fact(label: "Process", value: "\(entry.processName) · pid \(entry.pid) · \(entry.user)")
            }
            if let uptime = entry.uptime, entry.container == nil {
                Fact(label: "Running", value: Explain.uptime(uptime))
            }
            if let project = entry.project {
                Fact(label: "Project", value: project.name + (project.branch.map { " · \($0)" } ?? ""))
            }
            if let cwd = entry.cwd {
                Fact(label: "Folder") {
                    Button { Actions.reveal(cwd) } label: {
                        Text(Explain.abbreviate(cwd)).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .help("Show in Finder")
                }
            }
            if entry.launchedByWrapper, let root = entry.root {
                Fact(label: "Started with", value: Explain.prettyCommand(root.command, limit: 80), mono: true)
            } else if let parent = entry.parentName, entry.container == nil {
                Fact(label: "Parent", value: parent)
            } else if entry.ppid == 1, entry.container == nil {
                Fact(label: "Parent", value: "launchd")
            }
            if entry.container == nil {
                Fact(label: "Command") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.command)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(showFullCommand ? nil : 3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            if entry.command.count > 160 {
                                Button(showFullCommand ? "Less" : "More") { showFullCommand.toggle() }
                            }
                            Button("Copy") { Actions.copy(entry.command) }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .font(.system(size: 12))
    }

    private var processes: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Processes · \(entry.group.count)")
            ForEach(entry.group, id: \.pid) { member in
                HStack(spacing: 8) {
                    Text(member.name).font(.system(size: 12)).frame(width: 70, alignment: .leading).lineLimit(1)
                    Text(verbatim: "\(member.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text(Explain.prettyCommand(member.command, limit: 48))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if member.pid == entry.pid {
                        Text("listening").font(.system(size: 10)).foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Connections")
            if entry.connections.isEmpty {
                Text("None right now").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(entry.connections) { connection in
                    HStack {
                        Text(connection.process ?? "remote peer").font(.system(size: 12))
                        if let pid = connection.pid {
                            Text(verbatim: "pid \(pid)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(connection.peer)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "safari", help: "Open localhost:\(entry.ports.first ?? 0)") { Actions.openInBrowser(entry) }
            if let folder = Actions.folder(entry) {
                if let editor = preferences.editor {
                    IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in \(editor.name)") { editor.open(folder) }
                }
                if let terminal = preferences.terminal {
                    IconButton(symbol: "terminal", help: "Open in \(terminal.name)") { terminal.open(folder) }
                }
                IconButton(symbol: "folder", help: "Show in Finder") { Actions.reveal(folder) }
            }
            if let log = store.logs[entry.identity] {
                IconButton(symbol: "doc.text", help: "Show restart log") { Actions.openFile(log) }
            }
            Spacer()
            if store.busy.contains(entry.id) {
                ProgressView().controlSize(.small)
            } else if store.stuck.contains(entry.id) {
                Button("Force quit", role: .destructive) { store.stop(entry, force: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("Restart") { store.restart(entry) }
                    .help(restartHelp)
                Button(StopCopy.button(entry), role: .destructive) {
                    if StopCopy.needsConfirmation(entry) { confirming = true } else { store.stop(entry) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var restartHelp: String {
        if let container = entry.container { return "docker restart \(container.name)" }
        let command = entry.root?.command ?? entry.command
        return "Stops it, then runs \(Explain.prettyCommand(command, limit: 80)) again in the same folder"
    }
}

struct UsageChart: View {
    let title: String
    let value: String
    let samples: [Sample]
    let metric: KeyPath<Sample, Double>
    let color: Color
    let limit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            Group {
                if samples.count < 2 {
                    Text("Collecting…").font(.system(size: 11)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let peak = samples.map { $0[keyPath: metric] }.max() ?? 0
                    Chart {
                        ForEach(samples) { sample in
                            AreaMark(x: .value("Time", sample.time), y: .value(title, sample[keyPath: metric]))
                                .foregroundStyle(color.opacity(0.18))
                            LineMark(x: .value("Time", sample.time), y: .value(title, sample[keyPath: metric]))
                                .foregroundStyle(color)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        if let limit, peak > limit * 0.6 {
                            RuleMark(y: .value("Limit", limit))
                                .foregroundStyle(.orange.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...max(peak * 1.2, limit.map { peak > $0 * 0.6 ? $0 * 1.1 : 0 } ?? 0, 1))
                }
            }
            .frame(height: 44)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct Fact<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

extension Fact where Content == AnyView {
    init(label: String, value: String, mono: Bool = false) {
        self.init(label: label) {
            AnyView(
                Text(value)
                    .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(2)
            )
        }
    }
}
