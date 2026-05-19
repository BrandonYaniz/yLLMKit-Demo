import Combine
import Foundation
import yLLMKit
import yLLMKitMLX

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var setupState: SetupState = .checking
    @Published private(set) var supportedModels: [ModelDescriptor] = []
    @Published private(set) var localModels: [LocalModel] = []
    @Published private(set) var modelDownloads: [String: DownloadProgress] = [:]
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draftMessage = ""
    @Published private(set) var isThinking = false
    @Published private(set) var statusText = "Ready"

    private var runtime: LLMRuntime?
    private var session: (any LLMSession)?
    private var activeModel: ModelDescriptor?
    private var setupTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    var activeModelName: String {
        activeModel?.displayName ?? "No model loaded"
    }

    var activeModelID: String? {
        activeModel?.id
    }

    var installedModelIDs: Set<String> {
        Set(localModels.map(\.modelID))
    }

    var installedModels: [ModelDescriptor] {
        supportedModels.filter { installedModelIDs.contains($0.id) }
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

    func downloadModel(_ model: ModelDescriptor) {
        guard downloadTasks[model.id] == nil else { return }
        downloadTasks[model.id] = Task {
            await downloadModel(model, loadWhenComplete: activeModel == nil)
            downloadTasks[model.id] = nil
        }
    }

    func switchModel(to model: ModelDescriptor) {
        guard model.id != activeModel?.id, installedModelIDs.contains(model.id), !isThinking else { return }
        setupTask?.cancel()
        setupTask = Task {
            await loadInstalledModel(model)
        }
    }

    func removeModel(_ model: ModelDescriptor) {
        guard !isThinking else { return }
        setupTask?.cancel()
        setupTask = Task {
            await removeInstalledModel(model)
        }
    }

    func isModelInstalled(_ model: ModelDescriptor) -> Bool {
        installedModelIDs.contains(model.id)
    }

    func isDownloading(_ model: ModelDescriptor) -> Bool {
        modelDownloads[model.id] != nil
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

            supportedModels = await runtime.supportedModels()
            try await refreshLocalModels(runtime: runtime)
            let installedModel = firstInstalledModel()

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
                let downloadProgress = DownloadProgress(progress: progress)
                modelDownloads[model.id] = downloadProgress
                setupState = .downloading(model, downloadProgress)
            }

            modelDownloads[model.id] = nil
            try await refreshLocalModels(runtime: runtime)
            try await load(model: model, runtime: runtime)
        } catch {
            modelDownloads[model.id] = nil
            setupState = .failed(error.localizedDescription)
        }
    }

    private func downloadModel(_ model: ModelDescriptor, loadWhenComplete: Bool) async {
        do {
            let runtime = try runtime ?? makeRuntime()
            self.runtime = runtime

            modelDownloads[model.id] = DownloadProgress(phaseLabel: "Queued")
            let stream = try await runtime.downloadAndInstallModel(id: model.id)
            for try await progress in stream {
                modelDownloads[model.id] = DownloadProgress(progress: progress)
            }

            modelDownloads[model.id] = nil
            try await refreshLocalModels(runtime: runtime)

            if loadWhenComplete {
                try await load(model: model, runtime: runtime)
            }
        } catch {
            modelDownloads[model.id] = nil
            setupState = .failed(error.localizedDescription)
        }
    }

    private func loadInstalledModel(_ model: ModelDescriptor) async {
        do {
            let runtime = try runtime ?? makeRuntime()
            self.runtime = runtime
            try await load(model: model, runtime: runtime)
        } catch {
            setupState = .failed(error.localizedDescription)
        }
    }

    private func removeInstalledModel(_ model: ModelDescriptor) async {
        do {
            let runtime = try runtime ?? makeRuntime()
            self.runtime = runtime

            if model.id == activeModel?.id {
                session?.cancel()
                session = nil
                activeModel = nil
                messages.removeAll()
                statusText = "Ready"
            }

            try await runtime.removeModel(id: model.id)
            try await refreshLocalModels(runtime: runtime)

            if activeModel == nil {
                if let nextModel = firstInstalledModel() {
                    try await load(model: nextModel, runtime: runtime)
                } else {
                    setupState = .needsModel(supportedModels)
                }
            }
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

    private func refreshLocalModels(runtime: LLMRuntime) async throws {
        localModels = try await runtime.localModels()
    }

    private func firstInstalledModel() -> ModelDescriptor? {
        supportedModels.first { installedModelIDs.contains($0.id) }
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
        if let fractionCompleted = progress.fractionCompleted,
           fractionCompleted.isFinite {
            fraction = min(1, max(0, fractionCompleted))
        } else if let totalBytes = progress.totalBytes,
                  let completedBytes = progress.completedBytes,
                  totalBytes > 0,
                  completedBytes > 0,
                  completedBytes <= totalBytes {
            fraction = min(1, Double(completedBytes) / Double(totalBytes))
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
