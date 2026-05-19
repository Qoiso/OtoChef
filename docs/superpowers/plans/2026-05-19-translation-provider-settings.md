# Translation Provider Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add provider-specific translation settings and Keychain-backed per-provider API keys for DeepSeek, ChatGPT/OpenAI, Claude, Gemini, Ollama, LM Studio, and OpenAI-compatible APIs.

**Architecture:** Swift owns provider selection, provider-specific persisted configuration, validation, and provider-specific Keychain accounts. The worker receives the selected provider and active configuration in the existing job JSON, then routes translation requests through either OpenAI-compatible chat completions, Anthropic Messages, or Gemini generateContent while preserving the current JSON-array translation contract.

**Tech Stack:** SwiftPM macOS app with SwiftUI, Keychain Services, XCTest, Python 3.11 worker, `requests`, pytest.

---

## File Structure

- Modify `Sources/OtoChefApp/Models/AppSettings.swift`: add `TranslationProvider`, `TranslationProviderConfiguration`, provider defaults, active configuration helpers, and tolerant decoding for older saved settings.
- Modify `Sources/OtoChefApp/Services/APIKeyStore.swift`: change key store protocol to provider-specific save/load/clear and add provider-specific Keychain accounts.
- Modify `Sources/OtoChefApp/Views/SettingsView.swift`: show provider picker, active provider fields, saved Keychain status, save/clear key actions, and local Keychain explanation.
- Modify `Sources/OtoChefApp/Services/JobValidator.swift`: validate active provider config instead of legacy endpoint/model fields.
- Modify `Sources/OtoChefApp/Stores/JobStore.swift`: load only the selected provider's key and pass it to the worker.
- Modify `worker/otochef_worker/models.py`: parse selected provider and provider configurations while accepting older job JSON.
- Modify `worker/otochef_worker/translation.py`: add provider routing and request builders for OpenAI-compatible, Claude, and Gemini.
- Modify `worker/otochef_worker/pipeline.py`: construct the routed translation provider.
- Modify Swift and Python tests under `Tests/OtoChefAppTests` and `worker/tests`.

---

### Task 1: Swift Translation Provider Model

**Files:**
- Modify: `Tests/OtoChefAppTests/AppSettingsTests.swift`
- Modify: `Tests/OtoChefAppTests/AppSettingsStoreTests.swift`
- Modify: `Sources/OtoChefApp/Models/AppSettings.swift`

- [ ] **Step 1: Write failing provider default tests**

Add tests that express the new model:

```swift
func testTranslationSettingsProvideDefaultsForEveryProvider() throws {
    let settings = AppSettings.defaults.translation

    XCTAssertEqual(settings.selectedProvider, .ollama)
    XCTAssertEqual(Set(settings.providerConfigurations.map(\.provider)), Set(TranslationProvider.allCases))
    XCTAssertEqual(settings.configuration(for: .deepSeek).baseURL, "https://api.deepseek.com")
    XCTAssertEqual(settings.configuration(for: .openAI).baseURL, "https://api.openai.com/v1")
    XCTAssertEqual(settings.configuration(for: .claude).baseURL, "https://api.anthropic.com")
    XCTAssertEqual(settings.configuration(for: .gemini).baseURL, "https://generativelanguage.googleapis.com")
    XCTAssertEqual(settings.configuration(for: .ollama).baseURL, "http://localhost:11434/v1")
    XCTAssertEqual(settings.configuration(for: .lmStudio).baseURL, "http://localhost:1234/v1")
}

func testUpdatingOneProviderConfigurationDoesNotAffectAnotherProvider() throws {
    var settings = AppSettings.defaults.translation

    settings.updateConfiguration(for: .deepSeek) { configuration in
        configuration.baseURL = "https://custom.deepseek.example"
        configuration.model = "deepseek-custom"
    }

    XCTAssertEqual(settings.configuration(for: .deepSeek).baseURL, "https://custom.deepseek.example")
    XCTAssertEqual(settings.configuration(for: .deepSeek).model, "deepseek-custom")
    XCTAssertEqual(settings.configuration(for: .openAI).baseURL, "https://api.openai.com/v1")
    XCTAssertNotEqual(settings.configuration(for: .openAI).model, "deepseek-custom")
}
```

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter AppSettingsTests/testTranslationSettingsProvideDefaultsForEveryProvider --filter AppSettingsTests/testUpdatingOneProviderConfigurationDoesNotAffectAnotherProvider`

Expected: compile failure because `TranslationProvider`, `providerConfigurations`, `configuration(for:)`, and `updateConfiguration(for:_:)` do not exist.

- [ ] **Step 3: Implement provider model**

In `AppSettings.swift`, replace legacy `TranslationSettings` fields with:

```swift
enum TranslationProvider: String, Codable, Equatable, CaseIterable, Identifiable {
    case deepSeek
    case openAI
    case claude
    case gemini
    case ollama
    case lmStudio
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .openAI: return "ChatGPT / OpenAI"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .openAICompatible: return "OpenAI 兼容 API"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .deepSeek, .openAI, .claude, .gemini:
            return true
        case .ollama, .lmStudio, .openAICompatible:
            return false
        }
    }
}

