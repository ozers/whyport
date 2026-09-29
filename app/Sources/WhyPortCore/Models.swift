import Foundation

public enum Bind: Hashable, Sendable {
    case localhost
    case all
    case specific(String)

    static let loopback: Set<String> = ["127.0.0.1", "::1", "localhost"]
    static let wildcard: Set<String> = ["*", "0.0.0.0", "::", "::0"]

    public static func classify(_ hosts: [String]) -> Bind {
        if !hosts.isEmpty, hosts.allSatisfy({ loopback.contains($0) }) { return .localhost }
        if hosts.contains(where: { wildcard.contains($0) }) { return .all }
        var seen: [String] = []
        for host in hosts where !seen.contains(host) { seen.append(host) }
        return .specific(seen.joined(separator: ", "))
    }

    public var label: String {
        switch self {
        case .localhost: return "localhost only"
        case .all: return "all interfaces"
        case .specific(let hosts): return hosts
        }
    }
}

public struct PortBinding: Hashable, Sendable, Identifiable {
    public var id: Int { port }
    public var port: Int
    public var hosts: [String]
    public var containerPort: Int?

    public init(port: Int, hosts: [String], containerPort: Int? = nil) {
        self.port = port
        self.hosts = hosts
        self.containerPort = containerPort
    }

    public var bind: Bind { Bind.classify(hosts) }
}

public struct Project: Hashable, Sendable {
    public var name: String
    public var root: String
    public var branch: String?

    public init(name: String, root: String, branch: String?) {
        self.name = name
        self.root = root
        self.branch = branch
    }
}

public struct Container: Hashable, Sendable {
    public var id: String
    public var name: String
    public var image: String

    public init(id: String, name: String, image: String) {
        self.id = id
        self.name = name
        self.image = image
    }
}

public struct Connection: Hashable, Sendable, Identifiable {
    public var id: String { peer }
    public var peer: String
    public var pid: Int32?
    public var process: String?

    public init(peer: String, pid: Int32?, process: String?) {
        self.peer = peer
        self.pid = pid
        self.process = process
    }
}

public enum EntryKind: String, Sendable {
    case server
    case container
    case database
    case daemon
    case app
    case other

    public var isProject: Bool {
        self == .server || self == .container || self == .database
    }

    var order: Int {
        switch self {
        case .server: return 0
        case .container: return 1
        case .database: return 2
        case .other: return 3
        case .daemon: return 4
        case .app: return 5
        }
    }
}

public struct GroupMember: Hashable, Sendable {
    public var pid: Int32
    public var name: String
    public var command: String

    public init(pid: Int32, name: String, command: String) {
        self.pid = pid
        self.name = name
        self.command = command
    }
}

public struct PortEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var pid: Int32
    public var processName: String
    public var user: String
    public var command: String
    public var ppid: Int32?
    public var parentName: String?
    public var uptime: TimeInterval?
    /// Summed over the whole launch group, so `npm run dev` and its children count as one server.
    public var memoryKB: Int?
    public var cpu: Double?
    public var cwd: String?
    public var project: Project?
    public var container: Container?
    public var bindings: [PortBinding]
    public var connections: [Connection]
    public var role: String
    public var kind: EntryKind
    public var group: [GroupMember] = []

    public var ports: [Int] { bindings.map(\.port) }
    public var title: String { container?.name ?? project?.name ?? role }
    public var bind: Bind { Bind.classify(bindings.flatMap(\.hosts)) }
    public var why: String { Explain.why(self) }
    public var exposed: Bool { bind != .localhost }
    public var root: GroupMember? { group.first }
    public var launchedByWrapper: Bool { (root?.pid ?? pid) != pid }

    public var identity: String {
        if let container { return "container:\(container.name)" }
        if let project { return "project:\(project.root)|\(role)" }
        return "process:\(processName)|\(role)"
    }

    public var isIdle: Bool {
        kind == .server && connections.isEmpty && (cpu ?? 0) < 1 && (uptime ?? 0) > 30 * 60
    }
}
