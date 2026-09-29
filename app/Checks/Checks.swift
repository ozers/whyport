import Foundation
@testable import WhyPortCore

nonisolated(unsafe) var failures = 0

func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition {
        failures += 1
        print("FAIL \(file):\(line) \(message)")
    }
}

func describe(_ address: (host: String, port: Int)?) -> String {
    address.map { "\($0.host) \($0.port)" } ?? "nil"
}

func addresses() {
    check(describe(Parse.address("127.0.0.1:58501")) == "127.0.0.1 58501", "ipv4")
    check(describe(Parse.address("[::1]:61412")) == "::1 61412", "ipv6")
    check(describe(Parse.address("*:8083")) == "* 8083", "wildcard")
    check(Parse.address("127.0.0.1:3000->127.0.0.1:55123") == nil, "connections are not listeners")
}

func lsofFields() {
    let text = "p4632\ncjava\nLozer\nf349\nn127.0.0.1:58501\nTST=LISTEN\nf485\nn[::1]:58501\nTST=LISTEN\np7142\ncPython\nLozer\nf4\nn*:8090\nTST=LISTEN\n"
    let processes = Parse.lsof(text)
    check(processes.map(\.pid) == [4632, 7142], "pids")
    check(processes[0].files.map(\.name) == ["127.0.0.1:58501", "[::1]:58501"], "files")
    check(processes[1].files[0].state == "LISTEN", "state")
    check(Bind.classify(["127.0.0.1", "::1"]) == .localhost, "localhost bind")
    check(Bind.classify(["*"]) == .all, "wildcard bind")
}

func psRows() {
    let rows = Parse.ps(" 7142     1 03-18:46:58  42000   0.1 /usr/bin/python /work/mock services.py\n")
    let row = rows[7142]
    check(row?.ppid == 1, "ppid")
    let expected: TimeInterval = 326_818
    check(row?.elapsed == expected, "elapsed")
    check(row?.rssKB == 42000, "rss")
    check(row?.command == "/usr/bin/python /work/mock services.py", "command keeps spaces")
}

func dockerPorts() {
    let ports = Docker.parse("abc123\tpostgres-dev\tpostgres:16\t0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp\n")
    check(ports[5433]?.container.name == "postgres-dev", "container name")
    check(ports[5433]?.containerPort == 5432, "container port")
}

func roles() {
    check(Role.guess(process: "java", command: "/jdk/bin/java -cp /c/org.postgresql/r2dbc-postgresql.jar com.example.ListingApplicationKt", cwd: nil) == "java · ListingApplication", "main class, not classpath")
    check(Role.guess(process: "java", command: "java -jar /srv/app/orders.jar", cwd: nil) == "java · orders.jar", "jar")
    check(Role.guess(process: "java", command: "java -cp /g.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.7.1", cwd: nil) == "Gradle daemon 9.7.1", "gradle")
    check(Role.guess(process: "java", command: "java -cp kotlin-daemon-embeddable-2.3.21.jar org.jetbrains.kotlin.daemon.KotlinCompileDaemon", cwd: nil) == "Kotlin daemon 2.3.21", "kotlin")
    check(Role.guess(process: "node", command: "node /app/node_modules/.bin/next dev", cwd: nil) == "Next.js", "next")
    check(Role.guess(process: "Python", command: "/usr/bin/Python /work/mock-services.py", cwd: nil) == "Python · mock-services.py", "script")
}

func connections() {
    let entry = PortEntry(
        id: "pid:7142", pid: 7142, processName: "Python", user: "ozer", command: "python", ppid: 1,
        parentName: nil, uptime: nil, memoryKB: nil, cpu: nil, cwd: nil, project: nil, container: nil,
        bindings: [PortBinding(port: 8090, hosts: ["127.0.0.1"])], connections: [], role: "Python", kind: .other
    )
    var entries = [entry]
    let established = Parse.lsof(
        "p7142\ncPython\nf4\nn127.0.0.1:8090->127.0.0.1:55123\nTST=ESTABLISHED\n"
            + "p900\ncnode\nf8\nn127.0.0.1:55123->127.0.0.1:8090\nTST=ESTABLISHED\n"
            + "p901\ncchrome\nf9\nn10.0.0.2:61000->1.2.3.4:8090\nTST=ESTABLISHED\n"
    )
    PortScanner().attachConnections(&entries, established: established)
    check(entries[0].connections == [Connection(peer: "127.0.0.1:55123", pid: 900, process: "node")], "client wins over listener side")
}