struct TranslationProviderConfiguration: Codable, Equatable, Identifiable {
    var provider: TranslationProvider
    var baseURL: String
    var model: String

    var id: TranslationProvider { provider }
}

struct TranslationSettings: Codable, Equatable {
    var backend: TranslationBackend
    var selectedProvider: TranslationProvider
    var providerConfigurations: [TranslationProviderConfiguration]
    var prompt: String
    var timeoutSeconds: Int
    var retryLimit: Int

    var activeConfiguration: TranslationProviderConfiguration {
        configuration(for: selectedProvider)
    }

    static let defaultPrompt = "Translate each Japanese subtitle segment into natural Simplified Chinese. Preserve IDs. Return only a JSON array of objects with id and text."

    static let defaultProviderConfigurations = [
        TranslationProviderConfiguration(provider: .deepSeek, baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash"),
        TranslationProviderConfiguration(provider: .openAI, baseURL: "https://api.openai.com/v1", model: "gpt-5"),
        TranslationProviderConfiguration(provider: .claude, baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-5-20250929"),
        TranslationProviderConfiguration(provider: .gemini, baseURL: "https://generativelanguage.googleapis.com", model: "gemini-2.0-flash"),
        TranslationProviderConfiguration(provider: .ollama, baseURL: "http://localhost:11434/v1", model: "qwen2.5:7b"),
        TranslationProviderConfiguration(provider: .lmStudio, baseURL: "http://localhost:1234/v1", model: "model-identifier"),
        TranslationProviderConfiguration(provider: .openAICompatible, baseURL: "https://api.example.com/v1", model: "model-name")
    ]

    func configuration(for provider: TranslationProvider) -> TranslationProviderConfiguration {
        providerConfigurations.first { $0.provider == provider }
            ?? Self.defaultProviderConfigurations.first { $0.provider == provider }!
    }

    mutating func updateConfiguration(
        for provider: TranslationProvider,
        mutate: (inout TranslationProviderConfiguration) -> Void
    ) {
        var configuration = configuration(for: provider)
        mutate(&configuration)
        providerConfigurations.removeAll { $0.provider == provider }
        providerConfigurations.append(configuration)
        providerConfigurations.sort { lhs, rhs in
            guard let lhsIndex = TranslationProvider.allCases.firstIndex(of: lhs.provider),
                  let rhsIndex = TranslationProvider.allCases.firstIndex(of: rhs.provider) else {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return lhsIndex < rhsIndex
        }
    }
}
```

Update `AppSettings.defaults.translation` to:

```swift
translation: TranslationSettings(
    backend: .api,
    selectedProvider: .ollama,
    providerConfigurations: TranslationSettings.defaultProviderConfigurations,
    prompt: TranslationSettings.defaultPrompt,
    timeoutSeconds: 120,
    retryLimit: 2
),
```

- [ ] **Step 4: Run provider default tests**

Run: `swift test --filter AppSettingsTests`

Expected: new tests pass after updating any existing tests that still read `translation.endpoint` or `translation.model`.

- [ ] **Step 5: Add tolerant decoding test**

Add:

```swift
func testTranslationSettingsDecodeOlderEndpointModelShapeIntoDefaults() throws {
    let json = """
    {
      "backend": "api",
      "endpoint": "https://legacy.example.com/v1",
      "model": "legacy-model",
      "prompt": "Legacy prompt",
      "timeoutSeconds": 90,
      "retryLimit": 3
    }
    """

    let settings = try JSONDecoder().decode(TranslationSettings.self, from: Data(json.utf8))

    XCTAssertEqual(settings.selectedProvider, .openAICompatible)
    XCTAssertEqual(settings.configuration(for: .openAICompatible).baseURL, "https://legacy.example.com/v1")
    XCTAssertEqual(settings.configuration(for: .openAICompatible).model, "legacy-model")
    XCTAssertEqual(settings.prompt, "Legacy prompt")
    XCTAssertEqual(settings.timeoutSeconds, 90)
    XCTAssertEqual(settings.retryLimit, 3)
}
```

- [ ] **Step 6: Verify tolerant decoding test fails**

Run: `swift test --filter AppSettingsTests/testTranslationSettingsDecodeOlderEndpointModelShapeIntoDefaults`

Expected: decoding failure or default-only decode because custom `init(from:)` is missing.

- [ ] **Step 7: Add custom decoding and encoding**

Add `CodingKeys` and `init(from:)` to `TranslationSettings` to decode the new shape, then fall back to legacy `endpoint` and `model`:

```swift
enum CodingKeys: String, CodingKey {
    case backend
    case selectedProvider
    case providerConfigurations
    case endpoint
    case model
    case prompt
    case timeoutSeconds
    case retryLimit
}

init(
    backend: TranslationBackend,
    selectedProvider: TranslationProvider,
    providerConfigurations: [TranslationProviderConfiguration],
    prompt: String,
    timeoutSeconds: Int,
    retryLimit: Int
) {
    self.backend = backend
    self.selectedProvider = selectedProvider
    self.providerConfigurations = providerConfigurations
    self.prompt = prompt
    self.timeoutSeconds = timeoutSeconds
    self.retryLimit = retryLimit
}

init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    backend = try container.decodeIfPresent(TranslationBackend.self, forKey: .backend) ?? .api
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? Self.defaultPrompt
    timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 120
    retryLimit = try container.decodeIfPresent(Int.self, forKey: .retryLimit) ?? 2

    if let selectedProvider = try container.decodeIfPresent(TranslationProvider.self, forKey: .selectedProvider),
       let configurations = try container.decodeIfPresent([TranslationProviderConfiguration].self, forKey: .providerConfigurations) {
        self.selectedProvider = selectedProvider
        self.providerConfigurations = Self.mergedWithDefaults(configurations)
    } else {
        let legacyEndpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .model)
        selectedProvider = .openAICompatible
        var configurations = Self.defaultProviderConfigurations
        if legacyEndpoint != nil || legacyModel != nil {
            configurations.removeAll { $0.provider == .openAICompatible }
            configurations.append(
                TranslationProviderConfiguration(
                    provider: .openAICompatible,
                    baseURL: legacyEndpoint ?? "https://api.example.com/v1",
                    model: legacyModel ?? "model-name"
                )
            )
        }
        providerConfigurations = Self.mergedWithDefaults(configurations)
    }
}

static func mergedWithDefaults(_ configurations: [TranslationProviderConfiguration]) -> [TranslationProviderConfiguration] {
    TranslationProvider.allCases.map { provider in
        configurations.first { $0.provider == provider }
            ?? defaultProviderConfigurations.first { $0.provider == provider }!
    }
}
```

- [ ] **Step 8: Run Swift settings tests**

Run: `swift test --filter AppSettingsTests && swift test --filter AppSettingsStoreTests`

Expected: PASS.

---

### Task 2: Provider-Specific Keychain Store

**Files:**
- Modify: `Tests/OtoChefAppTests/APIKeyStoreTests.swift`
- Modify: `Sources/OtoChefApp/Services/APIKeyStore.swift`

- [ ] **Step 1: Write failing per-provider key tests**

Replace the memory key test with:

```swift
func testMemoryAPIKeyStoreSavesLoadsAndClearsPerProviderKeys() throws {
    let store = MemoryAPIKeyStore()

    try store.saveTranslationAPIKey("deepseek-key", for: .deepSeek)
    try store.saveTranslationAPIKey("openai-key", for: .openAI)

    XCTAssertEqual(try store.loadTranslationAPIKey(for: .deepSeek), "deepseek-key")
    XCTAssertEqual(try store.loadTranslationAPIKey(for: .openAI), "openai-key")

    try store.clearTranslationAPIKey(for: .deepSeek)

    XCTAssertNil(try store.loadTranslationAPIKey(for: .deepSeek))
    XCTAssertEqual(try store.loadTranslationAPIKey(for: .openAI), "openai-key")
}
```

- [ ] **Step 2: Verify test fails**

Run: `swift test --filter APIKeyStoreTests/testMemoryAPIKeyStoreSavesLoadsAndClearsPerProviderKeys`

Expected: compile failure because provider-specific methods do not exist.

- [ ] **Step 3: Update key store protocol and memory store**

Change the protocol to:

```swift
protocol APIKeyStore {
    func saveTranslationAPIKey(_ key: String, for provider: TranslationProvider) throws
    func loadTranslationAPIKey(for provider: TranslationProvider) throws -> String?
    func clearTranslationAPIKey(for provider: TranslationProvider) throws
}
```

Change `MemoryAPIKeyStore` to:

```swift
final class MemoryAPIKeyStore: APIKeyStore {
    private var keys: [TranslationProvider: String] = [:]

