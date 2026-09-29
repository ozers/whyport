import Foundation
import UserNotifications
import WhyPortCore

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let stopAction = "stop"
    static let category = "port"

    var onStop: ((String) -> Void)?
    private var authorized = false
    private var baseline: [String: PortEntry]?
    private var warnedMemory: Set<String> = []
    private var warnedExposed: Set<String> = []

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        let stop = UNNotificationAction(identifier: Self.stopAction, title: "Stop", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [stop], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func observe(_ entries: [PortEntry], preferences: Preferences) {
        let current = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        defer { baseline = current }
        let limitKB = preferences.memoryLimitMB * 1024

        for entry in entries where (entry.memoryKB ?? 0) < limitKB * 8 / 10 {
            warnedMemory.remove(entry.id)
        }
        guard let baseline else {
            warnedExposed = Set(entries.filter(\.exposed).map(\.id))
            return
        }

        let watched = entries.filter { $0.kind.isProject && !preferences.hidden.contains($0.identity) }
        for entry in watched {
            if preferences.notifyStartStop, baseline[entry.id] == nil {
                post(entry, title: "\(entry.title) is up", body: "Listening on \(ports(entry)).")
            }
            if preferences.notifyExposed, entry.exposed, !warnedExposed.contains(entry.id) {
                warnedExposed.insert(entry.id)
                let address = Network.lanAddress().map { " at \($0):\(entry.ports.first ?? 0)" } ?? ""
                post(entry, title: "\(entry.title) is reachable from your network", body: "Other devices can open it\(address).")
            }
            if preferences.notifyMemory, let memory = entry.memoryKB, memory > limitKB, !warnedMemory.contains(entry.id) {
                warnedMemory.insert(entry.id)
                post(entry, title: "\(entry.title) is using \(Explain.memory(memory))", body: "That is over your \(preferences.memoryLimitMB) MB limit.")
            }
        }
        if preferences.notifyStartStop {
            for (id, entry) in baseline where current[id] == nil && entry.kind.isProject && !preferences.hidden.contains(entry.identity) {
                post(nil, title: "\(entry.title) stopped", body: "\(ports(entry)) is free.")
            }
        }
    }

    private func ports(_ entry: PortEntry) -> String {
        entry.ports.map(String.init).joined(separator: ", ")
    }

    private func post(_ entry: PortEntry?, title: String, body: String) {
        guard authorized, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let entry {
            content.categoryIdentifier = Self.category
            content.userInfo = ["id": entry.id]
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.userInfo["id"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == Self.stopAction, let id { self.onStop?(id) }
            completionHandler()
        }
    }
}
