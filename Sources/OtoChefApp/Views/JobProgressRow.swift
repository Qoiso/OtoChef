import AppKit
import SwiftUI

struct JobProgressRow: View {
    var job: RecentJob
    var showsFinderButton = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusImage)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: job.audioPath).lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

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
                    Label(job.translationProvider.label, systemImage: "text.bubble")
                    Label(job.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(URL(fileURLWithPath: job.workingDirectory).lastPathComponent, systemImage: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if showsFinderButton {
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
