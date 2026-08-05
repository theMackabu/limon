import Foundation
import AppKit

struct DockerContainer: Identifiable, Decodable, Hashable {
    let containerID: String
    let names: String
    let image: String
    let status: String
    let state: String
    let ports: String

    enum CodingKeys: String, CodingKey {
        case containerID = "ID"
        case names = "Names"
        case image = "Image"
        case status = "Status"
        case state = "State"
        case ports = "Ports"
    }

    var id: String { containerID }
    var name: String { names.split(separator: ",").first.map(String.init) ?? names }
    var shortID: String { String(containerID.prefix(12)) }

    var isRunning: Bool { state == "running" }
    var isExited: Bool { state == "exited" }

    var publicPort: Int? {
        ports.split(separator: ",").compactMap { mapping -> Int? in
            guard let arrow = mapping.range(of: "->"),
                  let colon = mapping[..<arrow.lowerBound].lastIndex(of: ":")
            else { return nil }
            return Int(mapping[mapping.index(after: colon)..<arrow.lowerBound])
        }.min()
    }
}

struct DockerImage: Identifiable, Decodable, Hashable {
    let imageID: String
    let repository: String
    let tag: String
    let size: String
    let createdSince: String

    enum CodingKeys: String, CodingKey {
        case imageID = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
        case createdSince = "CreatedSince"
    }

    var id: String { "\(imageID) \(repository):\(tag)" }
    var name: String { "\(repository):\(tag)" }
    var isDangling: Bool { repository == "<none>" || tag == "<none>" }
}

struct DockerVolume: Identifiable, Decodable, Hashable {
    let name: String
    let driver: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
    }

    var id: String { name }
}

struct ImageDetails: Decodable {
    let id: String
    let repoTags: [String]
    let architecture: String
    let os: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case repoTags = "RepoTags"
        case architecture = "Architecture"
        case os = "Os"
    }
}

struct VolumeDetails: Decodable {
    let name: String
    let driver: String
    let mountpoint: String
    let createdAt: String
    let scope: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case mountpoint = "Mountpoint"
        case createdAt = "CreatedAt"
        case scope = "Scope"
        case labels = "Labels"
    }
}

enum PruneTarget: Hashable {
    case images
    case volumes
}

struct ServiceNotice: Equatable {
    let message: String
    let isError: Bool
}

