import Foundation
import MLXLLM
import MLXLMCommon
import MLXLMHuggingFace
import MLXLMTransformers
import Observation

@MainActor
@Observable
final class LocalModelStore {
    private enum DefaultsKeys {
        static let downloadedModelIDs = "BuddyGrammar.localModels.downloaded"
    }

    private enum LoadPurpose {
        case preload
        case rewrite
    }

    private let defaults: UserDefaults
    private let runtime: LocalModelRuntime
    private var downloadedModelIDs: Set<LocalModelID>
    private var preloadTask: Task<Void, Never>?

    var statuses: [LocalModelID: LocalModelStatus]
    var lastErrorMessage: String?

    init(defaults: UserDefaults = .standard, runtime: LocalModelRuntime = LocalModelRuntime()) {
        let downloadedModelIDs = Set(
            (defaults.array(forKey: DefaultsKeys.downloadedModelIDs) as? [String] ?? [])
                .compactMap(LocalModelID.init(rawValue:))
        )

        self.defaults = defaults
        self.runtime = runtime
        self.downloadedModelIDs = downloadedModelIDs
        self.statuses = Dictionary(
            uniqueKeysWithValues: LocalModelID.allCases.map { modelID in
                let status: LocalModelStatus = if downloadedModelIDs.contains(modelID) {
                    .init(state: .ready, progress: nil, errorMessage: nil)
                } else {
                    .notDownloaded
                }
                return (modelID, status)
            }
        )
    }

    func apply(settings: AppSettings) {
        guard case .local(let modelID) = settings.rewriteProvider else {
            lastErrorMessage = nil
            unloadCurrentModelIfNeeded()
            return
        }

        if settings.preloadLocalModelOnLaunch {
            preload(modelID: modelID, allowDownload: false)
        } else {
            Task {
                await transitionAwayFromLoadedModelIfNeeded(except: modelID)
            }
        }
    }

    func status(for modelID: LocalModelID) -> LocalModelStatus {
        statuses[modelID] ?? .notDownloaded
    }

