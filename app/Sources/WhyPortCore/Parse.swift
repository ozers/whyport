import Foundation

struct LsofFile: Hashable {
    var fd: String
    var name = ""
    var state = ""
}

struct LsofProcess: Hashable {
    var pid: Int32
    var command = ""
    var user = ""
    var files: [LsofFile] = []
}

struct PsRow: Hashable {
    var pid: Int32
    var ppid: Int32
    var elapsed: TimeInterval?
    var rssKB: Int?
    var cpu: Double?
    var command: String
}

struct Endpoint: Hashable {
    var local: String
    var remote: String
    var localHost: String
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
}

enum Parse {
    static func lsof(_ text: String) -> [LsofProcess] {
        var result: [LsofProcess] = []
        for line in text.split(separator: "\n") {
            guard let id = line.first else { continue }
            let value = String(line.dropFirst())
            if id == "p" {
                result.append(LsofProcess(pid: Int32(value) ?? 0))
                continue
            }
            guard !result.isEmpty else { continue }
            let last = result.count - 1
            switch id {
            case "c": result[last].command = value
            case "L": result[last].user = value
            case "f": result[last].files.append(LsofFile(fd: value))
            case "n":
                if !result[last].files.isEmpty {
                    result[last].files[result[last].files.count - 1].name = value
                }
            case "T":
                if value.hasPrefix("ST="), !result[last].files.isEmpty {
                    result[last].files[result[last].files.count - 1].state = String(value.dropFirst(3))
                }
            default: break
            }
        }
        return result
    }

    static func address(_ name: String) -> (host: String, port: Int)? {
        if name.contains("->") { return nil }
        if name.hasPrefix("[") {
            guard let close = name.firstIndex(of: "]") else { return nil }
            let host = String(name[name.index(after: name.startIndex)..<close])
            let rest = name[name.index(after: close)...]
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return nil }
            return (host, port)
        }
        guard let colon = name.lastIndex(of: ":"), colon != name.startIndex else { return nil }
        guard let port = Int(name[name.index(after: colon)...]) else { return nil }
        return (String(name[..<colon]), port)
    }

    static func endpoint(_ name: String) -> Endpoint? {
        let parts = name.components(separatedBy: "->")
        guard parts.count == 2,
              let local = address(parts[0]),
              let remote = address(parts[1]) else { return nil }
        return Endpoint(
            local: parts[0], remote: parts[1],
            localHost: local.host, localPort: local.port,
            remoteHost: remote.host, remotePort: remote.port
        )
    }

    static func elapsed(_ text: String) -> TimeInterval? {
        var days = 0
        var clock = Substring(text)
        if let dash = text.firstIndex(of: "-") {
            days = Int(text[..<dash]) ?? 0
            clock = text[text.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return TimeInterval(days * 86_400 + seconds)
    }

    static func ps(_ text: String) -> [Int32: PsRow] {
        var rows: [Int32: PsRow] = [:]
        for line in text.split(separator: "\n") {
            var rest = Substring(line)
            func token() -> Substring? {
                rest = rest.drop(while: { $0 == " " })
                guard !rest.isEmpty else { return nil }
                let value = rest.prefix(while: { $0 != " " })
                rest = rest.dropFirst(value.count)
                return value
            }
            guard let pid = token().flatMap({ Int32($0) }),
                  let ppid = token().flatMap({ Int32($0) }),
                  let etime = token(),
                  let rss = token(),
                  let cpu = token() else { continue }
            rows[pid] = PsRow(
                pid: pid,
                ppid: ppid,
                elapsed: elapsed(String(etime)),
                rssKB: Int(rss),
                cpu: Double(cpu.replacingOccurrences(of: ",", with: ".")),
                command: rest.trimmingCharacters(in: .whitespaces)
            )
        }
        return rows
    }

    static func names(_ text: String) -> [Int32: String] {
        var names: [Int32: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]) else { continue }
            let path = trimmed[space...].trimmingCharacters(in: .whitespaces)
            names[pid] = (path as NSString).lastPathComponent
        }
        return names
    }

    static func cwds(_ text: String) -> [Int32: String] {
        var cwds: [Int32: String] = [:]
        for process in lsof(text) {
            if let file = process.files.first(where: { $0.fd == "cwd" && !$0.name.isEmpty }) {
                cwds[process.pid] = file.name
            }
        }
        return cwds
    }

    static func dockerPorts(_ text: String) -> [(host: Int, container: Int)] {
        var result: [(host: Int, container: Int)] = []
        for mapping in text.components(separatedBy: ",") {
            let parts = mapping.trimmingCharacters(in: .whitespaces).components(separatedBy: "->")
            guard parts.count == 2,
                  parts[1].hasSuffix("/tcp"),
                  let host = address(parts[0])?.port,
                  let container = Int(parts[1].dropLast(4)) else { continue }
            if !result.contains(where: { $0.host == host }) { result.append((host, container)) }
        }
        return result
    }
}