func projects() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("whyport-\(UUID().uuidString)")
    let nested = root.appendingPathComponent("services/api")
    let daemon = root.appendingPathComponent(".gradle/daemon/9.6.1")
    try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: daemon, withIntermediateDirectories: true)
    try? #"{"name":"shop"}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try? FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try? "ref: refs/heads/feature/login\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let project = ProjectDetector.detect(cwd: nested.path)
    check(project?.name == "shop", "package name from parent")
    check(project?.branch == "feature/login", "branch from HEAD")
    check(ProjectDetector.detect(cwd: daemon.path) == nil, "daemon folders are not projects")
}

func row(_ pid: Int32, _ ppid: Int32, _ command: String) -> PsRow {
    PsRow(pid: pid, ppid: ppid, elapsed: nil, rssKB: 1000, cpu: 0, command: command)
}

func launchGroups() {
    let npm = ProcessTree(rows: Dictionary(uniqueKeysWithValues: [
        row(100, 1, "/Applications/Cursor.app/Contents/MacOS/Cursor"),
        row(200, 100, "/bin/zsh -il"),
        row(300, 200, "node /opt/homebrew/bin/npm run dev"),
        row(400, 300, "sh -c next dev"),
        row(500, 400, "node /app/node_modules/.bin/next dev"),
        row(600, 500, "node /app/node_modules/next/dist/server/lib/start-server.js"),
    ].map { ($0.pid, $0) }))
    check(npm.launchRoot(of: 600) == 300, "npm run dev owns the listener, the terminal does not")
    check(npm.group(for: 600) == [300, 400, 500, 600], "group is npm and its children")

    let agent = ProcessTree(rows: Dictionary(uniqueKeysWithValues: [
        row(10, 1, "node /Users/me/.local/bin/claude"),
        row(20, 10, "/bin/bash -c python3 -m http.server 8000"),
        row(30, 20, "python3 -m http.server 8000"),
    ].map { ($0.pid, $0) }))
    check(agent.launchRoot(of: 30) == 30, "never climbs into the agent that ran the command")

    let directAgent = ProcessTree(rows: Dictionary(uniqueKeysWithValues: [
        row(11, 1, "node /Users/me/.local/bin/claude"),
        row(12, 11, "node server.js"),
    ].map { ($0.pid, $0) }))
    check(directAgent.launchRoot(of: 12) == 12, "same runtime as the agent is not enough to climb")

    let gradle = ProcessTree(rows: Dictionary(uniqueKeysWithValues: [
        row(1000, 1, "java -cp gradle.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.7.1"),
        row(1100, 1000, "java -cp app.jar com.example.ListingApplicationKt"),
    ].map { ($0.pid, $0) }))
    check(gradle.launchRoot(of: 1100) == 1100, "shared Gradle daemon stays out of the group")

    let reloader = ProcessTree(rows: Dictionary(uniqueKeysWithValues: [
        row(7, 1, "/bin/zsh -il"),
        row(8, 7, "python manage.py runserver"),
        row(9, 8, "python manage.py runserver"),
    ].map { ($0.pid, $0) }))
    check(reloader.launchRoot(of: 9) == 8, "reloader parent with the same executable is included")

    check(Explain.prettyCommand("node /opt/homebrew/lib/node_modules/npm/bin/npm-cli.js run dev") == "npm run dev", "pretty npm")
}

@main
struct Checks {
    static func main() {
        addresses()
        lsofFields()
        psRows()
        dockerPorts()
        roles()
        connections()
        projects()
        launchGroups()
        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("All checks passed")
    }
}
