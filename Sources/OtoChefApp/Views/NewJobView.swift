import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NewJobView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新任务")
                .font(.title)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                fileButton("选择音频", systemImage: "waveform", value: store.draft.audioURL?.lastPathComponent) {
                    chooseFile(allowedTypes: ["wav", "mp3", "m4a", "flac"]) { store.draft.audioURL = $0 }
                }
                fileButton("选择图片", systemImage: "photo", value: store.draft.imageURL?.lastPathComponent) {
                    chooseFile(allowedTypes: ["png", "jpg", "jpeg", "webp"]) { store.draft.imageURL = $0 }
                }
            }

            fileButton("选择输出文件夹", systemImage: "folder", value: store.draft.outputDirectory?.path) {
                chooseDirectory { store.draft.outputDirectory = $0 }
            }

            if !store.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.validationErrors) { error in
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            List(store.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message ?? event.type.rawValue)
                    if let path = event.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                store.startProcessing()
            } label: {
                Label("开始处理", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canStart())
        }
        .padding(24)
        .onChange(of: store.draft) {
            store.validate()
        }
    }

    private func fileButton(_ title: String, systemImage: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(value ?? "未选择")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
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
