import Darwin
import Foundation

public enum StopOutcome: Equatable, Sendable {
    case stopped
    case stillRunning
    case failed(String)
}

public enum RestartOutcome: Equatable, Sendable {
    case restarted(log: String?)
    case failed(String)
}

public enum Stopper {
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func targets(_ entry: PortEntry) -> [Int32] {
        entry.group.isEmpty ? [entry.pid] : entry.group.map(\.pid)
    }

    public static func stop(_ entry: PortEntry, force: Bool) -> StopOutcome {
        if let container = entry.container {
            return Docker.run(["stop", container.id]) ? .stopped : .failed("docker stop \(container.name) failed")
        }
        let pids = targets(entry)
        let signal = force ? SIGKILL : SIGTERM
        for pid in pids where kill(pid, signal) != 0 {
            let code = errno
            if code == ESRCH { continue }
            if code == EPERM { return .failed("Not allowed to stop pid \(pid). It belongs to \(entry.user).") }
            return .failed(String(cString: strerror(code)))
        }
        let deadline = Date().addingTimeInterval(force ? 1 : 3)
        while Date() < deadline {
            if !pids.contains(where: isAlive) { return .stopped }
            usleep(100_000)
        }
        return pids.contains(where: isAlive) ? .stillRunning : .stopped
    }

    public static func restartPlan(_ entry: PortEntry) -> (command: String, directory: String)? {
        guard entry.container == nil else { return nil }
        let root = entry.root ?? GroupMember(pid: entry.pid, name: entry.processName, command: entry.command)
        let rootCwd = Parse.cwds(Shell.run("/usr/sbin/lsof", ["-nP", "-w", "-a", "-p", String(root.pid), "-d", "cwd", "-F", "pn"]).output)[root.pid]
        guard let directory = rootCwd ?? entry.cwd, !root.command.isEmpty else { return nil }
        return (root.command, directory)
    }

    public static func restart(_ entry: PortEntry, logDirectory: URL) -> RestartOutcome {
        if let container = entry.container {
            return Docker.run(["restart", container.id]) ? .restarted(log: nil) : .failed("docker restart \(container.name) failed")
        }
        guard let plan = restartPlan(entry) else { return .failed("Could not find the command and folder that started \(entry.title).") }

        switch stop(entry, force: false) {
        case .failed(let reason): return .failed(reason)
        case .stillRunning:
            if case .failed(let reason) = stop(entry, force: true) { return .failed(reason) }
        case .stopped: break
        }
        waitForPortsToClose(entry.ports)

        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let slug = entry.title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let log = logDirectory.appendingPathComponent("\(String(slug))-\(entry.ports.first ?? 0).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: log) else { return .failed("Could not write \(log.path)") }
        handle.write(Data("\n--- \(Date()) · \(plan.command)\n".utf8))

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", plan.command]
        process.currentDirectoryURL = URL(fileURLWithPath: plan.directory)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        do {
            try process.run()
        } catch {
            return .failed("Could not start \(plan.command): \(error.localizedDescription)")
        }
        return .restarted(log: log.path)
    }

    static func waitForPortsToClose(_ ports: [Int]) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let busy = ports.contains { port in
                !Shell.run("/usr/sbin/lsof", ["-nP", "-w", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]).output
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !busy { return }
            usleep(200_000)
        }
    }
}
