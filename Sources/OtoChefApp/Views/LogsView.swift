import AppKit
import SwiftUI

struct LogsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("日志")
                    .font(.title)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    if let url = store.developerLogFileURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("打开日志文件", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .disabled(store.developerLogFileURL == nil)
            }

            ScrollView {
                Text(logText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(store.developerLogText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(24)
    }

    private var logText: String {
        guard !store.developerLogText.isEmpty else {
            return "暂无日志。运行任务后会在这里显示上一次任务的完整日志。"
        }
        return store.developerLogText
    }
}
