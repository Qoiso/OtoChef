import SwiftUI

struct DiagnosticsView: View {
    @Bindable var store: JobStore
    @State private var lastRunAt: Date?
    @State private var diagnosticItems: [EnvironmentDiagnosticItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("诊断")
                    .font(.title)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    diagnosticItems = makeEnvironmentChecks()
                    lastRunAt = Date()
                } label: {
                    Label("运行环境诊断", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            if let lastRunAt {
                Text("上次刷新：\(lastRunAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if diagnosticItems.isEmpty {
                ContentUnavailableView("尚未运行诊断", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(diagnosticItems) { check in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.title)
                                .font(.headline)
                            Text(check.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Image(systemName: check.status.systemImage)
                            .foregroundStyle(check.status.color)
                            .frame(width: 20)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
    }

    private func makeEnvironmentChecks() -> [EnvironmentDiagnosticItem] {
        let settings = store.draft.settings
        let fileManager = FileManager.default
        let condaPath = settings.conda.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let ffmpegPath = settings.tools.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelBaseURL = resolveModelBaseURL(settings.asr.modelFolder)
        let modelURL = modelBaseURL.appendingPathComponent(settings.asr.model, isDirectory: true)
        let workerURL = projectRoot().appendingPathComponent("worker", isDirectory: true)

        return [
            EnvironmentDiagnosticItem(
                title: "Conda 可执行文件",
                message: condaPath.isEmpty ? "未配置 conda 路径。" : condaPath,
                status: !condaPath.isEmpty && fileManager.fileExists(atPath: condaPath) ? .ok : .error
            ),
            EnvironmentDiagnosticItem(
                title: "Conda 环境名",
                message: settings.conda.environmentName.isEmpty ? "未配置 conda 环境名。" : settings.conda.environmentName,
                status: settings.conda.environmentName.isEmpty ? .error : .ok
            ),
            EnvironmentDiagnosticItem(
                title: "FFmpeg",
                message: ffmpegPath.isEmpty ? "未配置 FFmpeg 路径。" : ffmpegPath,
                status: !ffmpegPath.isEmpty && fileManager.fileExists(atPath: ffmpegPath) ? .ok : .warning
            ),
            EnvironmentDiagnosticItem(
                title: "WhisperKit 模型目录",
                message: modelBaseURL.path,
                status: fileManager.fileExists(atPath: modelBaseURL.path) ? .ok : .warning
            ),
            EnvironmentDiagnosticItem(
                title: "当前 WhisperKit 模型",
                message: modelURL.path,
                status: fileManager.fileExists(atPath: modelURL.path) ? .ok : .warning
            ),
            EnvironmentDiagnosticItem(
                title: "Python worker 目录",
                message: workerURL.path,
                status: fileManager.fileExists(atPath: workerURL.path) ? .ok : .error
            )
        ]
    }

    private func resolveModelBaseURL(_ modelFolder: String) -> URL {
        let expandedPath = modelFolder.expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath, isDirectory: true)
        }
        return projectRoot().appendingPathComponent(expandedPath, isDirectory: true)
    }

    private func projectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private struct EnvironmentDiagnosticItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var status: EnvironmentDiagnosticStatus
}

private enum EnvironmentDiagnosticStatus {
    case ok
    case warning
    case error

    var systemImage: String {
        switch self {
        case .ok:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .ok:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
