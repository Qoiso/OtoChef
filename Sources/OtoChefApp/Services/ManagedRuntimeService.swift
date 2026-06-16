import Foundation
import CryptoKit

enum ManagedRuntimeStatus: Equatable {
    case missing
    case ready
}

enum ManagedRuntimeError: LocalizedError {
    case unsupportedArchitecture(String)
    case invalidDownloadResponse
    case checksumMismatch
    case missingEnvironmentFile(String)
    case processFailed(executable: String, status: Int32, output: String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let architecture):
            return "当前处理器架构暂不支持自动配置：\(architecture)"
        case .invalidDownloadResponse:
            return "Micromamba 下载响应无效。"
        case .checksumMismatch:
            return "Micromamba 下载文件校验失败。"
        case .missingEnvironmentFile(let path):
            return "找不到环境定义文件：\(path)"
        case .processFailed(let executable, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(executable) 执行失败，状态码 \(status)。"
                : "\(executable) 执行失败，状态码 \(status)：\(detail)"
        case .verificationFailed(let tool):
            return "环境配置完成，但无法验证 \(tool)。"
        }
    }
}

struct ManagedRuntimePaths: Equatable {
    let projectRoot: URL

    var root: URL {
        projectRoot.appendingPathComponent(".otochef-runtime", isDirectory: true)
    }

    var micromamba: URL {
        root.appendingPathComponent("bin/micromamba")
    }

    var environment: URL {
        root.appendingPathComponent("envs/otochef", isDirectory: true)
    }

    var python: URL {
        environment.appendingPathComponent("bin/python")
    }

    var ffmpeg: URL {
        environment.appendingPathComponent("bin/ffmpeg")
    }

    var ytDLP: URL {
        environment.appendingPathComponent("bin/yt-dlp")
    }

    var deno: URL {
        environment.appendingPathComponent("bin/deno")
    }

    var environmentFile: URL {
        projectRoot.appendingPathComponent("worker/environment.yml")
    }

    var stateFile: URL {
        root.appendingPathComponent("runtime-state.json")
    }

