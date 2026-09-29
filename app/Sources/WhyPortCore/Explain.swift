import Foundation

public enum Explain {
    public static func summary(_ entry: PortEntry) -> String {
        var parts: [String] = []
        if let container = entry.container {
            parts.append(container.image)
        } else {
            parts.append(entry.role)
            if let branch = entry.project?.branch { parts.append(branch) }
        }
        return parts.joined(separator: " · ")
    }

    public static func why(_ entry: PortEntry) -> String {
        var sentences: [String] = []
        let bind: String
        switch entry.bind {
        case .localhost: bind = "only on localhost"
        case .all: bind = "on all interfaces"
        case .specific(let hosts): bind = "on \(hosts)"
        }

        if let container = entry.container {
            let mappings = entry.bindings.map { binding in
                binding.containerPort.map { "\(binding.port) → \($0)" } ?? String(binding.port)
            }.joined(separator: ", ")
            sentences.append("Docker container \(container.name) (\(container.image)) publishes \(mappings) \(bind).")
            sentences.append("Stopping it runs docker stop; the image and volumes stay.")
        } else {
            let place: String
            if let project = entry.project {
                place = "\(project.name)\(project.branch.map { " on \($0)" } ?? "")"
            } else if let cwd = entry.cwd {
                place = abbreviate(cwd)
            } else {
                place = "an unknown folder"
            }
            let parts = entry.role.components(separatedBy: " · ")
            let subject = parts.count == 2 ? "\(parts[1]) (\(parts[0]))" : entry.role
            sentences.append("\(subject) is listening \(bind) from \(place).")
            if entry.launchedByWrapper, let root = entry.root {
                sentences.append("It was launched with \(prettyCommand(root.command)).")
            } else if let ppid = entry.ppid, ppid > 1, let parent = entry.parentName {
                sentences.append("Started by \(parent).")
            } else if entry.ppid == 1 {
                sentences.append("Its parent is launchd, so no terminal owns it anymore.")
            }
            if entry.group.count > 1 {
                sentences.append("Stop ends all \(entry.group.count) processes in that group.")
            }
            if case .daemon = entry.kind {
                sentences.append("Build tools start these on their own and reuse them between builds.")
            }
        }

        if entry.connections.isEmpty {
            sentences.append("Nothing is connected right now.")
        } else {
            var names: [String] = []
            for connection in entry.connections {
                let name = connection.process ?? "a remote peer"
                if !names.contains(name) { names.append(name) }
            }
            let shown = names.prefix(3).joined(separator: ", ")
            let rest = names.count > 3 ? " and \(names.count - 3) more" : ""
            let count = entry.connections.count
            sentences.append("\(count) open connection\(count == 1 ? "" : "s") from \(shown)\(rest).")
        }
        return sentences.joined(separator: " ")
    }

    public static func prettyCommand(_ command: String, limit: Int = 60) -> String {
        var tokens = command.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return command }
        let first = (tokens[0] as NSString).lastPathComponent
        if ["node", "bun"].contains(first), tokens.count > 1,
           ProcessTree.wrapperScripts.contains(where: { tokens[1].contains($0) }) {
            var script = ((tokens[1] as NSString).lastPathComponent as NSString).deletingPathExtension
            if script == "npm-cli" { script = "npm" }
            if !script.isEmpty { tokens = [script] + tokens.dropFirst(2) }
        } else {
            tokens[0] = first
        }
        let joined = tokens.joined(separator: " ")
        return joined.count > limit ? String(joined.prefix(limit - 1)) + "…" : joined
    }

    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func uptime(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    public static func memory(_ kilobytes: Int?) -> String {
        guard let kilobytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(kilobytes) * 1024, countStyle: .memory)
    }
}
