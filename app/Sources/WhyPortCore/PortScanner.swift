import Foundation

public struct PortScanner: Sendable {
    public init() {}

    public func scan() -> [PortEntry] {
        let listening = Parse.lsof(Shell.run("/usr/sbin/lsof", ["-nP", "-w", "-iTCP", "-sTCP:LISTEN", "-F", "pcLnT"]).output)

        var order: [Int32] = []
        var owners: [Int32: LsofProcess] = [:]
        var bindings: [Int32: [PortBinding]] = [:]
        for process in listening {
            for file in process.files where file.state == "LISTEN" {
                guard let address = Parse.address(file.name) else { continue }
                if owners[process.pid] == nil {
                    owners[process.pid] = process
                    order.append(process.pid)
                }
                var list = bindings[process.pid, default: []]
                if let index = list.firstIndex(where: { $0.port == address.port }) {
                    if !list[index].hosts.contains(address.host) { list[index].hosts.append(address.host) }
                } else {
                    list.append(PortBinding(port: address.port, hosts: [address.host]))
                }
                bindings[process.pid] = list
            }
        }
        guard !order.isEmpty else { return [] }

        let pidList = order.map(String.init).joined(separator: ",")
        let ps = Parse.ps(Shell.run("/bin/ps", ["-ax", "-o", "pid=,ppid=,etime=,rss=,%cpu=,command="]).output)
        let tree = ProcessTree(rows: ps)
        let cwds = Parse.cwds(Shell.run("/usr/sbin/lsof", ["-nP", "-w", "-a", "-p", pidList, "-d", "cwd", "-F", "pn"]).output)
        func name(of pid: Int32) -> String? {
            ps[pid].map { Role.guess(process: ProcessTree.executable($0.command), command: $0.command, cwd: nil) }
        }
        let established = Parse.lsof(Shell.run("/usr/sbin/lsof", ["-nP", "-w", "-iTCP", "-sTCP:ESTABLISHED", "-F", "pcnT"]).output)
        let containers = owners.values.contains(where: { $0.command.lowercased().contains("docker") || $0.command.contains("vpnkit") })
            ? Docker.publishedPorts()
            : [:]

        var projectCache: [String: Project?] = [:]
        func project(for cwd: String?) -> Project? {
            guard let cwd else { return nil }
            if let cached = projectCache[cwd] { return cached }
            let detected = ProjectDetector.detect(cwd: cwd)
            projectCache[cwd] = detected
            return detected
        }

        var entries: [PortEntry] = []
        for pid in order {
            guard let owner = owners[pid] else { continue }
            let row = ps[pid]
            let command = row?.command ?? owner.command
            let executable = (command.split(separator: " ").first.map(String.init) ?? "") as NSString
            let processName = executable.lastPathComponent.isEmpty ? owner.command : executable.lastPathComponent
            let cwd = cwds[pid]
            let detected = project(for: cwd)
            let role = Role.guess(process: processName, command: command, cwd: cwd)

            var remaining = bindings[pid] ?? []
            var byContainer: [String: (Container, [PortBinding])] = [:]
            var containerOrder: [String] = []
            if !containers.isEmpty {
                remaining = remaining.filter { binding in
                    guard let match = containers[binding.port] else { return true }
                    var mapped = binding
                    mapped.containerPort = match.containerPort
                    if byContainer[match.container.id] == nil {
                        byContainer[match.container.id] = (match.container, [])
                        containerOrder.append(match.container.id)
                    }
                    byContainer[match.container.id]?.1.append(mapped)
                    return false
                }
            }

            func entry(id: String, container: Container?, bindings: [PortBinding]) -> PortEntry {
                let sorted = bindings.sorted { $0.port < $1.port }
                let entryProject = container == nil ? detected : nil
                let entryRole = container == nil ? role : "Docker container"
                let kind = Role.kind(role: entryRole, command: command, project: entryProject, container: container)
                let pids = [.server, .database, .other].contains(kind) ? tree.group(for: pid) : [pid]
                let members = pids.compactMap { member -> GroupMember? in
                    guard let memberRow = ps[member] else { return nil }
                    return GroupMember(pid: member, name: ProcessTree.executable(memberRow.command), command: memberRow.command)
                }
                let groupRows = members.compactMap { ps[$0.pid] }
                let groupMemory = groupRows.isEmpty ? row?.rssKB : groupRows.compactMap(\.rssKB).reduce(0, +)
                let groupCPU = groupRows.isEmpty ? row?.cpu : groupRows.compactMap(\.cpu).reduce(0, +)
                let rootElapsed = members.first.flatMap { ps[$0.pid]?.elapsed }
                var entry = PortEntry(
                    id: id,
                    pid: pid,
                    processName: processName,
                    user: owner.user,
                    command: command,
                    ppid: row?.ppid,
                    parentName: row.flatMap { name(of: $0.ppid) },
                    uptime: container == nil ? (rootElapsed ?? row?.elapsed) : row?.elapsed,
                    memoryKB: container == nil ? groupMemory : nil,
                    cpu: container == nil ? groupCPU : nil,
                    cwd: container == nil ? cwd : nil,
                    project: entryProject,
                    container: container,
                    bindings: sorted,
                    connections: [],
                    role: entryRole,
                    kind: kind
                )
                if container == nil { entry.group = members }
                return entry
            }

            for id in containerOrder {
                guard let (container, list) = byContainer[id] else { continue }
                entries.append(entry(id: "docker:\(container.id)", container: container, bindings: list))
            }
            if !remaining.isEmpty {
                entries.append(entry(id: "pid:\(pid)", container: nil, bindings: remaining))
            }
        }

        attachConnections(&entries, established: established)
        return entries.sorted {
            if $0.kind.order != $1.kind.order { return $0.kind.order < $1.kind.order }
            return ($0.ports.first ?? 0) < ($1.ports.first ?? 0)
        }
    }

    func attachConnections(_ entries: inout [PortEntry], established: [LsofProcess]) {
        var portOwner: [Int: Int] = [:]
        for (index, entry) in entries.enumerated() {
            for port in entry.ports { portOwner[port] = index }
        }
        var peers: [Int: [String: Connection]] = [:]
        for process in established {
            for file in process.files {
                guard file.state.isEmpty || file.state == "ESTABLISHED",
                      let endpoint = Parse.endpoint(file.name) else { continue }
                if let index = portOwner[endpoint.localPort], entries[index].pid == process.pid {
                    let key = endpoint.remote
                    if peers[index]?[key] == nil {
                        peers[index, default: [:]][key] = Connection(peer: endpoint.remote, pid: nil, process: nil)
                    }
                }
                let loopback = Bind.loopback.contains(endpoint.remoteHost) || endpoint.remoteHost == endpoint.localHost
                if loopback, let index = portOwner[endpoint.remotePort], entries[index].pid != process.pid {
                    peers[index, default: [:]][endpoint.local] = Connection(peer: endpoint.local, pid: process.pid, process: process.command)
                }
            }
        }
        for (index, connections) in peers {
            entries[index].connections = connections.values.sorted { $0.peer < $1.peer }
        }
    }
}