    func preload(modelID: LocalModelID, allowDownload: Bool = true) {
        preloadTask?.cancel()
        if !allowDownload, !downloadedModelIDs.contains(modelID) {
            statuses[modelID] = .notDownloaded
            lastErrorMessage = nil
            return
        }
        preloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.loadContainer(for: modelID, purpose: .preload, allowDownload: allowDownload)
            } catch let failure as RewriteFailure {
                if !Task.isCancelled {
                    self.recordFailure(for: modelID, message: failure.errorDescription ?? "Could not load the local model.")
                }
            } catch {
                if !Task.isCancelled {
                    self.recordFailure(for: modelID, message: error.localizedDescription)
                }
            }
        }
    }

    func rewrite(_ request: RewriteRequest, modelID: LocalModelID) async throws -> RewriteResult {
        let container = try await loadContainer(for: modelID, purpose: .rewrite, allowDownload: true)
        let session = ChatSession(
            container,
            instructions: request.profile.instruction,
            generateParameters: modelID.generateParameters
        )

        do {
            let rawOutput = try await session.respond(to: request.selectedText)
            let sanitizedOutput = try RewriteOutputGuard.sanitize(rawOutput)
            markLoaded(modelID)
            lastErrorMessage = nil
            return RewriteResult(originalText: request.selectedText, rewrittenText: sanitizedOutput)
        } catch let failure as RewriteFailure {
            throw failure
        } catch {
            let message = "Local rewrite failed: \(error.localizedDescription)"
            recordFailure(for: modelID, message: message)
            throw RewriteFailure.localModel(message)
        }
    }

    private func loadContainer(
        for modelID: LocalModelID,
        purpose: LoadPurpose,
        allowDownload: Bool
    ) async throws -> ModelContainer {
        let previousLoadedModelID = await runtime.currentLoadedModelID()
        if let previousLoadedModelID, previousLoadedModelID != modelID {
            setReadyIfDownloaded(previousLoadedModelID)
        }

        if !downloadedModelIDs.contains(modelID), !allowDownload {
            statuses[modelID] = .notDownloaded
            return try await runtime.ensureUnavailable(modelID: modelID)
        }

        let currentState = status(for: modelID).state
        if currentState != .loaded {
            statuses[modelID] = .init(
                state: downloadedModelIDs.contains(modelID) ? .loading : .downloading,
                progress: downloadedModelIDs.contains(modelID) ? nil : 0,
                errorMessage: nil
            )
        }

        do {
            let container = try await runtime.ensureLoaded(modelID: modelID) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    let state: LocalModelState = self.downloadedModelIDs.contains(modelID) ? .loading : .downloading
                    self.statuses[modelID] = .init(
                        state: state,
                        progress: progress.fractionCompleted > 0 ? progress.fractionCompleted : nil,
                        errorMessage: nil
                    )
                }
            }

            if purpose == .preload || currentState != .loaded {
                markLoaded(modelID)
            }
            return container
        } catch {
            let message = "Could not load \(modelID.title): \(error.localizedDescription)"
            recordFailure(for: modelID, message: message)
            throw RewriteFailure.localModel(message)
        }
    }

    private func unloadCurrentModelIfNeeded() {
        preloadTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            if let loadedModelID = await runtime.currentLoadedModelID() {
                await runtime.unload()
                await MainActor.run {
                    self.setReadyIfDownloaded(loadedModelID)
                }
            }
        }
    }

    private func transitionAwayFromLoadedModelIfNeeded(except modelID: LocalModelID) async {
        guard let loadedModelID = await runtime.currentLoadedModelID(), loadedModelID != modelID else {
            return
        }
        await runtime.unload()
        await MainActor.run {
            self.setReadyIfDownloaded(loadedModelID)
        }
    }

    private func markLoaded(_ modelID: LocalModelID) {
        downloadedModelIDs.insert(modelID)
        persistDownloadedModelIDs()
        statuses[modelID] = .init(state: .loaded, progress: nil, errorMessage: nil)
        lastErrorMessage = nil
    }

    private func setReadyIfDownloaded(_ modelID: LocalModelID) {
        if downloadedModelIDs.contains(modelID) {
            statuses[modelID] = .init(state: .ready, progress: nil, errorMessage: nil)
        } else {
            statuses[modelID] = .notDownloaded
        }
    }

    private func recordFailure(for modelID: LocalModelID, message: String) {
        statuses[modelID] = .init(state: .failed, progress: nil, errorMessage: message)
        lastErrorMessage = message
    }

    private func persistDownloadedModelIDs() {
        defaults.set(downloadedModelIDs.map(\.rawValue).sorted(), forKey: DefaultsKeys.downloadedModelIDs)
    }
}

extension LocalModelID {
    var generateParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: 96,
            temperature: 0,
            topP: 1,
            topK: 0,
            repetitionPenalty: nil,
            prefillStepSize: 512
        )
    }
}

actor LocalMLXRewriteEngine: RewriteEngine {
    private let localModelStore: LocalModelStore
    private let modelID: LocalModelID

    init(localModelStore: LocalModelStore, modelID: LocalModelID) {
        self.localModelStore = localModelStore
        self.modelID = modelID
    }

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        try await localModelStore.rewrite(request, modelID: modelID)
    }
}

actor LocalModelRuntime {
    private var activeModelID: LocalModelID?
    private var loadedContainer: ModelContainer?

    func currentLoadedModelID() -> LocalModelID? {
        activeModelID
    }

    func unload() {
        activeModelID = nil
        loadedContainer = nil
    }

    func ensureUnavailable(modelID: LocalModelID) throws -> ModelContainer {
        if activeModelID == modelID, let loadedContainer {
            return loadedContainer
        }
        throw RewriteFailure.localModel(
            "\(modelID.title) is not downloaded yet. Warm load it from Settings first."
        )
    }

    func ensureLoaded(
        modelID: LocalModelID,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> ModelContainer {
        if activeModelID == modelID, let loadedContainer {
            return loadedContainer
        }

        let container = try await loadModelContainer(
            from: HubClient.default,
            id: modelID.repositoryID,
            progressHandler: progressHandler
        )
        activeModelID = modelID
        loadedContainer = container
        return container
    }
}
