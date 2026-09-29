import Foundation
import ServiceManagement
import WhyPortCore

struct Sample: Identifiable, Hashable {
    var id: Date { time }
    let time: Date
    let memoryMB: Double
    let cpu: Double
}

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var scannedAt: Date?
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var stuck: Set<String> = []
    @Published private(set) var history: [String: [Sample]] = [:]
    @Published private(set) var logs: [String: String] = [:]
    @Published var message: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let preferences: Preferences
    let notifier = Notifier()
    private let scanner = PortScanner()
    private var scanning = false
    private var timer: Timer?
    private var visible = false

    static let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WhyPort", isDirectory: true)

    init(preferences: Preferences? = nil, autostart: Bool = true) {
        self.preferences = preferences ?? .shared
        guard autostart else { return }
        notifier.onStop = { [weak self] id in
            guard let self, let entry = self.entries.first(where: { $0.id == id }) else { return }
            self.stop(entry)
        }
        notifier.start()
        refresh()
        schedule()
    }

    var overLimit: [PortEntry] {
        let limit = preferences.memoryLimitMB * 1024
        return entries.filter { ($0.memoryKB ?? 0) > limit }
    }

    func setVisible(_ value: Bool) {
        visible = value
        if value { refresh() }
        schedule()
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let scanner = scanner
        Task.detached(priority: .utility) {
            let result = scanner.scan()
            await MainActor.run { self.apply(result) }
        }
    }

    func scanNow() {
        apply(scanner.scan())
    }

    private func apply(_ result: [PortEntry]) {
        let now = Date()
        entries = result
        scannedAt = now
        scanning = false
        let ids = Set(result.map(\.id))
        stuck = stuck.intersection(ids)

        var next: [String: [Sample]] = [:]
        let cutoff = now.addingTimeInterval(-600)
        for entry in result {
            guard let memory = entry.memoryKB else { continue }
            var samples = (history[entry.id] ?? []).filter { $0.time > cutoff }
            samples.append(Sample(time: now, memoryMB: Double(memory) / 1024, cpu: entry.cpu ?? 0))
            next[entry.id] = samples
        }
        history = next
        notifier.observe(result, preferences: preferences)
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = visible ? 2 : 10
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop(_ entry: PortEntry, force: Bool = false) {
        guard !busy.contains(entry.id) else { return }
        busy.insert(entry.id)
        message = nil
        Task.detached(priority: .userInitiated) {
            let outcome = Stopper.stop(entry, force: force)
            await MainActor.run { self.finish(entry, outcome) }
        }
    }

    func stop(_ list: [PortEntry]) {
        for entry in list { stop(entry) }
    }

    private func finish(_ entry: PortEntry, _ outcome: StopOutcome) {
        busy.remove(entry.id)
        switch outcome {
        case .stopped:
            stuck.remove(entry.id)
            entries.removeAll { $0.id == entry.id }
        case .stillRunning:
            stuck.insert(entry.id)
            message = "\(entry.title) ignored the stop request. Force quit ends it immediately."
        case .failed(let reason):
            message = reason
        }
        scanning = false
        refresh()
    }

    func restart(_ entry: PortEntry) {
        guard !busy.contains(entry.id) else { return }
        busy.insert(entry.id)
        message = nil
        let directory = Self.logDirectory
        Task.detached(priority: .userInitiated) {
            let outcome = Stopper.restart(entry, logDirectory: directory)
            await MainActor.run {
                self.busy.remove(entry.id)
                switch outcome {
                case .restarted(let log):
                    if let log { self.logs[entry.identity] = log }
                case .failed(let reason):
                    self.message = reason
                }
                self.scanning = false
                self.refresh()
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { self.refresh() }
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            message = "Open at login needs WhyPort in Applications. \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
