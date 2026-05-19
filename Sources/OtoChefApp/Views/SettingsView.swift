import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var apiKey = ""
    @State private var savedAPIKeyExists = false
    @State private var keychainMessage: String?
    private let apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()

    var body: some View {
        Form {
            Section("语音识别") {
                Picker("WhisperKit 模型", selection: $settings.asr.model) {
                    ForEach(ASRSettings.whisperKitModelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Text("模型固定从项目目录 Models/whisperkit 读取，便于统一管理。")
                    .foregroundStyle(.secondary)
                Text("下载：https://huggingface.co/argmaxinc/whisperkit-coreml")
                    .foregroundStyle(.secondary)
                Text("Mac 本机推荐：WhisperKit/Core ML。首次加载会编译模型，之后会命中系统缓存。")
                    .foregroundStyle(.secondary)
                Toggle("语音活动检测（VAD）", isOn: $settings.asr.vadEnabled)
                Text("开启后会自动识别并跳过静音片段，长音频通常更稳。")
                    .foregroundStyle(.secondary)
                Stepper("同时处理片段数: \(settings.asr.cpuThreads)", value: $settings.asr.cpuThreads, in: 1...16)
                Text("数值越高速度可能越快，但会占用更多内存；不确定时保持默认 8。")
                    .foregroundStyle(.secondary)
            }

            Section("翻译") {
                Picker("提供商", selection: $settings.translation.selectedProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                Text(providerHint)
                    .foregroundStyle(.secondary)
                TextField("Base URL", text: activeBaseURL)
                TextField("模型", text: activeModel)
                if showsAPIKeyControls {
                    SecureField(apiKeyPlaceholder, text: $apiKey)
                    HStack {
                        Button {
                            saveAPIKey()
                        } label: {
                            Label("保存密钥", systemImage: "key")
                        }
                        if savedAPIKeyExists {
                            Button(role: .destructive) {
                                clearAPIKey()
                            } label: {
                                Label("清除密钥", systemImage: "trash")
                            }
                        }
                    }
                    Text(savedAPIKeyExists ? "已保存到本机 macOS Keychain，仅 OtoChef 读取这份提供商密钥。" : "密钥会保存在本机 macOS Keychain，不写入任务文件或设置 JSON。")
                        .foregroundStyle(.secondary)
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

            Section("字幕输出") {
                Picker("模式", selection: $settings.video.subtitleOutputMode) {
                    ForEach(SubtitleOutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("默认外挂字幕只生成 SRT/ASS，不合成视频；推荐 MKV + ASS 软字幕。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .onAppear {
            loadAPIKeyState()
        }
        .onChange(of: settings.translation.selectedProvider) {
            loadAPIKeyState()
        }
    }

    private var selectedProvider: TranslationProvider {
        settings.translation.selectedProvider
    }

    private var activeBaseURL: Binding<String> {
        Binding {
            settings.translation.activeConfiguration.baseURL
        } set: { newValue in
            settings.translation.updateConfiguration(for: selectedProvider) { configuration in
                configuration.baseURL = newValue
            }
        }
    }

    private var activeModel: Binding<String> {
        Binding {
            settings.translation.activeConfiguration.model
        } set: { newValue in
            settings.translation.updateConfiguration(for: selectedProvider) { configuration in
                configuration.model = newValue
            }
        }
    }

    private var showsAPIKeyControls: Bool {
        selectedProvider.requiresAPIKey || selectedProvider.acceptsOptionalAPIKey || savedAPIKeyExists
    }

    private var apiKeyPlaceholder: String {
        savedAPIKeyExists ? "••••••••••••••••" : "API Key"
    }

    private var providerHint: String {
        switch selectedProvider {
        case .deepSeek, .openAI, .ollama, .lmStudio, .openAICompatible:
            return "使用 OpenAI 兼容的 /chat/completions 接口。"
        case .claude:
            return "使用 Anthropic Messages API。"
        case .gemini:
            return "使用 Gemini generateContent API。"
        }
    }

    private func loadAPIKeyState() {
        apiKey = ""
        do {
            savedAPIKeyExists = try apiKeyStore.loadTranslationAPIKey(for: selectedProvider) != nil
            keychainMessage = savedAPIKeyExists ? "\(selectedProvider.label) 密钥已保存在本机 Keychain" : nil
        } catch {
            savedAPIKeyExists = false
            keychainMessage = "Keychain 读取失败：\(error.localizedDescription)"
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            keychainMessage = "请输入新的 \(selectedProvider.label) 密钥后再保存"
            return
        }
        do {
            try apiKeyStore.saveTranslationAPIKey(trimmedKey, for: selectedProvider)
            apiKey = ""
            savedAPIKeyExists = true
            keychainMessage = "\(selectedProvider.label) 密钥已保存到本机 Keychain"
        } catch {
            keychainMessage = "\(selectedProvider.label) 密钥保存失败：\(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        do {
            try apiKeyStore.clearTranslationAPIKey(for: selectedProvider)
            apiKey = ""
            savedAPIKeyExists = false
            keychainMessage = "\(selectedProvider.label) 密钥已清除"
        } catch {
            keychainMessage = "\(selectedProvider.label) 密钥清除失败：\(error.localizedDescription)"
        }
    }
}
