import Foundation

struct ProcessTree {
    let rows: [Int32: PsRow]
    let children: [Int32: [Int32]]

    init(rows: [Int32: PsRow]) {
        self.rows = rows
        var children: [Int32: [Int32]] = [:]
        for row in rows.values where row.ppid != row.pid {
            children[row.ppid, default: []].append(row.pid)
        }
        self.children = children.mapValues { $0.sorted() }
    }

    static let wrappers: Set<String> = [
        "npm", "npx", "pnpm", "pnpx", "yarn", "bun", "bunx", "nodemon", "turbo", "concurrently",
        "tsx", "ts-node-dev", "foreman", "overmind", "honcho", "watchexec", "cargo-watch", "air",
    ]
    static let wrapperScripts = [
        "/npm-cli.js", "/bin/npm", "/bin/npx", "/bin/pnpm", "/pnpm.cjs", "/bin/yarn", "/yarn.js",
        "/nodemon", "/concurrently", "/turbo", "/bin/tsx",
    ]
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

    static func executable(_ command: String) -> String {
        let first = command.split(separator: " ").first.map(String.init) ?? ""
        return (first as NSString).lastPathComponent
    }

    static func isWrapper(_ row: PsRow) -> Bool {
        let name = executable(row.command)
        if wrappers.contains(name) { return true }
        if ["node", "bun"].contains(name), wrapperScripts.contains(where: { row.command.contains($0) }) { return true }
        if name == "go", row.command.contains(" run ") { return true }
        if name == "cargo", row.command.contains(" run") || row.command.contains(" watch") { return true }
        if name == "mix", row.command.contains("phx.server") { return true }
        return false
    }

    static func isNonInteractiveShell(_ row: PsRow) -> Bool {
        shells.contains(executable(row.command).trimmingCharacters(in: CharacterSet(charactersIn: "-")))
            && row.command.contains(" -c ")
    }

    static let sharedHosts = ["claude", "codex", "cursor-agent", "gemini", "opencode", "aider", "pm2", "god daemon"]

    static func isOffLimits(_ row: PsRow) -> Bool {
        let lowered = row.command.lowercased()
        return row.pid <= 1
            || row.command.contains(".app/Contents/")
            || row.command.contains("GradleDaemon")
            || row.command.contains("KotlinCompileDaemon")
            || sharedHosts.contains { lowered.contains($0) }
    }

    /// Walks up from a listener through the launchers that exist only to run it (npm, pnpm, go run, a reloader
    /// parent with the same executable), stopping at terminals, editors, agents and anything shared.
    func launchRoot(of pid: Int32) -> Int32 {
        guard var current = rows[pid] else { return pid }
        var root = pid
        while let parent = rows[current.ppid], !Self.isOffLimits(parent) {
            if Self.isWrapper(parent) || Self.executable(parent.command) == Self.executable(current.command) {
                root = parent.pid
                current = parent
                continue
            }
            if Self.isNonInteractiveShell(parent),
               let grandparent = rows[parent.ppid],
               !Self.isOffLimits(grandparent),
               Self.isWrapper(grandparent) {
                root = grandparent.pid
                current = grandparent
                continue
            }
            break
        }
        return root
    }

    func descendants(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var queue = children[pid] ?? []
        var seen: Set<Int32> = [pid]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    func group(for pid: Int32) -> [Int32] {
        let root = launchRoot(of: pid)
        return [root] + descendants(of: root)
    }
}
