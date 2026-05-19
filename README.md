# yLLMKit Demo

A small macOS SwiftUI chat app that demonstrates how to use
[`yLLMKit`](https://github.com/BrandonYaniz/yLLMKit) from an application target.

The demo is intentionally simple:

- Show the supported local chat models declared by `yLLMKit`.
- Download the selected model when it is not installed.
- Display model download progress.
- Load the selected model.
- Manage downloaded models from the app.
- Switch between downloaded models from the chat window.
- Send the full chat history to the local LLM for each response.
- Stream assistant responses into a chat interface.

## Requirements

- macOS 14 or later.
- Swift 6.2 or later.
- Full Xcode, not only the Command Line Tools package.
- Apple Silicon is recommended for MLX-backed local inference.

## Fresh Xcode Setup

On a new machine or a fresh Xcode install, make sure the active developer
directory points at Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Run Xcode's first-launch setup so license acceptance and required components
are ready before the first build:

```sh
sudo xcodebuild -runFirstLaunch
```

Install the Metal Toolchain before building the MLX-backed target:

```sh
xcodebuild -downloadComponent MetalToolchain
```

The first build will resolve Swift Package dependencies from GitHub, including
`yLLMKit`, `mlx-swift-lm`, `mlx-swift`, and Hugging Face packages, so network
access is required.

When building from the command line, skip macro validation for the MLX package
macro target:

```sh
xcodebuild \
  -skipMacroValidation \
  -project yLLMKit-Demo.xcodeproj \
  -scheme yLLMKit-Demo \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Opening the project in Xcode may prompt you to trust or enable package macros.
Approve the prompt for the MLX dependency when asked.

## yLLMKit Capabilities Used

The current `yLLMKit` package includes the app-facing pieces needed for this
demo:

- `SupportedModelCatalog` for the supported model list.
- `FileModelStore` for tracking installed models.
- `LLMRuntime` for model discovery, download, install, load, and session
  creation.
- `LLMRuntime.removeModel(id:)` for deleting downloaded models.
- `yLLMKitMLX` for MLX-backed local inference.
- `LLMSession.streamResponse(to:settings:)` for streaming chat output.

## Development

Open `yLLMKit-Demo.xcodeproj` in Xcode and run the `yLLMKit-Demo` target.