    func saveTranslationAPIKey(_ key: String, for provider: TranslationProvider) throws {
        keys[provider] = key
    }

    func loadTranslationAPIKey(for provider: TranslationProvider) throws -> String? {
        keys[provider]
    }

    func clearTranslationAPIKey(for provider: TranslationProvider) throws {
        keys.removeValue(forKey: provider)
    }
}
```

- [ ] **Step 4: Update Keychain store**

In `KeychainAPIKeyStore`, derive account by provider:

```swift
private func account(for provider: TranslationProvider) -> String {
    "translation-api-key.\(provider.rawValue)"
}
```

Use `account(for:)` in save/load/clear. Implement clear with `SecItemDelete`; treat `errSecItemNotFound` as success.

- [ ] **Step 5: Run API key tests**

Run: `swift test --filter APIKeyStoreTests`

Expected: PASS.

---

### Task 3: Settings UI and Validation

**Files:**
- Modify: `Tests/OtoChefAppTests/JobValidatorTests.swift`
- Modify: `Tests/OtoChefAppTests/JobStoreTests.swift`
- Modify: `Sources/OtoChefApp/Services/JobValidator.swift`
- Modify: `Sources/OtoChefApp/Stores/JobStore.swift`
- Modify: `Sources/OtoChefApp/Views/SettingsView.swift`

- [ ] **Step 1: Write failing validation tests**

Update endpoint/model validation tests:

```swift
func testValidationFailsWhenSelectedProviderBaseURLIsEmpty() {
    var settings = AppSettings.defaults
    settings.translation.selectedProvider = .deepSeek
    settings.translation.updateConfiguration(for: .deepSeek) { configuration in
        configuration.baseURL = ""
    }
    let draft = JobDraft(
        audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
        imageURL: URL(fileURLWithPath: "/tmp/image.png"),
        outputDirectory: URL(fileURLWithPath: "/tmp/out"),
        settings: settings
    )

    let errors = JobValidator().validate(draft)

    XCTAssertTrue(errors.contains(.missingTranslationEndpoint))
}

func testValidationFailsWhenSelectedProviderModelIsEmpty() {
    var settings = AppSettings.defaults
    settings.translation.selectedProvider = .claude
    settings.translation.updateConfiguration(for: .claude) { configuration in
        configuration.model = ""
    }
    let draft = JobDraft(
        audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
        imageURL: URL(fileURLWithPath: "/tmp/image.png"),
        outputDirectory: URL(fileURLWithPath: "/tmp/out"),
        settings: settings
    )

    let errors = JobValidator().validate(draft)

    XCTAssertTrue(errors.contains(.missingTranslationModel))
}
```

- [ ] **Step 2: Verify validation tests fail**

Run: `swift test --filter JobValidatorTests`

Expected: compile failure until provider model is wired through existing tests, then failing assertions if validator still reads legacy fields.

- [ ] **Step 3: Update validator**

Replace legacy translation validation with:

```swift
let translationConfiguration = draft.settings.translation.activeConfiguration
if translationConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    errors.append(.missingTranslationEndpoint)
}
if translationConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    errors.append(.missingTranslationModel)
}
```

- [ ] **Step 4: Write failing JobStore key selection test**

In `JobStoreTests`, add:

```swift
func testStartProcessingPassesOnlySelectedProviderAPIKey() throws {
    let apiKeyStore = MemoryAPIKeyStore()
    try apiKeyStore.saveTranslationAPIKey("deepseek-key", for: .deepSeek)
    try apiKeyStore.saveTranslationAPIKey("openai-key", for: .openAI)
    let worker = CapturingPythonWorker()
    let transcriber = StubNativeTranscriptionService()
    let settingsStore = MemoryAppSettingsStore()
    var settings = AppSettings.defaults
    settings.asr.backend = .whisperKit
    settings.translation.selectedProvider = .deepSeek
    try settingsStore.save(settings)
    let store = JobStore(
        apiKeyStore: apiKeyStore,
        settingsStore: settingsStore,
        worker: worker,
        transcriber: transcriber,
        toolFileExists: { _ in true }
    )
    store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
    store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
    store.draft.outputDirectory = URL(fileURLWithPath: "/tmp/out")

    store.startProcessing()

    XCTAssertEqual(worker.lastRequest?.environment["OTOCHEF_TRANSLATION_API_KEY"], "deepseek-key")
}
```

If local test helper names differ, adapt to existing stubs in the same file.

- [ ] **Step 5: Update JobStore selected provider key load**

Change:

```swift
let apiKey = try apiKeyStore.loadTranslationAPIKey()
```

to:

```swift
let apiKey = try apiKeyStore.loadTranslationAPIKey(for: job.settings.translation.selectedProvider)
```

- [ ] **Step 6: Update SettingsView**

Replace translation section with provider-aware bindings:

```swift
Picker("提供商", selection: $settings.translation.selectedProvider) {
    ForEach(TranslationProvider.allCases) { provider in
        Text(provider.label).tag(provider)
    }
}

