import AppKit
import SwiftUI

enum JobProgressRowMode {
    case detailed
    case compact
}

struct JobProgressRow: View {
    var job: RecentJob
    var mode: JobProgressRowMode = .detailed
    var showsFinderButton = false
    var onOpenOutputDirectory: (() -> Void)?
    var onClear: (() -> Void)?

    var body: some View {
        if mode == .compact {
            compactBody
        } else {
            detailedBody
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(titleText)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(progressValue.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progressValue, total: 1)
        }
        .padding(.vertical, 8)
    }

    private var detailedBody: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusImage)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(titleText)
                        .font(.headline)
                        .lineLimit(1)

                    Text(job.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(job.status.label)
                        .font(.caption)
                        .foregroundStyle(statusColor)

                    if let mode = job.submissionMode {
                        Text(mode.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(job.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(progressValue.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: progressValue, total: 1)

                HStack(spacing: 12) {
                    if job.kind == .audio {
                        Label(job.translationProvider.label, systemImage: "text.bubble")
                    }
                    Label(job.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if let downloadedFilePath = job.downloadedFilePath {
                        Label(URL(fileURLWithPath: downloadedFilePath).lastPathComponent, systemImage: "arrow.down.doc")
                    } else {
                        Label(URL(fileURLWithPath: job.workingDirectory).lastPathComponent, systemImage: "folder")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if job.status == .finished, onOpenOutputDirectory != nil || onClear != nil {
                HStack(spacing: 8) {
                    if let onOpenOutputDirectory {
                        Button("打开", action: onOpenOutputDirectory)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("打开输出位置")
                    }

                    if let onClear {
                        Button("清除", action: onClear)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("从最近任务中清除")
                    }
                }
            } else if showsFinderButton {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.workingDirectory)])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
            }
        }
        .padding(.vertical, 6)
    }

    private var progressValue: Double {
        switch job.status {
        case .queued:
            return 0
        case .running:
            return job.progress ?? 0
        case .finished:
            return 1
        case .failed:
            return job.progress ?? 0
        }
    }

    private var titleText: String {
        switch job.kind {
        case .audio:
            return URL(fileURLWithPath: job.audioPath).lastPathComponent
        case .video:
            return URL(fileURLWithPath: job.videoURL ?? job.audioPath).lastPathComponent
        case .videoDownload:
            return job.videoURL ?? job.audioPath
        }
    }

    private var statusImage: String {
        switch job.status {
        case .queued:
            return "clock"
        case .running:
            return "gearshape.2"
        case .finished:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return .secondary
        case .running:
            return .blue
        case .finished:
            return .green
        case .failed:
            return .red
        }
    }
}