    func requiredToolsExist(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> Bool {
        [micromamba, python, ffmpeg, ytDLP, deno].allSatisfy { fileExists($0.path) }
    }

    func status(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> ManagedRuntimeStatus {
        requiredToolsExist(fileExists: fileExists) && fileExists(stateFile.path) ? .ready : .missing
    }

    static func currentProjectRoot(
        bundleURL: URL = Bundle.main.bundleURL,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> URL {
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
    }
}

extension AppSettings {
    func applyingManagedRuntime(_ paths: ManagedRuntimePaths) -> AppSettings {
        var settings = self
        settings.conda.environmentPath = paths.environment.path
        settings.tools.ffmpegPath = paths.ffmpeg.path
        settings.tools.ytDLPPath = paths.ytDLP.path
        return settings
    }
}

struct ManagedRuntimeInstaller {
    private struct MicromambaArtifact {
        var url: URL
        var sha256: String
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func processEnvironment(
        paths: ManagedRuntimePaths,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for key in ["PATH", "TMPDIR", "LANG", "LC_ALL", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"] {
            if let value = base[key] {
                environment[key] = value
            }
        }
        environment["HOME"] = paths.root.appendingPathComponent("home", isDirectory: true).path
        environment["MAMBA_ROOT_PREFIX"] = paths.root.path
        environment["XDG_CACHE_HOME"] = paths.root.appendingPathComponent("cache", isDirectory: true).path
        return environment
    }

    func configure(
        paths: ManagedRuntimePaths,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws {
        if paths.status() == .ready {
            await onUpdate("检测到已有完整环境，无需重新配置。")
            return
        }
        guard fileManager.fileExists(atPath: paths.environmentFile.path) else {
            throw ManagedRuntimeError.missingEnvironmentFile(paths.environmentFile.path)
        }

        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.micromamba.deletingLastPathComponent(), withIntermediateDirectories: true)
        let processEnvironment = Self.processEnvironment(paths: paths)
        try fileManager.createDirectory(
            at: paths.root.appendingPathComponent("home", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.root.appendingPathComponent("cache", isDirectory: true),
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: paths.micromamba.path) {
            await onUpdate("正在下载项目专用 Micromamba…")
            try await installMicromamba(paths: paths)
        }

        if fileManager.fileExists(atPath: paths.stateFile.path) {
            try fileManager.removeItem(at: paths.stateFile)
        }
        if fileManager.fileExists(atPath: paths.environment.path),
           paths.status() != .ready {
            await onUpdate("检测到未完成的旧环境，正在重新创建…")
            try fileManager.removeItem(at: paths.environment)
        }

        await onUpdate("正在创建 OtoChef 项目环境，首次配置可能需要几分钟…")
        _ = try await runProcess(
            executable: paths.micromamba.path,
            arguments: [
                "create",
                "--yes",
                "--no-rc",
                "--root-prefix", paths.root.path,
                "--prefix", paths.environment.path,
                "--file", paths.environmentFile.path
            ],
            currentDirectory: paths.environmentFile.deletingLastPathComponent(),
            environment: processEnvironment
        )

        await onUpdate("正在验证 Python、FFmpeg 与 yt-dlp…")
        try await verify(paths: paths, environment: processEnvironment)
        await onUpdate("正在清理环境下载缓存…")
        _ = try? await runProcess(
            executable: paths.micromamba.path,
            arguments: ["clean", "--all", "--yes", "--no-rc"],
            currentDirectory: paths.root,
            environment: processEnvironment
        )
        let state = try JSONEncoder().encode(ManagedRuntimeState(schemaVersion: 1))
        try state.write(to: paths.stateFile, options: .atomic)
        await onUpdate("项目运行环境配置完成。")
    }

    private func installMicromamba(paths: ManagedRuntimePaths) async throws {
        let artifact: MicromambaArtifact
        switch ProcessInfo.processInfo.machineArchitecture {
        case "arm64":
            artifact = MicromambaArtifact(
                url: URL(string: "https://micro.mamba.pm/api/micromamba/osx-arm64/2.8.1")!,
                sha256: "a28588c79e96436c2001c87e3b8360bf2eb5c380fb288871389197b9150caf0a"
            )
        case "x86_64":
            artifact = MicromambaArtifact(
                url: URL(string: "https://micro.mamba.pm/api/micromamba/osx-64/2.8.1")!,
                sha256: "146abdea8793c6ccf1b8600ae2b03cf2a0f1506a2846eeafc34ae3ebe1123fe6"
            )
        default:
            throw ManagedRuntimeError.unsupportedArchitecture(ProcessInfo.processInfo.machineArchitecture)
        }
        let (archiveURL, response) = try await URLSession.shared.download(from: artifact.url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ManagedRuntimeError.invalidDownloadResponse
        }
        let archiveData = try Data(contentsOf: archiveURL)
        let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else {
            throw ManagedRuntimeError.checksumMismatch
        }

        let temporaryDirectory = paths.root.appendingPathComponent(".micromamba-extract", isDirectory: true)
        if fileManager.fileExists(atPath: temporaryDirectory.path) {
            try fileManager.removeItem(at: temporaryDirectory)
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        _ = try await runProcess(
            executable: "/usr/bin/tar",
            arguments: ["-xjf", archiveURL.path, "-C", temporaryDirectory.path],
            currentDirectory: paths.root
        )
        let extractedExecutable = temporaryDirectory.appendingPathComponent("bin/micromamba")
        guard fileManager.fileExists(atPath: extractedExecutable.path) else {
            throw ManagedRuntimeError.verificationFailed("Micromamba")
        }
        if fileManager.fileExists(atPath: paths.micromamba.path) {
            try fileManager.removeItem(at: paths.micromamba)
        }
        try fileManager.copyItem(at: extractedExecutable, to: paths.micromamba)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.micromamba.path)
    }

    private func verify(paths: ManagedRuntimePaths, environment: [String: String]) async throws {
        guard paths.requiredToolsExist() else {
            throw ManagedRuntimeError.verificationFailed("必要工具")
        }
        _ = try await runProcess(
            executable: paths.python.path,
            arguments: ["-c", "import otochef_worker"],
            currentDirectory: paths.projectRoot.appendingPathComponent("worker", isDirectory: true),
            environment: environment
        )
        _ = try await runProcess(
            executable: paths.ffmpeg.path,
            arguments: ["-version"],
            currentDirectory: paths.root,
            environment: environment
        )
        _ = try await runProcess(
            executable: paths.ytDLP.path,
            arguments: ["--version"],
            currentDirectory: paths.root,
            environment: environment
        )
        _ = try await runProcess(
            executable: paths.deno.path,
            arguments: ["--version"],
            currentDirectory: paths.root,
            environment: environment
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]? = nil
    ) async throws -> String {
        try await Task.detached {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.environment = environment
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw ManagedRuntimeError.processFailed(
                    executable: URL(fileURLWithPath: executable).lastPathComponent,
                    status: process.terminationStatus,
                    output: output
                )
            }
            return output
        }.value
    }
}

private struct ManagedRuntimeState: Codable {
    var schemaVersion: Int
}

private extension ProcessInfo {
    var machineArchitecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