TextField("Base URL", text: activeBaseURL)
TextField("模型", text: activeModel)

if settings.translation.selectedProvider.requiresAPIKey || savedAPIKeyExists || settings.translation.selectedProvider == .openAICompatible || settings.translation.selectedProvider == .lmStudio {
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
```

Add helper bindings:

```swift
private var activeBaseURL: Binding<String> {
    Binding {
        settings.translation.activeConfiguration.baseURL
    } set: { newValue in
        settings.translation.updateConfiguration(for: settings.translation.selectedProvider) {
            $0.baseURL = newValue
        }
    }
}

private var activeModel: Binding<String> {
    Binding {
        settings.translation.activeConfiguration.model
    } set: { newValue in
        settings.translation.updateConfiguration(for: settings.translation.selectedProvider) {
            $0.model = newValue
        }
    }
}
```

Add `onAppear` and `onChange(of: settings.translation.selectedProvider)` to call `loadAPIKeyState()`. `loadAPIKeyState()` should set `apiKey = ""`, `savedAPIKeyExists = true/false`, and a concise message if loading fails.

- [ ] **Step 7: Run Swift focused tests**

Run: `swift test --filter JobValidatorTests && swift test --filter JobStoreTests && swift test --filter APIKeyStoreTests`

Expected: PASS.

---

### Task 4: Worker Provider Parsing

**Files:**
- Modify: `worker/tests/test_models.py`
- Modify: `worker/otochef_worker/models.py`

- [ ] **Step 1: Write failing model parsing test**

Add:

```python
def test_job_from_dict_parses_selected_translation_provider(tmp_path: Path) -> None:
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": "/tmp/audio.wav",
            "imagePath": "/tmp/image.png",
            "outputDirectory": str(tmp_path),
            "settings": {
                "asr": {
                    "backend": "whisperKit",
                    "model": "large-v3-v20240930_626MB",
                    "device": "coreML",
                    "computeType": "all",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
                    "cpuThreads": 8,
                },
                "translation": {
                    "backend": "api",
                    "selectedProvider": "claude",
                    "providerConfigurations": [
                        {"provider": "claude", "baseURL": "https://api.anthropic.com", "model": "claude-sonnet-4-5-20250929"},
                        {"provider": "openAI", "baseURL": "https://api.openai.com/v1", "model": "gpt-5"},
                    ],
                    "prompt": "Translate",
                    "timeoutSeconds": 120,
                    "retryLimit": 2,
                },
                "tools": {"ffmpegPath": "/opt/homebrew/bin/ffmpeg"},
                "video": {"width": 1920, "height": 1080, "imageFit": "contain", "backgroundColor": "black"},
            },
        }
    )

    assert job.translation.selected_provider == "claude"
    assert job.translation.active_configuration.base_url == "https://api.anthropic.com"
    assert job.translation.active_configuration.model == "claude-sonnet-4-5-20250929"
