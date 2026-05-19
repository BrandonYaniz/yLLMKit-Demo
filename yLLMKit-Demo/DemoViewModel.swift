import Combine
import Foundation
import yLLMKit
import yLLMKitMLX

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var setupState: SetupState = .checking
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draftMessage = ""
    @Published private(set) var isThinking = false
    @Published private(set) var statusText = "Ready"

    private var runtime: LLMRuntime?
    private var session: (any LLMSession)?
    private var activeModel: ModelDescriptor?
    private var setupTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?

    var activeModelName: String {
        activeModel?.displayName ?? "No model loaded"
    }

    func start() async {
        guard setupTask == nil else { return }
        retrySetup()
    }

    func retrySetup() {
        setupTask?.cancel()
        setupTask = Task {
            await configureRuntimeAndLoadModel()
        }
    }

    func downloadAndLoad(_ model: ModelDescriptor) {
        setupTask?.cancel()
        setupTask = Task {
            await downloadAndLoadModel(model)
        }
    }

    func sendDraftMessage() {
        let content = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isThinking else { return }

        draftMessage = ""
        messages.append(ChatMessage(role: .user, content: content))

        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))

        isThinking = true
        statusText = "Thinking"

        generationTask?.cancel()
        generationTask = Task {
            await generateResponse(assistantID: assistantID)
        }
    }

    private func configureRuntimeAndLoadModel() async {
        setupState = .checking
        do {
            let runtime = try makeRuntime()
            self.runtime = runtime

            let supportedModels = await runtime.supportedModels()
            let installedModel = try await firstInstalledModel(in: supportedModels, runtime: runtime)

            guard let installedModel else {
                setupState = .needsModel(supportedModels)
                return
            }

            try await load(model: installedModel, runtime: runtime)
        } catch {
            setupState = .failed(error.localizedDescription)
        }
    }

    private func downloadAndLoadModel(_ model: ModelDescriptor) async {
        do {
            let runtime = try runtime ?? makeRuntime()
            self.runtime = runtime

            setupState = .downloading(model, DownloadProgress(phaseLabel: "Queued"))
            let stream = try await runtime.downloadAndInstallModel(id: model.id)

            for try await progress in stream {
                setupState = .downloading(model, DownloadProgress(progress: progress))
            }

            try await load(model: model, runtime: runtime)
        } catch {
            setupState = .failed(error.localizedDescription)
        }
    }

    private func load(model: ModelDescriptor, runtime: LLMRuntime) async throws {
        setupState = .loading(model)
        _ = try await runtime.loadModel(id: model.id)
        session = try await runtime.createSession(
            modelID: model.id,
            configuration: SessionConfiguration(
                systemPrompt: "You are a concise, helpful local assistant running through the yLLMKit demo app."
            )
        )
        activeModel = model
        statusText = "Ready"
        setupState = .ready
    }

    private func makeRuntime() throws -> LLMRuntime {
        let registry = try ModelRegistry(models: SupportedModelCatalog.all)
        let store = try FileModelStore(
            rootDirectory: modelStoreURL(),
            removalPolicy: .registeredPaths
        )
        return try LLMRuntime(
            modelRegistry: registry,
            modelStore: store,
            backends: [MLXBackend()]
        )
    }

    private func modelStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupport
            .appendingPathComponent("yLLMKit-Demo", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func firstInstalledModel(
        in models: [ModelDescriptor],
        runtime: LLMRuntime
    ) async throws -> ModelDescriptor? {
        for model in models {
            if try await runtime.isModelInstalled(model.id) {
                return model
            }
        }

        return nil
    }

    private func generateResponse(assistantID: UUID) async {
        guard let session, let activeModel else {
            updateAssistantMessage(id: assistantID, content: "No model session is available.")
            isThinking = false
            statusText = "Ready"
            return
        }

        do {
            for try await token in session.streamResponse(
                to: llmMessages(),
                settings: activeModel.defaultSettings
            ) {
                appendToAssistantMessage(id: assistantID, content: token.text)
            }
            statusText = "Ready"
        } catch {
            appendToAssistantMessage(id: assistantID, content: "\n\n\(error.localizedDescription)")
            statusText = "Error"
        }

        isThinking = false
    }

    private func llmMessages() -> [LLMMessage] {
        messages.map { message in
            LLMMessage(
                role: message.role.llmRole,
                content: message.content
            )
        }
    }

    private func appendToAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += content
    }

    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }
}

enum SetupState {
    case checking
    case needsModel([ModelDescriptor])
    case downloading(ModelDescriptor, DownloadProgress)
    case loading(ModelDescriptor)
    case ready
    case failed(String)
}

struct DownloadProgress {
    var fraction: Double?
    var phaseLabel: String
    var message: String?

    init(
        fraction: Double? = nil,
        phaseLabel: String,
        message: String? = nil
    ) {
        self.fraction = fraction
        self.phaseLabel = phaseLabel
        self.message = message
    }

    init(progress: ModelDownloadProgress) {
        if let totalBytes = progress.totalBytes, totalBytes > 0 {
            fraction = min(1, Double(progress.completedBytes) / Double(totalBytes))
        } else {
            fraction = nil
        }

        phaseLabel = progress.phase.rawValue.capitalized
        message = progress.message
    }
}

struct ChatMessage: Identifiable, Equatable {
    var id = UUID()
    var role: ChatRole
    var content: String
}

enum ChatRole: Equatable {
    case user
    case assistant

    var displayName: String {
        switch self {
        case .user:
            "You"
        case .assistant:
            "Assistant"
        }
    }

    var llmRole: LLMMessage.Role {
        switch self {
        case .user:
            .user
        case .assistant:
            .assistant
        }
    }
}
