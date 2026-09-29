import Foundation

enum ProjectDetector {
    static let markers = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "composer.json",
        "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts", "mix.exs",
    ]

    static func isRuntimeDirectory(_ path: String) -> Bool {
        let fragments = ["/.gradle/", "/.m2/", "/node_modules/", "/Library/Containers/", "/Library/Caches/", "/kotlin/daemon"]
        return fragments.contains { path.contains($0) }
    }

    static func detect(cwd: String?, home: String = NSHomeDirectory()) -> Project? {
        guard let cwd, cwd != "/", !isRuntimeDirectory(cwd) else { return nil }
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: cwd).standardizedFileURL

        while true {
            for marker in markers {
                let file = url.appendingPathComponent(marker)
                if fileManager.fileExists(atPath: file.path) {
                    return Project(name: name(file: file, marker: marker, dir: url), root: url.path, branch: branch(from: url.path))
                }
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || url.path == home { break }
            url = parent
        }

        let resolved = URL(fileURLWithPath: cwd).standardizedFileURL.path
        if resolved == home { return nil }
        return Project(name: (resolved as NSString).lastPathComponent, root: resolved, branch: branch(from: resolved))
    }

    static func name(file: URL, marker: String, dir: URL) -> String {
        let fallback = dir.lastPathComponent
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return fallback }
        switch marker {
        case "package.json", "composer.json":
            let data = Data(text.utf8)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let name = object?["name"] as? String, !name.isEmpty { return name }
        case "go.mod":
            for line in text.split(separator: "\n") where line.hasPrefix("module ") {
                return line.dropFirst(7).trimmingCharacters(in: .whitespaces)
            }
        case "Cargo.toml", "pyproject.toml":
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("name"), let open = trimmed.firstIndex(of: "\"") else { continue }
                let rest = trimmed[trimmed.index(after: open)...]
                if let close = rest.firstIndex(of: "\"") { return String(rest[..<close]) }
            }
        default:
            break
        }
        return fallback
    }

    static func branch(from path: String) -> String? {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: path)
        while true {
            let git = url.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                var gitDir = git
                if !isDirectory.boolValue {
                    guard let text = try? String(contentsOf: git, encoding: .utf8),
                          let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
                    let target = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    gitDir = target.hasPrefix("/") ? URL(fileURLWithPath: target) : url.appendingPathComponent(target)
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                let value = head.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("ref: refs/heads/") { return String(value.dropFirst(16)) }
                return "detached \(value.prefix(7))"
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
    }
}