@MainActor
final class ColimaService: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var images: [DockerImage] = []
    @Published private(set) var volumes: [DockerVolume] = []
    @Published private(set) var unusedVolumes: Set<String> = []
    @Published private(set) var busy: String?
    @Published private(set) var pruning: Set<PruneTarget> = []
    @Published private(set) var notice: ServiceNotice?

    private var noticeTask: Task<Void, Never>?

    let colima: String?
    let docker: String?

    private var poller: Task<Void, Never>?

    init() {
        colima = Self.locate("colima")
        docker = Self.locate("docker")
        startPolling()
    }


    var title: String {
        if busy != nil { return "🍋 …" }
        guard colima != nil else { return "🍋 ?" }
        return isRunning ? "🍋 \(containers.filter(\.isRunning).count)" : "🍋 ✕"
    }


    private static func locate(_ tool: String) -> String? {
        let home = NSHomeDirectory()
        let dirs = [
            "\(home)/.local/share/mise/shims",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.asdf/shims",
        ]
        for dir in dirs {
            let path = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return loginShellLookup(tool)
    }

    private static func loginShellLookup(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(tool)"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    private nonisolated static let toolPATH: String = {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/share/mise/shims",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
    }()


    private nonisolated static func run(_ path: String, _ args: [String]) async -> (code: Int32, out: String, err: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = toolPATH
                process.environment = environment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                    return
                }

                let errQueue = DispatchQueue(label: "limon.stderr")
                var errData = Data()
                errQueue.async { errData = stderr.fileHandleForReading.readDataToEndOfFile() }

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errQueue.sync {}

                continuation.resume(returning: (
                    process.terminationStatus,
                    String(data: data, encoding: .utf8) ?? "",
                    String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }


    private func startPolling() {
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = UserDefaults.standard.integer(forKey: "refreshSeconds")
                let interval = seconds > 0 ? seconds : 5
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard let colima, busy == nil else { return }

        isRunning = await Self.run(colima, ["status"]).code == 0

        guard isRunning, let docker else {
            containers = []
            images = []
            volumes = []
            unusedVolumes = []
            return
        }

        async let ps = Self.run(docker, ["ps", "-a", "--format", "{{json .}}"])
        async let imageList = Self.run(docker, ["image", "ls", "--format", "{{json .}}"])
        async let volumeList = Self.run(docker, ["volume", "ls", "--format", "{{json .}}"])
        async let unused = Self.run(docker, ["volume", "ls", "-f", "dangling=true", "-q"])

        containers = Self.decodeLines(await ps.out)
        images = Self.decodeLines(await imageList.out)
        volumes = Self.decodeLines(await volumeList.out)
        unusedVolumes = Set(await unused.out.split(separator: "\n").map(String.init))
    }

    private nonisolated static func decodeLines<T: Decodable>(_ out: String) -> [T] {
        let decoder = JSONDecoder()
        return out.split(separator: "\n")
            .compactMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
    }

    func imageDetails(_ ref: String) async -> ImageDetails? {
        guard let docker else { return nil }
        let out = await Self.run(docker, ["image", "inspect", ref]).out
        return (try? JSONDecoder().decode([ImageDetails].self, from: Data(out.utf8)))?.first
    }

    func volumeDetails(_ name: String) async -> VolumeDetails? {
        guard let docker else { return nil }
        let out = await Self.run(docker, ["volume", "inspect", name]).out
        return (try? JSONDecoder().decode([VolumeDetails].self, from: Data(out.utf8)))?.first
    }

    func volumeUsers(_ name: String) async -> [String] {
        guard let docker else { return [] }
        let out = await Self.run(docker, ["ps", "-a", "--filter", "volume=\(name)",
                                          "--format", "{{.Names}}"]).out
        return out.split(separator: "\n").map(String.init)
    }


    func colimaAction(_ args: [String], label: String) {
        guard let colima else { return }
        perform(colima, args, label: label)
    }

    func dockerAction(_ args: [String], label: String) {
        guard let docker else { return }
        perform(docker, args, label: label)
    }

    func prune(_ target: PruneTarget) {
        guard let docker, !pruning.contains(target) else { return }
        let args = target == .images ? ["image", "prune", "-f"] : ["volume", "prune", "-f"]
        let noun = target == .images ? "images" : "volumes"
        Task {
            pruning.insert(target)
            let result = await Self.run(docker, args)
            await refresh()
            pruning.remove(target)

            if result.code == 0 {
                let reclaimed = result.out
                    .split(separator: "\n")
                    .first { $0.hasPrefix("Total reclaimed space:") }
                    .flatMap { $0.split(separator: ":").last }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let detail = reclaimed.map { ", \($0) reclaimed" } ?? ""
                showNotice(ServiceNotice(message: "Pruned \(noun)\(detail)", isError: false))
            } else {
                let reason = result.err
                    .split(separator: "\n")
                    .first
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                showNotice(ServiceNotice(message: reason?.isEmpty == false ? reason! : "Failed to prune \(noun)",
                                         isError: true))
            }
        }
    }

    private func showNotice(_ new: ServiceNotice) {
        noticeTask?.cancel()
        notice = new
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }

    private func perform(_ path: String, _ args: [String], label: String) {
        Task {
            busy = label
            _ = await Self.run(path, args)
            busy = nil
            await refresh()
        }
    }

    private nonisolated static let ghostty: String? = {
        let candidates = [
            "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            "\(NSHomeDirectory())/Applications/Ghostty.app/Contents/MacOS/ghostty",
            "/opt/homebrew/bin/ghostty",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private nonisolated static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func openInTerminal(_ argv: [String]) {
        guard !argv.isEmpty else { return }

        if let ghostty = Self.ghostty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghostty)
            process.arguments = ["-e"] + argv

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = Self.toolPATH
            process.environment = environment

            try? process.run()
            return
        }

        let command = argv.map(Self.shellQuote).joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        NSAppleScript(source: source)?.executeAndReturnError(nil)
    }
}