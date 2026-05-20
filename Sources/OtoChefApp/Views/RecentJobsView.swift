import AppKit
import SwiftUI

struct RecentJobsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近任务")
                .font(.title)
                .fontWeight(.semibold)

            if store.recentJobs.isEmpty {
                ContentUnavailableView("暂无最近任务", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.recentJobs) { job in
                    RecentJobRow(job: job)
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
    }
}

private struct RecentJobRow: View {
    var job: RecentJob

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusImage)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: job.audioPath).lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.status.label)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                Text(job.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(job.translationProvider.label, systemImage: "text.bubble")
                    Label(job.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(URL(fileURLWithPath: job.workingDirectory).lastPathComponent, systemImage: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.workingDirectory)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
        }
        .padding(.vertical, 6)
    }

    private var statusImage: String {
        switch job.status {
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
        case .running:
            return .blue
        case .finished:
            return .green
        case .failed:
            return .red
        }
    }
}
