import SwiftUI
import yLLMKit

struct ContentView: View {
    @StateObject private var model = DemoViewModel()

    var body: some View {
        ZStack {
            switch model.setupState {
            case .checking:
                SetupStatusView(
                    title: "Checking for local models",
                    message: "Looking for a downloaded yLLMKit model.",
                    showsProgress: true
                )

            case .needsModel(let models):
                ModelSelectionView(
                    models: models,
                    onSelect: model.downloadAndLoad
                )

            case .downloading(let descriptor, let progress):
                DownloadProgressView(
                    model: descriptor,
                    progress: progress
                )

            case .loading(let descriptor):
                SetupStatusView(
                    title: "Loading \(descriptor.displayName)",
                    message: "Preparing the local model for chat.",
                    showsProgress: true
                )

            case .ready:
                ChatView(model: model)

            case .failed(let message):
                ErrorStateView(
                    message: message,
                    retry: model.retrySetup
                )
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .task {
            await model.start()
        }
    }
}

private struct SetupStatusView: View {
    var title: String
    var message: String
    var showsProgress: Bool

    var body: some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}

private struct ModelSelectionView: View {
    var models: [ModelDescriptor]
    var onSelect: (ModelDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a local model")
                    .font(.largeTitle.weight(.semibold))
                Text("No downloaded yLLMKit model was found. Select one of the supported chat models to download.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(models) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            ModelRow(model: model)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(32)
    }
}

private struct ModelRow: View {
    var model: ModelDescriptor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.and.arrow.down")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(model.displayName)
                        .font(.headline)

                    if let ram = model.recommendedRAMGB {
                        Text("\(ram) GB RAM")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(model.repository)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Context window: \(model.capabilities.contextWindow.formatted()) tokens")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}

private struct DownloadProgressView: View {
    var model: ModelDescriptor
    var progress: DownloadProgress

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Downloading \(model.displayName)")
                    .font(.title2.weight(.semibold))
                Text(progress.message ?? model.repository)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .frame(width: 360)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(progress.phaseLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}

private struct ErrorStateView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("yLLMKit setup failed")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520)
        .padding(32)
    }
}

private struct ChatView: View {
    @ObservedObject var model: DemoViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: model.messages) { _, messages in
                    guard let lastID = messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider()

            VStack(spacing: 10) {
                HStack {
                    Label(model.statusText, systemImage: model.isThinking ? "brain" : "checkmark.circle")
                        .foregroundStyle(model.isThinking ? Color.secondary : Color.green)
                    Spacer()
                }
                .font(.caption)

                ChatInputView(
                    text: $model.draftMessage,
                    isEnabled: !model.isThinking,
                    onSubmit: model.sendDraftMessage
                )
                .frame(height: 92)
            }
            .padding(16)
            .background(.bar)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("yLLMKit Demo")
                    .font(.headline)
                Text(model.activeModelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct MessageBubble: View {
    var message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(message.role.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message.content.isEmpty ? "Thinking..." : message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(message.content.isEmpty ? .secondary : .primary)
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
    }
}

#Preview {
    ContentView()
}
