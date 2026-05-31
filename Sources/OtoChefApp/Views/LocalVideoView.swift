import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalVideoView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("视频")
                .font(.title)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入")
                        .font(.headline)

                    fileButton(
                        "视频",
                        systemImage: "film",
                        selectionText: selectionSummary(for: store.draft.videoURL)
                    ) {
                        chooseFile(allowedTypes: ["mp4", "mov", "mkv", "webm", "m4v"]) { store.draft.videoURL = $0 }
                    }
                    fileButton(
                        "输出位置",
                        systemImage: "folder",
                        selectionText: outputDirectorySummary
                    ) {
                        chooseDirectory { store.draft.outputDirectory = $0 }
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.draft.inputKind = .video
                            store.startProcessing(mode: .queued)
                        } label: {
                            Label("排队开始", systemImage: "list.bullet")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.draft.inputKind = .video
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
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
                .localVideoPanelCardStyle()

                LocalVideoLogPanel(logText: store.userLogText)
                    .frame(minHeight: 220, maxHeight: 220)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("任务队列")
                    .font(.headline)

                if store.runningVideoJobs.isEmpty {
                    ContentUnavailableView("暂无任务", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.runningVideoJobs) { job in
                                JobProgressRow(job: job, mode: .compact)
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
        .onAppear {
            store.draft.inputKind = .video
            store.validate()
        }
        .onChange(of: store.draft) {
            store.validate()
        }
    }

    private func fileButton(
        _ title: String,
        systemImage: String,
        selectionText: String?,
        action: @escaping () -> Void
    ) -> some View {
        let hasSelection = selectionText != nil

        return HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)

                    if let selectionText {
                        Text(selectionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(hasSelection ? .blue : .primary)
            }

            Spacer()

            Button(action: action) {
                Text("选择")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.blue.opacity(0.36), lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var outputDirectorySummary: String? {
        guard let outputDirectory = store.draft.outputDirectory else {
            return nil
        }
        return "位置: \(abbreviated(outputDirectory.path, limit: 44))"
    }

    private func selectionSummary(for url: URL?) -> String? {
        guard let url else {
            return nil
        }
        return "已选: \(abbreviated(url.lastPathComponent, limit: 22))"
    }

    private func abbreviated(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return "\(value.prefix(limit))..."
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

private struct LocalVideoLogPanel: View {
    var logText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日志")
                .font(.headline)

            ScrollView {
                Text(logText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(logText == "等待任务开始。" ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
        .padding(18)
        .localVideoPanelCardStyle()
    }
}

private extension View {
    func localVideoPanelCardStyle() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}