```

- [ ] **Step 2: Verify parsing test fails**

Run: `cd worker && pytest tests/test_models.py::test_job_from_dict_parses_selected_translation_provider -q`

Expected: attribute error because provider configurations are not modeled.

- [ ] **Step 3: Implement Python translation config model**

Add:

```python
@dataclass(frozen=True)
class TranslationProviderConfiguration:
    provider: str
    base_url: str
    model: str
```

Change `TranslationSettings` to include:

```python
selected_provider: str
provider_configurations: tuple[TranslationProviderConfiguration, ...]
prompt: str
timeout_seconds: int
retry_limit: int

@property
def active_configuration(self) -> TranslationProviderConfiguration:
    for configuration in self.provider_configurations:
        if configuration.provider == self.selected_provider:
            return configuration
    raise ValueError(f"Missing configuration for translation provider: {self.selected_provider}")
```

In `Job.from_dict`, if `selectedProvider` exists, parse `providerConfigurations`; otherwise create a legacy `openAICompatible` configuration from `endpoint` and `model`.

- [ ] **Step 4: Run worker model tests**

Run: `cd worker && pytest tests/test_models.py -q`

Expected: PASS.

---

### Task 5: Worker Provider Request Routing

**Files:**
- Modify: `worker/tests/test_translation.py`
- Modify: `worker/otochef_worker/translation.py`
- Modify: `worker/otochef_worker/pipeline.py`

- [ ] **Step 1: Write failing OpenAI-compatible request test**

Use monkeypatching or a small fake `requests.post` to assert:

```python
def test_openai_compatible_provider_posts_to_chat_completions(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": '[{"id":"s1","text":"你好"}]'}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        selected_provider="deepSeek",
        provider_configurations=(TranslationProviderConfiguration("deepSeek", "https://api.deepseek.com", "deepseek-v4-flash"),),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )

    result = RoutedTranslationProvider(settings, api_key="secret").translate([
        TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")
    ])

    assert result == {"s1": "你好"}
    assert calls[0][0] == "https://api.deepseek.com/chat/completions"
    assert calls[0][1]["headers"]["Authorization"] == "Bearer secret"
    assert calls[0][1]["json"]["model"] == "deepseek-v4-flash"
