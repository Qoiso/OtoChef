import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NewJobView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新任务")
                .font(.title)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入")
                        .font(.headline)

                    fileButton("音频", systemImage: "waveform") {
                        chooseFile(allowedTypes: ["wav", "mp3", "m4a", "flac"]) { store.draft.audioURL = $0 }
                    }
                    fileButton("图片", systemImage: "photo") {
                        chooseFile(allowedTypes: ["png", "jpg", "jpeg", "webp"]) { store.draft.imageURL = $0 }
                    }
                    fileButton("输出位置", systemImage: "folder") {
                        chooseDirectory { store.draft.outputDirectory = $0 }
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.startProcessing(mode: .queued)
                        } label: {
                            Label("排队开始", systemImage: "list.bullet")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.startProcessing(mode: .parallel)
                        } label: {
                            Label("并行开始", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 208, maxHeight: 208)
                .panelCardStyle()

                JobLogPanel(entries: store.logEntries)
                    .frame(minHeight: 208, maxHeight: 208)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("任务队列")
                    .font(.headline)

                if store.recentJobs.isEmpty {
                    ContentUnavailableView("暂无任务", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.recentJobs) { job in
                                JobProgressRow(job: job)
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: store.draft) {
            store.validate()
        }
    }

    private func fileButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer()

            Button("选择", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.blue)
                .fontWeight(.semibold)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func chooseFile(allowedTypes: [String], assign: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }

    private func chooseDirectory(assign: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }

}

private struct JobLogPanel: View {
    var entries: [JobLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日志")
                .font(.headline)

            ScrollView {
                Text(logText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(entries.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(18)
        .panelCardStyle()
    }

    private var logText: String {
        guard !entries.isEmpty else {
            return "等待任务开始。"
        }
        return entries.suffix(40).map { entry in
            let event = entry.event
            let stage = event.stage.map { "[\($0)] " } ?? ""
            let message = event.message ?? event.type.rawValue
            if let progress = event.progress {
                let percentage = progress.formatted(.percent.precision(.fractionLength(0)))
                return "\(timestamp(for: entry.timestamp)) \(stage)\(message) (\(percentage))"
            }
            return "\(timestamp(for: entry.timestamp)) \(stage)\(message)"
        }
        .joined(separator: "\n")
    }

    private func timestamp(for date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}

private extension View {
    func panelCardStyle() -> some View {
        background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}
