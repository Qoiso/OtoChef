# OtoChef

[English](README.md) | [中文](README.zh-CN.md)

OtoChef 是一个面向日语音频和视频字幕制作流程的 macOS 应用。应用本体使用 WhisperKit/Core ML 做本机语音识别，然后把转写结果交给 Python worker 完成翻译、字幕渲染和可选的 FFmpeg 视频输出。

## 功能

- 使用 WhisperKit/Core ML 在 macOS 本机完成语音识别。
- WhisperKit 模型统一放在项目根目录的 `Models/whisperkit`。
- 为 OpenAI、Anthropic、Gemini、DeepSeek、Ollama、LM Studio 和 OpenAI 兼容接口分别保存翻译配置。
- API Key 写入 macOS Keychain，不写入设置 JSON 或任务文件。
- 支持外挂 SRT/ASS、MKV + ASS 软字幕、MP4 硬字幕三种输出。
- Python worker 负责翻译、字幕渲染、进度事件和 FFmpeg 编排。

## 环境要求

- macOS 14 或更新版本。
- Xcode 或 Xcode Command Line Tools，并支持 Swift 5.10。
- Conda，用于 Python worker 环境。
- FFmpeg，用于 MKV/MP4 视频输出。MP4 硬字幕推荐使用 `ffmpeg-full`，因为需要 `subtitles` filter。
- 单独下载 WhisperKit/Core ML 模型。

## 模型设置

OtoChef 从项目根目录下这个被 Git 忽略的目录读取 WhisperKit 模型：

```text
Models/whisperkit
```

请从 [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) 下载兼容的 Core ML 模型并放入该目录。不要提交模型文件。

当前模型选项：

- `openai_whisper-large-v3` - 质量优先的 large-v3 完整模型。
- `openai_whisper-large-v3_947MB` - 默认使用的 large-v3 947MB 平衡模型。
- `large-v3-v20240930_626MB` - 更偏速度的 large-v3 turbo 模型。
- `tiny` - 用于冒烟测试的小模型。

模型首次加载时可能会编译 Core ML 产物，后续通常会命中系统缓存。

## 翻译设置

翻译配置按提供商独立保存。Base URL、模型名和 API Key 不会在不同提供商之间共享。

支持的提供商标签：

- OpenAI-GPT
- Anthropic-Claude
- Google-Gemini
- DeepSeek
- Ollama
- LM Studio
- OpenAI 兼容接口

远程 API Key 会保存到 macOS Keychain，账户名格式为 `translation-api-key.<provider>`。OtoChef 不会把密钥写入 `settings.json` 或 `job.json`。

Ollama、LM Studio 等本地 OpenAI 兼容接口默认可以不填 API Key，除非你的本地服务自行要求鉴权。

## 字幕输出

可以在设置里选择输出模式：

- 外挂字幕：只写出 SRT 和 ASS，不调用 FFmpeg 合成视频。
- MKV + ASS 软字幕：生成带 ASS 软字幕的 `output.mkv`。
- MP4 硬字幕：生成烧录 ASS 字幕的 `output.mp4`，需要 FFmpeg 构建包含 `subtitles` filter。

翻译文本会被当作不可信字幕内容处理。OtoChef 会保留可见文本，并在写入 `.ass` 前中和 ASS override/control 语法。

## 构建和运行

构建 Swift 应用：

```sh
swift build
```

创建或更新 Python worker 环境：

```sh
script/setup_conda_env.sh
```

构建、打包、签名并启动 macOS 应用：

```sh
script/build_and_run.sh
```

验证打包后的应用可以启动：

```sh
script/build_and_run.sh --verify
```

## 测试

运行 Swift 测试：

```sh
swift test
```

在 Codex 沙盒中，或 SwiftPM 缓存权限报错时，使用：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache \
swift test --disable-sandbox
```

运行 Python worker 测试：

```sh
cd worker
/opt/homebrew/bin/conda run -n otochef python -m pytest
```

## 仓库结构

```text
Sources/OtoChefApp/        SwiftPM macOS 应用 target
Tests/OtoChefAppTests/     Swift 单元测试
worker/otochef_worker/     Python media worker 包
worker/tests/              Python worker 测试
Resources/                 App bundle 资源
script/                    环境、构建和运行脚本
docs/superpowers/          设计说明和实现计划
```

## 贡献

欢迎提交 issue 和 pull request。较大的变更请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 安全

请不要在公开 issue 中报告安全问题。披露流程见 [SECURITY.md](SECURITY.md)。

## 许可证

OtoChef 使用 [MIT License](LICENSE) 开源。
