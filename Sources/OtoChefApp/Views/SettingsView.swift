import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var apiKey = ""
    @State private var savedAPIKeyExists = false
    @State private var isEditingAPIKey = false
    @State private var keychainMessage: String?
    private let apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()

    var body: some View {
        Form {
            Section("语音识别") {
                Picker("WhisperKit 模型", selection: $settings.asr.model) {
                    ForEach(ASRSettings.whisperKitModelChoices) { choice in
                        Text(choice.label).tag(choice.model)
                    }
                }
                Toggle("语音活动检测（VAD）", isOn: $settings.asr.vadEnabled)
                Stepper(
                    "同时处理片段数: \(settings.asr.cpuThreads)",
                    value: $settings.asr.cpuThreads,
                    in: 1...ASRSettings.maxWhisperKitConcurrentSegments
                )
            }

            Section("翻译") {
                Picker("提供商", selection: $settings.translation.selectedProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                TextField("Base URL", text: activeBaseURL)
                TextField("模型", text: activeModel)
                if showsAPIKeyControls {
                    LabeledContent("API密钥") {
                        if isEditingAPIKey {
                            SecureField("API Key", text: $apiKey)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text(savedAPIKeyExists ? "••••••••••••••••" : "")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    HStack {
                        Spacer()
                        if isEditingAPIKey {
                            Button {
                                saveAPIKey()
                            } label: {
                                Label("保存密钥", systemImage: "key")
                            }
                            Button {
                                cancelAPIKeyEditing()
                            } label: {
                                Label("取消", systemImage: "xmark")
                            }
                        } else {
                            Button {
                                beginAPIKeyEditing()
                            } label: {
                                Label("编辑密钥", systemImage: "pencil")
                            }
                        }
                        if savedAPIKeyExists {
                            Button(role: .destructive) {
                                clearAPIKey()
                            } label: {
                                Label("清除密钥", systemImage: "trash")
                            }
                        }
                    }
                }
                if let keychainMessage {
                    Text(keychainMessage)
                        .foregroundStyle(.secondary)
                }
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

    private func loadAPIKeyState() {
        apiKey = ""
        isEditingAPIKey = false
        do {
            savedAPIKeyExists = try apiKeyStore.loadTranslationAPIKey(for: selectedProvider) != nil
            keychainMessage = nil
        } catch {
            savedAPIKeyExists = false
            keychainMessage = "Keychain 读取失败：\(error.localizedDescription)"
        }
    }

    private func beginAPIKeyEditing() {
        apiKey = ""
        isEditingAPIKey = true
        keychainMessage = nil
    }

    private func cancelAPIKeyEditing() {
        apiKey = ""
        isEditingAPIKey = false
        keychainMessage = nil
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
            isEditingAPIKey = false
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
            isEditingAPIKey = false
            savedAPIKeyExists = false
            keychainMessage = "\(selectedProvider.label) 密钥已清除"
        } catch {
            keychainMessage = "\(selectedProvider.label) 密钥清除失败：\(error.localizedDescription)"
        }
    }
}
