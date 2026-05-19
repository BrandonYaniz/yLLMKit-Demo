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
    @State private var showsModelManagement = false

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
        .sheet(isPresented: $showsModelManagement) {
            ModelManagementView(model: model)
                .frame(minWidth: 680, minHeight: 520)
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

            if model.installedModels.count > 1 {
                Picker("Model", selection: activeModelSelection) {
                    ForEach(model.installedModels) { descriptor in
                        Text(descriptor.displayName)
                            .tag(descriptor.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                .disabled(model.isThinking)
            }

            Button {
                showsModelManagement = true
            } label: {
                Label("Models", systemImage: "internaldrive")
            }
            .disabled(model.isThinking)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var activeModelSelection: Binding<String> {
        Binding(
            get: { model.activeModelID ?? "" },
            set: { modelID in
                guard let descriptor = model.installedModels.first(where: { $0.id == modelID }) else { return }
                model.switchModel(to: descriptor)
            }
        )
    }
}

private struct ModelManagementView: View {
    @ObservedObject var model: DemoViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models")
                        .font(.title2.weight(.semibold))
                    Text("Download, switch, or remove supported yLLMKit models.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.supportedModels) { descriptor in
                        ManagedModelRow(
                            descriptor: descriptor,
                            localModel: model.localModels.first { $0.modelID == descriptor.id },
                            isInstalled: model.isModelInstalled(descriptor),
                            isActive: model.activeModelID == descriptor.id,
                            isDownloading: model.isDownloading(descriptor),
                            progress: model.modelDownloads[descriptor.id],
                            isBusy: model.isThinking,
                            download: { model.downloadModel(descriptor) },
                            switchModel: { model.switchModel(to: descriptor) },
                            remove: { model.removeModel(descriptor) }
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct ManagedModelRow: View {
    var descriptor: ModelDescriptor
    var localModel: LocalModel?
    var isInstalled: Bool
    var isActive: Bool
    var isDownloading: Bool
    var progress: DownloadProgress?
    var isBusy: Bool
    var download: () -> Void
    var switchModel: () -> Void
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(descriptor.displayName)
                            .font(.headline)

                        if isActive {
                            Text("Active")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.16), in: Capsule())
                        } else if isInstalled {
                            Text("Downloaded")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }

                    Text(descriptor.repository)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Text("Context: \(descriptor.capabilities.contextWindow.formatted())")
                        if let ram = descriptor.recommendedRAMGB {
                            Text("RAM: \(ram) GB")
                        }
                        if let sizeBytes = localModel?.sizeBytes {
                            Text("Size: \(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            if let progress {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(progress.phaseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()

                if isInstalled {
                    Button("Use", action: switchModel)
                        .disabled(isActive || isBusy)

                    Button("Remove", role: .destructive, action: remove)
                        .disabled(isBusy)
                } else {
                    Button("Download", action: download)
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading || isBusy)
                }
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    private var iconName: String {
        if isActive {
            return "checkmark.circle.fill"
        }
        if isInstalled {
            return "internaldrive.fill"
        }
        return "square.and.arrow.down"
    }

    private var iconColor: Color {
        if isActive {
            return .green
        }
        if isInstalled {
            return .accentColor
        }
        return .secondary
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
