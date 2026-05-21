import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var apiKey = ""
    @State private var savedAPIKeyExists = false
    @State private var isEditingAPIKey = false
    @State private var keychainMessage: String?
    private let apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.title)
                .fontWeight(.semibold)

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
                                SecureField("", text: $apiKey)
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
                                    Label("保存", systemImage: "key")
                                }
                                .buttonStyle(.borderedProminent)
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

                Section("输出文件") {
                    ForEach(OutputFile.allCases) { outputFile in
                        Toggle(outputFile.label, isOn: outputFileBinding(outputFile))
                    }
                    if settings.video.includesVideo {
                        Picker("视频模式", selection: videoSubtitleOutputMode) {
                            Text(SubtitleOutputMode.mkvSoftAss.label).tag(SubtitleOutputMode.mkvSoftAss)
                            Text(SubtitleOutputMode.mp4HardSubtitles.label).tag(SubtitleOutputMode.mp4HardSubtitles)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var videoSubtitleOutputMode: Binding<SubtitleOutputMode> {
        Binding {
            settings.video.subtitleOutputMode == .external ? .mkvSoftAss : settings.video.subtitleOutputMode
        } set: { newValue in
            settings.video.subtitleOutputMode = newValue
        }
    }

    private func outputFileBinding(_ outputFile: OutputFile) -> Binding<Bool> {
        Binding {
            settings.video.outputFiles.contains(outputFile)
        } set: { isSelected in
            if isSelected {
                if !settings.video.outputFiles.contains(outputFile) {
                    settings.video.outputFiles.append(outputFile)
                    settings.video.outputFiles = OutputFile.allCases.filter { settings.video.outputFiles.contains($0) }
                }
                if outputFile == .video, settings.video.subtitleOutputMode == .external {
                    settings.video.subtitleOutputMode = .mkvSoftAss
                }
            } else {
                settings.video.outputFiles.removeAll { $0 == outputFile }
                if outputFile == .video {
                    settings.video.subtitleOutputMode = .external
                }
            }
        }
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
        do {
            apiKey = try apiKeyStore.loadTranslationAPIKey(for: selectedProvider) ?? ""
            isEditingAPIKey = true
            keychainMessage = nil
        } catch {
            apiKey = ""
            isEditingAPIKey = false
            keychainMessage = "Keychain 读取失败：\(error.localizedDescription)"
        }
    }

    private func cancelAPIKeyEditing() {
        apiKey = ""
        isEditingAPIKey = false
        keychainMessage = nil
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedKey.isEmpty {
                if savedAPIKeyExists {
                    try apiKeyStore.clearTranslationAPIKey(for: selectedProvider)
                    savedAPIKeyExists = false
                    keychainMessage = "\(selectedProvider.label) 密钥已清除"
                } else {
                    keychainMessage = nil
                }
            } else {
                try apiKeyStore.saveTranslationAPIKey(trimmedKey, for: selectedProvider)
                savedAPIKeyExists = true
                keychainMessage = "\(selectedProvider.label) 密钥已保存到本机 Keychain"
            }
            apiKey = ""
            isEditingAPIKey = false
        } catch {
            keychainMessage = "\(selectedProvider.label) 密钥更新失败：\(error.localizedDescription)"
        }
    }
}
