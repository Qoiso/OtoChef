import AppKit
import SwiftUI

struct VideoDownloadView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("视频")
                .font(.title)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("下载")
                        .font(.headline)

                    TextField("https://", text: $store.videoDraft.urlString)
                        .textFieldStyle(.roundedBorder)

                    Picker("下载参数", selection: $store.draft.settings.videoDownload.preset) {
                        ForEach(VideoDownloadPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    directoryButton

                    HStack {
                        Spacer()
                        Button {
                            store.startVideoDownload()
                        } label: {
                            Label("开始下载", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 276, maxHeight: 276)
                .videoPanelCardStyle()

                VideoDownloadLogPanel(logText: store.userLogText)
                    .frame(minHeight: 276, maxHeight: 276)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("下载队列")
                    .font(.headline)

                if store.runningVideoDownloadJobs.isEmpty {
                    ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.runningVideoDownloadJobs) { job in
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
        .onChange(of: store.videoDraft) {
            store.validateVideoDownload()
        }
    }

    private var directoryButton: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("输出位置")
                    if let outputDirectory = store.videoDraft.outputDirectory {
                        Text("位置: \(abbreviated(outputDirectory.path, limit: 44))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } icon: {
                Image(systemName: "folder")
                    .foregroundStyle(store.videoDraft.outputDirectory == nil ? Color.primary : Color.blue)
            }

            Spacer()

            Button {
                chooseDirectory { store.videoDraft.outputDirectory = $0 }
            } label: {
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

    private func abbreviated(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return "\(value.prefix(limit))..."
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

private struct VideoDownloadLogPanel: View {
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
        .videoPanelCardStyle()
    }
}

private extension View {
    func videoPanelCardStyle() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}
