import Foundation
import WhyPortCore

/// Made-up ports for README screenshots, so a snapshot never shows the real machine.
enum Demo {
    private static let home = NSHomeDirectory() + "/Projects"
    private static let npm = "node /opt/homebrew/lib/node_modules/npm/bin/npm-cli.js run dev"

    private static func project(_ name: String, _ branch: String) -> Project {
        Project(name: name, root: "\(home)/\(name)", branch: branch)
    }

    static let entries: [PortEntry] = [
        PortEntry(
            id: "demo-3000", pid: 48213, processName: "node", user: "dev",
            command: "node node_modules/.bin/next dev",
            ppid: 48190, uptime: 2 * 3600 + 14 * 60, memoryKB: 412_000, cpu: 3.2,
            cwd: "\(home)/storefront", project: project("storefront", "main"),
            bindings: [PortBinding(port: 3000, hosts: ["127.0.0.1"])],
            connections: [
                Connection(peer: "127.0.0.1:52011", pid: 611, process: "Safari"),
                Connection(peer: "127.0.0.1:52014", pid: 611, process: "Safari"),
            ],
            role: "Next.js", kind: .server,
            group: [
                GroupMember(pid: 48190, name: "npm", command: npm),
                GroupMember(pid: 48201, name: "sh", command: "sh -c next dev"),
                GroupMember(pid: 48213, name: "node", command: "node node_modules/.bin/next dev"),
            ]
        ),
        PortEntry(
            id: "demo-8080", pid: 50377, processName: "api", user: "dev",
            command: "/var/folders/x1/T/go-build/b001/exe/api",
            ppid: 50310, uptime: 5 * 3600 + 3 * 60, memoryKB: 96_000, cpu: 0.4,
            cwd: "\(home)/orders-api", project: project("orders-api", "feature/checkout"),
            bindings: [PortBinding(port: 8080, hosts: ["*"])],
            connections: [Connection(peer: "127.0.0.1:50122", pid: 48213, process: "node")],
            role: "go · cmd/api", kind: .server,
            group: [
                GroupMember(pid: 50310, name: "go", command: "go run ./cmd/api"),
                GroupMember(pid: 50377, name: "api", command: "/var/folders/x1/T/go-build/b001/exe/api"),
            ]
        ),
        PortEntry(
            id: "demo-5173", pid: 47102, processName: "node", user: "dev",
            command: "node node_modules/.bin/vite",
            ppid: 47090, uptime: 3 * 3600 + 40 * 60, memoryKB: 184_000, cpu: 0,
            cwd: "\(home)/admin", project: project("admin", "main"),
            bindings: [PortBinding(port: 5173, hosts: ["::1"])],
            role: "Vite", kind: .server,
            group: [
                GroupMember(pid: 47090, name: "npm", command: npm),
                GroupMember(pid: 47102, name: "node", command: "node node_modules/.bin/vite"),
            ]
        ),
        PortEntry(
            id: "demo-8000", pid: 51920, processName: "python3.12", user: "dev",
            command: "python3.12 -m uvicorn app.main:app --reload --port 8000",
            ppid: 51002, uptime: 47 * 60, memoryKB: 2_750_000, cpu: 38.5,
            cwd: "\(home)/ml-playground", project: project("ml-playground", "experiments"),
            bindings: [PortBinding(port: 8000, hosts: ["127.0.0.1"])],
            role: "Uvicorn", kind: .server,
            group: [GroupMember(pid: 51920, name: "python3.12", command: "python3.12 -m uvicorn app.main:app --reload --port 8000")]
        ),
        PortEntry(
            id: "demo-5432", pid: 1402, processName: "com.docker.backend", user: "dev",
            command: "com.docker.backend", uptime: 26 * 3600,
            container: Container(id: "3f9c2a7be81d44c0", name: "shop-postgres", image: "postgres:16"),
            bindings: [PortBinding(port: 5432, hosts: ["*"], containerPort: 5432)],
            connections: [Connection(peer: "127.0.0.1:50130", pid: 50377, process: "api")],
            role: "Docker", kind: .container
        ),
        PortEntry(
            id: "demo-6379", pid: 1402, processName: "com.docker.backend", user: "dev",
            command: "com.docker.backend", uptime: 26 * 3600,
            container: Container(id: "a81e0d55c3b24f19", name: "shop-redis", image: "redis:7"),
            bindings: [PortBinding(port: 6379, hosts: ["127.0.0.1"], containerPort: 6379)],
            role: "Docker", kind: .container
        ),
    ]

    static var history: [String: [Sample]] {
        let now = Date()
        var result: [String: [Sample]] = [:]
        for entry in entries {
            guard let memory = entry.memoryKB else { continue }
            let base = Double(memory) / 1024
            let growing = entry.id == "demo-8000"
            var seed = UInt64(entry.pid)
            func noise() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(1 << 31)
            }
            result[entry.id] = (0..<60).map { step in
                let t = Double(step)
                let memoryMB = growing
                    ? base * (0.55 + 0.45 * t / 59 + noise() * 0.02)
                    : base * (0.94 + sin(t / 6) * 0.02 + noise() * 0.03)
                let spike = noise() > 0.9 ? 2.5 : 1
                let cpu = (entry.cpu ?? 0) * (0.4 + noise() * 0.8) * spike
                return Sample(time: now.addingTimeInterval(-600 + t * 10), memoryMB: memoryMB, cpu: cpu)
            }
        }
        return result
    }
}
