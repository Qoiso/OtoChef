# Contributing To OtoChef

Thank you for helping improve OtoChef.

## Before You Start

- Search existing issues and pull requests before opening a new one.
- For large behavior changes, open an issue first so the design can be discussed.
- Keep sample media, local model files, build output, and secrets out of Git.

## Development Setup

1. Install Xcode or Xcode Command Line Tools.
2. Install Conda.
3. Run `script/setup_conda_env.sh` to create or update the worker environment.
4. Download WhisperKit/Core ML models into `Models/whisperkit`.

## Testing

Run the relevant targeted tests while developing.

Before opening a pull request, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache \
swift test --disable-sandbox
```

```sh
cd worker
/opt/homebrew/bin/conda run -n otochef python -m pytest
```

## Pull Requests

Pull requests should include:

- A concise user-facing summary.
- The Swift and Python tests you ran.
- Screenshots or recordings for visible UI changes.
- Any migration notes for settings, models, or output files.

Use concise imperative commit subjects. Conventional Commit prefixes such as `feat:`, `fix:`, and `chore:` are welcome.
