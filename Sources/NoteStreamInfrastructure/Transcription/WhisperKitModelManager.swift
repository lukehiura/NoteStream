import Foundation
import Hub
import NoteStreamCore
import WhisperKit

public final class WhisperKitModelManager: @unchecked Sendable, ModelManaging {
  private let state = StateActor()
  private let diagnostics: any DiagnosticsLogging

  public init(diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()) {
    self.diagnostics = diagnostics
    Task { await state.setDiagnostics(diagnostics) }
  }

  public func statusUpdates() async -> AsyncStream<ModelStatus> {
    await state.statusUpdates()
  }

  public func prepare(model: String) async {
    await diagnostics.log(
      .init(
        level: .info, category: "model", message: "model_prepare_requested",
        metadata: ["model": model]))
    do { _ = try await getPipe(model: model) } catch {
      // Status already published via state.
    }
  }

  public func retry(model: String) async {
    await diagnostics.log(
      .init(
        level: .info, category: "model", message: "model_retry_requested",
        metadata: ["model": model]))
    await state.reset(to: model)
    await prepare(model: model)
  }

  public func clearModelCache() async throws {
    await diagnostics.log(.init(level: .warning, category: "model", message: "model_cache_cleared"))
    try await state.clearModelCache()
  }

  public func getPipe(model: String) async throws -> WhisperKit {
    try await state.getPipe(model: model)
  }
}

private actor StateActor {
  private let repoId = "argmaxinc/whisperkit-coreml"
  private var pipe: WhisperKit?
  private var currentModel: String?

  private var continuations: [UUID: AsyncStream<ModelStatus>.Continuation] = [:]
  private var lastStatus: ModelStatus = ModelStatus(model: "base.en", state: .idle)
  private var diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()
  private var inFlightTask: Task<WhisperKit, Error>?
  private var inFlightModel: String?
  private var queuedModel: String?

  func setDiagnostics(_ diagnostics: any DiagnosticsLogging) {
    self.diagnostics = diagnostics
  }

  func statusUpdates() -> AsyncStream<ModelStatus> {
    AsyncStream { continuation in
      let id = UUID()
      continuations[id] = continuation
      continuation.yield(lastStatus)
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { await self?.removeContinuation(id: id) }
      }
    }
  }

  private func removeContinuation(id: UUID) {
    continuations.removeValue(forKey: id)
  }

  func reset(to model: String) async {
    inFlightTask?.cancel()
    inFlightTask = nil
    inFlightModel = nil
    queuedModel = nil
    pipe = nil
    currentModel = nil
    await publish(ModelStatus(model: model, state: .idle))
  }

  func clearModelCache() async throws {
    inFlightTask?.cancel()
    inFlightTask = nil
    inFlightModel = nil
    queuedModel = nil
    pipe = nil
    currentModel = nil

    let hubApi = HubApi()
    let repo = Hub.Repo(id: repoId, type: .models)
    let repoURL = hubApi.localRepoLocation(repo)
    if FileManager.default.fileExists(atPath: repoURL.path) {
      try FileManager.default.removeItem(at: repoURL)
    }
    await publish(ModelStatus(model: lastStatus.model, state: .idle, detail: "Cache cleared"))
  }

  // swiftlint:disable:next function_body_length
  func getPipe(model: String) async throws -> WhisperKit {
    while true {
      if let pipe, currentModel == model { return pipe }

      // If we already have an in-flight install for this model, await it.
      if let task = inFlightTask, inFlightModel == model {
        return try await task.value
      }

      // If some other model is currently installing, queue this request.
      if inFlightTask != nil, inFlightModel != nil, inFlightModel != model {
        queuedModel = model
        await diagnostics.log(
          .init(
            level: .info, category: "model", message: "model_install_queued",
            metadata: [
              "model": model,
              "installing": inFlightModel ?? "unknown",
            ]))
        await publish(
          ModelStatus(
            model: model,
            state: .downloading(fraction: nil),
            detail: "Queued (installing \(inFlightModel ?? "another model") first)…"
          )
        )

        // If this call needs the pipe now, wait for the current install to finish and loop.
        if let task = inFlightTask {
          _ = try? await task.value
        }
        continue
      }

      // Start a new install task (single-flight).
      inFlightModel = model
      let task = Task<WhisperKit, Error> {
        await diagnostics.log(
          .init(
            level: .info, category: "model", message: "model_download_started",
            metadata: ["model": model]))
        await publish(
          ModelStatus(
            model: model, state: .downloading(fraction: nil), detail: "Installing speech model…"))

        let downloadedFolder: URL
        do {
          downloadedFolder = try await WhisperKit.download(
            variant: model,
            useBackgroundSession: false,
            from: repoId,
            token: nil,
            progressCallback: { progress in
              Task {
                let fraction = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
                await self.diagnostics.log(
                  .init(
                    level: .debug, category: "model", message: "model_download_progress",
                    metadata: [
                      "model": model,
                      "fraction": fraction.map { "\($0)" } ?? "nil",
                    ]))
                await self.publish(
                  ModelStatus(
                    model: model,
                    state: .downloading(fraction: fraction),
                    detail: progress.localizedDescription
                  )
                )
              }
            }
          )
        } catch {
          await diagnostics.log(
            .init(
              level: .error, category: "model", message: "model_download_failed",
              metadata: ["model": model, "error": String(describing: error)]))
          await publish(
            ModelStatus(model: model, state: .failed(message: String(describing: error))))
          throw error
        }

        await diagnostics.log(
          .init(
            level: .info, category: "model", message: "model_download_completed",
            metadata: ["model": model]))
        await publish(
          ModelStatus(model: model, state: .loading, detail: "Loading speech model into memory…"))
        await diagnostics.log(
          .init(
            level: .info, category: "model", message: "model_load_started",
            metadata: ["model": model]))

        do {
          let t0 = Date()
          let config = WhisperKitConfig(
            modelFolder: downloadedFolder.path,
            verbose: false,
            load: true,
            download: false
          )
          let created = try await WhisperKit(config)
          let dt = Date().timeIntervalSince(t0)
          await diagnostics.log(
            .init(
              level: .info, category: "model", message: "model_load_completed",
              metadata: ["model": model, "loadSeconds": "\(dt)"]))
          return created
        } catch {
          await diagnostics.log(
            .init(
              level: .error, category: "model", message: "model_load_failed",
              metadata: ["model": model, "error": String(describing: error)]))
          throw error
        }
      }

      inFlightTask = task

      do {
        let created = try await task.value
        pipe = created
        currentModel = model
        await publish(ModelStatus(model: model, state: .ready, detail: "Speech model ready"))
        inFlightTask = nil
        inFlightModel = nil

        // If something was queued while we installed, kick it off in the background.
        if let next = queuedModel, next != currentModel {
          queuedModel = nil
          Task { _ = try? await self.getPipe(model: next) }
        }

        return created
      } catch {
        pipe = nil
        currentModel = nil
        inFlightTask = nil
        inFlightModel = nil
        await publish(ModelStatus(model: model, state: .failed(message: String(describing: error))))

        // If something was queued, let it proceed.
        if let next = queuedModel, next != model {
          queuedModel = nil
          Task { _ = try? await self.getPipe(model: next) }
        }

        throw error
      }
    }
  }

  private func publish(_ status: ModelStatus) async {
    lastStatus = status
    for c in continuations.values { c.yield(status) }
  }
}
