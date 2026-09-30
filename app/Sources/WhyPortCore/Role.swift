import Foundation

enum Role {
    static let databases: Set<String> = ["PostgreSQL", "Redis", "MySQL", "MongoDB"]

    static func arguments(_ command: String) -> [String] {
        var args: [String] = []
        var skipNext = false
        for part in command.split(separator: " ") {
            if skipNext {
                skipNext = false
                continue
            }
            if part == "-cp" || part == "-classpath" || part == "--class-path" {
                skipNext = true
                continue
            }
            if part.hasPrefix("-") { continue }
            args.append(String(part))
        }
        return args
    }

    static func guess(process: String, command: String, cwd: String?) -> String {
        let args = arguments(command)
        let tail = args.suffix(4).joined(separator: " ")
        let executable = ((args.first ?? "") as NSString).lastPathComponent
        let name = "\(process) \(executable)".lowercased()
        let directory = cwd ?? ""

        if command.contains("agentlib:jdwp") || command.contains("-Xrunjdwp") { return "JDWP debugger" }

        if let range = tail.range(of: "GradleDaemon") {
            let version = tail[range.upperBound...].split(separator: " ").first.map(String.init)
            if let version, version.first?.isNumber == true { return "Gradle daemon \(version)" }
            return "Gradle daemon"
        }
        if directory.contains("/.gradle/daemon/") { return "Gradle daemon" }

        if tail.contains("KotlinCompileDaemon") || directory.contains("/kotlin/daemon") {
            if let range = command.range(of: "kotlin-daemon-embeddable-") {
                let version = command[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." })
                let trimmed = version.hasSuffix(".") ? String(version.dropLast()) : String(version)
                if !trimmed.isEmpty { return "Kotlin daemon \(trimmed)" }
            }
            return "Kotlin daemon"
        }

        if name.contains("docker") { return "Docker" }
        if name.contains("postgres") { return "PostgreSQL" }
        if name.contains("redis-server") { return "Redis" }
        if name.contains("mysqld") || name.contains("mariadbd") { return "MySQL" }
        if name.contains("mongod") { return "MongoDB" }

        let lowerTail = tail.lowercased()
        if lowerTail.contains("next-server") || lowerTail.contains("next dev")
            || lowerTail.contains("next start") || lowerTail.contains(".bin/next") { return "Next.js" }
        if lowerTail.contains("vite") { return "Vite" }
        if lowerTail.contains("webpack") { return "webpack" }
        if lowerTail.contains("uvicorn") { return "Uvicorn" }
        if lowerTail.contains("gunicorn") { return "Gunicorn" }

        if executable == "java", args.count > 1 {
            let target = args[1]
            if target.hasSuffix(".jar") { return "java · \((target as NSString).lastPathComponent)" }
            if target.contains("."), !target.contains("/") {
                var main = String(target.split(separator: ".").last ?? Substring(target))
                if main.hasSuffix("Kt") { main.removeLast(2) }
                return "java · \(main)"
            }
        }

        let scripts = ["py", "mjs", "cjs", "js", "ts", "rb", "php"]
        if let script = args.first(where: { scripts.contains(($0 as NSString).pathExtension) }) {
            return "\(process.isEmpty ? "process" : process) · \((script as NSString).lastPathComponent)"
        }
        return process.isEmpty ? "process" : process
    }

    static func kind(role: String, command: String, project: Project?, container: Container?) -> EntryKind {
        if container != nil { return .container }
        if databases.contains(role) { return .database }
        if role.contains("daemon") || role == "JDWP debugger" { return .daemon }
        if project != nil { return .server }
        let bundled = command.split(separator: " ").first?.contains(".app/Contents/") ?? false
        return bundled ? .app : .other
    }
}
