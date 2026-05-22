# OtoChef

[English](README.md) | [中文](README.zh-CN.md)

OtoChef 是一个面向日语音频和视频字幕制作流程的 macOS 应用。应用本体使用 WhisperKit/Core ML 做本机语音识别，然后把转写结果交给 Python worker 完成翻译、字幕渲染和可选的 FFmpeg 视频输出。

## 功能

- 使用 WhisperKit/Core ML 在 macOS 本机完成语音识别。
- WhisperKit 模型统一放在本地项目目录的 `Models/whisperkit`。
- 为 OpenAI、Anthropic、Gemini、DeepSeek、Ollama、LM Studio 和 OpenAI 兼容接口分别保存翻译配置。
- API Key 写入 macOS Keychain，不写入设置 JSON 或任务文件。
- 可分别选择视频、日语字幕、中文字幕和双语字幕输出。
- 视频输出支持 MKV + ASS 软字幕或 MP4 硬字幕。
- Python worker 负责翻译、字幕渲染、进度事件和 FFmpeg 编排。

## 环境要求

- macOS 14 或更新版本。
- Xcode 或 Xcode Command Line Tools，并支持 Swift 5.10。
- Conda，用于 Python worker 环境。
- FFmpeg，用于 MKV/MP4 视频输出。MP4 硬字幕推荐使用 `ffmpeg-full`，因为需要 `subtitles` filter。
- 单独下载 WhisperKit/Core ML 模型。

## 模型设置

OtoChef 从项目根目录下的本地目录读取 WhisperKit 模型：

```text
Models/whisperkit
```

请从 [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) 下载兼容的 Core ML 模型并放入该目录。模型文件通常很大，作为本地资源使用，源码仓库不直接附带。

当前模型选项：

- `openai_whisper-large-v3` - 质量优先的 large-v3 完整模型。
- `openai_whisper-large-v3_947MB` - 默认使用的 large-v3 947MB 平衡模型。
- `large-v3-v20240930_626MB` - 更偏速度的 large-v3 turbo 模型。
- `tiny` - 用于快速验证的小模型。

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

## 输出文件

可以在设置里选择一个或多个输出文件：

- 日语字幕：写出 `subtitles.ja.srt` 和 `subtitles.ja.ass`。
- 中文字幕：写出 `subtitles.zh.srt` 和 `subtitles.zh.ass`。
- 双语字幕：写出 `subtitles.ja-zh.srt` 和 `subtitles.ja-zh.ass`。
- 视频：使用选择的静态图片和音频生成视频。

选择视频输出时，再选择视频字幕模式：

- MKV + ASS 软字幕：生成带 ASS 软字幕的 `output.mkv`。
- MP4 硬字幕：生成烧录 ASS 字幕的 `output.mp4`，需要 FFmpeg 构建包含 `subtitles` filter。

只有选择视频输出时才需要图片和 FFmpeg。只有选择中文字幕、双语字幕或视频输出时才会用到翻译配置，以及对应提供商需要的 API Key。

用户可见文件会直接写入选择的输出目录，默认是项目根目录下的 `output/`。`job.json`、`transcript.ja.json`、`translation.zh.json` 等内部文件会写入 `output/.otochef/<job-id>/`；最新开发日志写入 `output/.otochef/latest-run.log`。

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

## 贡献者检查

运行 Swift 测试：

```sh
swift test
```

如果 SwiftPM 提示缓存权限错误，可以改用项目内 module cache：

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

## 源码结构

```text
Sources/OtoChefApp/        SwiftPM macOS 应用 target
Tests/OtoChefAppTests/     Swift 单元测试
worker/otochef_worker/     Python media worker 包
worker/tests/              Python worker 测试
Resources/                 App bundle 资源
script/                    环境、构建和运行脚本
```

## 贡献

欢迎提交 issue 和 pull request。较大的变更请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 安全

请不要在公开 issue 中报告安全问题。披露流程见 [SECURITY.md](SECURITY.md)。

## 许可证

OtoChef 使用 [MIT License](LICENSE) 开源。
