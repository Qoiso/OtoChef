# Translation Provider Settings Design

## Goal

Make translation API settings feel persistent and provider-specific. Users should choose a provider, fill in that provider's official fields, and later reopen OtoChef with clear confirmation that the provider's secret is still saved.

## Current Behavior

OtoChef stores the translation API key in macOS Keychain using one generic account, `translation-api-key`. The settings view keeps the key field in local SwiftUI state and initializes it as an empty string every time the view is created. The key may be saved, but the UI does not reload Keychain state or show a saved placeholder, so reopening the app looks like the key disappeared.

The worker currently treats every remote translation API as OpenAI-compatible `/chat/completions`. That works for OpenAI-compatible providers such as DeepSeek, Ollama, LM Studio, and custom gateways, but it does not model Claude's Messages API or Gemini's generateContent API.

## Provider Model

Use a fixed provider enum for the first version:

- `deepSeek`
- `openAI`
- `claude`
- `gemini`
- `ollama`
- `lmStudio`
- `openAICompatible`

`TranslationSettings` stores:

- `selectedProvider`
- provider-specific configurations keyed by provider
- shared translation prompt
- timeout and retry settings

Each provider configuration stores:

- `provider`
- `baseURL`
- `model`
- `requiresAPIKey`

The API key itself remains outside `UserDefaults` and is saved in Keychain under a provider-specific account:

- `translation-api-key.deepSeek`
- `translation-api-key.openAI`
- `translation-api-key.claude`
- `translation-api-key.gemini`
- `translation-api-key.ollama`
- `translation-api-key.lmStudio`
- `translation-api-key.openAICompatible`

Legacy translation settings do not need to be migrated for the user's current workflow. Decoding older settings should still succeed by falling back to defaults, but it is acceptable for the user to re-enter provider settings.

## Default Provider Configuration

Defaults should be useful but editable:

- DeepSeek: `https://api.deepseek.com`, model `deepseek-v4-flash`
- ChatGPT/OpenAI: `https://api.openai.com/v1`, model `gpt-5`
- Claude: `https://api.anthropic.com`, model `claude-sonnet-4-5-20250929`
- Gemini: `https://generativelanguage.googleapis.com`, model `gemini-2.0-flash`
- Ollama: `http://localhost:11434/v1`, model `qwen2.5:7b`, API key not required
- LM Studio: `http://localhost:1234/v1`, model `model-identifier`, API key optional
- OpenAI-compatible API: empty base URL or `https://api.example.com/v1`, empty/custom model, API key optional

## Settings UI

The translation settings section should show:

- provider picker
- provider-specific base URL field when relevant
- model field
- API key secure field for providers that accept a key
- clear saved state: "已保存到本机 Keychain" when a key exists
- save key button that only overwrites the current provider's key
- clear key button when a key exists
- prompt editor
- timeout and retry controls if already present or easy to expose

The secure field should not display the real key. When Keychain already has a value, it can show a bullet placeholder such as `••••••••••••••••` and a status message. Editing the field and pressing save replaces the saved key. Clearing the field should not silently delete the saved key; deletion requires the clear button.

Explain Keychain in the UI using concise app-integrated wording: the key is saved in the user's local macOS Keychain for OtoChef. Avoid implying it is necessarily visible in the Passwords app.

## Worker API Behavior

The worker should route requests by selected provider:

- DeepSeek, ChatGPT/OpenAI, Ollama, LM Studio, and OpenAI-compatible API use OpenAI-compatible chat completions.
- Claude uses Anthropic Messages style: top-level `system`, `messages`, `model`, `max_tokens`, and `temperature`.
- Gemini uses Gemini generateContent: `POST /v1beta/models/{model}:generateContent?key=...` with `contents` and generation config.

All providers keep the same translation contract: the model must return a JSON array of `{ "id": "...", "text": "..." }`, which is parsed into segment translations.

## Validation

Validation should check the selected provider's active config:

- base URL is required for remote HTTP providers
- model is required
- API key is required only for providers that need it when starting a job

Ollama and LM Studio should not require an API key.

## Testing

Swift tests should cover:

- provider defaults exist for every provider
- changing one provider's base URL or model does not affect another provider
- older translation JSON decodes into usable defaults
- provider-specific memory key store saves, loads, and clears separate keys
- job launch passes only the selected provider's API key to the worker
- validation uses the selected provider's active config

Python tests should cover:

- job JSON parses selected provider and provider configurations
- OpenAI-compatible providers build the expected endpoint and auth header
- Claude provider builds the expected Messages request shape
- Gemini provider builds the expected generateContent request shape
- translation response parsing remains provider-independent

## Documentation Sources Checked

- OpenAI official docs: Chat Completions and Responses API use bearer API keys and `/v1` endpoints.
- Anthropic Python SDK docs: Messages API uses `ANTHROPIC_API_KEY`, top-level `system`, required `model`, `messages`, and `max_tokens`.
- Google Gen AI Python SDK docs: Gemini Developer API uses an API key and `models.generate_content`.
- DeepSeek official docs: DeepSeek supports OpenAI-compatible configuration with base URL `https://api.deepseek.com`.
- Ollama docs: local OpenAI compatibility uses `http://localhost:11434/v1` and requires but ignores a dummy key in OpenAI SDK examples.
- LM Studio docs: OpenAI compatibility uses `http://localhost:1234/v1` with `/v1/chat/completions` and other OpenAI-compatible endpoints.
