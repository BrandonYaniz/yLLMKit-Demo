# yLLMKit Demo

A small macOS SwiftUI chat app that demonstrates how to use
[`yLLMKit`](https://github.com/BrandonYaniz/yLLMKit) from an application target.

The demo is intentionally simple:

- Show the supported local chat models declared by `yLLMKit`.
- Download the selected model when it is not installed.
- Display model download progress.
- Load the selected model.
- Send the full chat history to the local LLM for each response.
- Stream assistant responses into a chat interface.

## Requirements

- macOS 14 or later.
- Swift 6.2 or later.
- Apple Silicon is recommended for MLX-backed local inference.

## yLLMKit Capabilities Used

The current `yLLMKit` package includes the app-facing pieces needed for this
demo:

- `SupportedModelCatalog` for the supported model list.
- `FileModelStore` for tracking installed models.
- `LLMRuntime` for model discovery, download, install, load, and session
  creation.
- `yLLMKitMLX` for MLX-backed local inference.
- `LLMSession.streamResponse(to:settings:)` for streaming chat output.

## Development

Open `yLLMKit-Demo.xcodeproj` in Xcode and run the `yLLMKit-Demo` target.
