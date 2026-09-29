import Foundation

enum Docker {
    static let directories = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
        NSHomeDirectory() + "/.docker/bin",
        NSHomeDirectory() + "/.orbstack/bin",
    ]

    static var executable: String? { Shell.find("docker", in: directories) }

    static func publishedPorts() -> [Int: (container: Container, containerPort: Int)] {
        guard let docker = executable else { return [:] }
        let result = Shell.run(docker, ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}"])
        guard result.status == 0 else { return [:] }
        return parse(result.output)
    }

    static func parse(_ text: String) -> [Int: (container: Container, containerPort: Int)] {
        var ports: [Int: (container: Container, containerPort: Int)] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 4 else { continue }
            let container = Container(id: fields[0], name: fields[1], image: fields[2])
            for mapping in Parse.dockerPorts(fields[3]) {
                ports[mapping.host] = (container, mapping.container)
            }
        }
        return ports
    }

    static func run(_ arguments: [String]) -> Bool {
        guard let docker = executable else { return false }
        return Shell.run(docker, arguments).status == 0
    }
}
