import AppKit
import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var apiKey = ""
    @State private var keychainMessage: String?
    private let apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()

    var body: some View {
        Form {
            Section("语音识别") {
                TextField("模型路径或 ID", text: $settings.asr.model)
                Button {
                    chooseModelDirectory()
                } label: {
                    Label("选择模型文件夹", systemImage: "folder")
                }
                Text("推荐：Systran/faster-whisper-large-v3")
                    .foregroundStyle(.secondary)
                Text("下载：https://huggingface.co/Systran/faster-whisper-large-v3")
                    .foregroundStyle(.secondary)
                TextField("设备", text: $settings.asr.device)
                TextField("计算类型", text: $settings.asr.computeType)
                Toggle("启用 VAD", isOn: $settings.asr.vadEnabled)
                Stepper("Beam Size: \(settings.asr.beamSize)", value: $settings.asr.beamSize, in: 1...10)
            }

            Section("翻译") {
                Picker("后端", selection: $settings.translation.backend) {
                    Text("本地").tag(TranslationBackend.local)
                    Text("API").tag(TranslationBackend.api)
                }
                TextField("Endpoint", text: $settings.translation.endpoint)
                TextField("模型", text: $settings.translation.model)
                SecureField("API Key", text: $apiKey)
                Button {
                    do {
                        try apiKeyStore.saveTranslationAPIKey(apiKey)
                        keychainMessage = "API Key 已保存到 Keychain"
                    } catch {
                        keychainMessage = "API Key 保存失败：\(error.localizedDescription)"
                    }
                } label: {
                    Label("保存 API Key", systemImage: "key")
                }
                if let keychainMessage {
                    Text(keychainMessage)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $settings.translation.prompt)
                    .frame(minHeight: 80)
            }

            Section("工具") {
                TextField("Conda", text: $settings.conda.executablePath)
                TextField("Conda 环境", text: $settings.conda.environmentName)
                TextField("FFmpeg", text: $settings.tools.ffmpegPath)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.asr.model = url.path
        }
    }
}