```

- [ ] **Step 2: Write failing Claude request test**

Assert `https://api.anthropic.com/v1/messages`, `x-api-key`, `anthropic-version`, top-level `system`, `messages`, and `max_tokens`.

- [ ] **Step 3: Write failing Gemini request test**

Assert `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=secret`, `contents`, and generation config.

- [ ] **Step 4: Verify request tests fail**

Run: `cd worker && pytest tests/test_translation.py -q`

Expected: import error or attribute error for `RoutedTranslationProvider` and new config classes.

- [ ] **Step 5: Implement routed provider**

Add `RoutedTranslationProvider` that switches on `settings.selected_provider`:

```python
OPENAI_COMPATIBLE_PROVIDERS = {"deepSeek", "openAI", "ollama", "lmStudio", "openAICompatible"}
```

For OpenAI-compatible providers, post to:

```python
f"{configuration.base_url.rstrip('/')}/chat/completions"
```

For Claude, post to:

```python
f"{configuration.base_url.rstrip('/')}/v1/messages"
```

with headers:

```python
{
    "Content-Type": "application/json",
    "x-api-key": api_key or "",
    "anthropic-version": "2023-06-01",
}
```

For Gemini, post to:

```python
f"{configuration.base_url.rstrip('/')}/v1beta/models/{configuration.model}:generateContent"
```

with query param `key=api_key`.

Each route extracts text and calls `parse_translation_response`.

- [ ] **Step 6: Update pipeline**

Replace `OpenAICompatibleTranslationProvider` with `RoutedTranslationProvider` in `worker/otochef_worker/pipeline.py`.

- [ ] **Step 7: Run worker tests**

Run: `cd worker && pytest -q`

Expected: PASS.

---

### Task 6: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run Swift tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 2: Run Python tests**

Run: `cd worker && pytest`

Expected: PASS.

- [ ] **Step 3: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Inspect git diff**

Run: `git diff --stat`

Expected: changes are limited to provider settings, Keychain handling, worker routing, docs, and tests.

---

## Self-Review

- Spec coverage: provider-specific profiles, provider-specific Keychain keys, UI saved state, official protocol routing, validation, and tests are covered.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: Swift uses `TranslationProvider` and `TranslationProviderConfiguration`; Python uses `selected_provider` and `TranslationProviderConfiguration` consistently.
