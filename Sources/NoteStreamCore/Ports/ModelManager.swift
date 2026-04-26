import Foundation

public enum ModelLifecycleState: Sendable, Equatable {
  case idle
  case downloading(fraction: Double?)
  case loading
  case ready
  case failed(message: String)
}

public struct ModelStatus: Sendable, Equatable {
  public var model: String
  public var state: ModelLifecycleState
  public var detail: String?

  public init(model: String, state: ModelLifecycleState, detail: String? = nil) {
    self.model = model
    self.state = state
    self.detail = detail
  }
}

public protocol ModelManaging: Sendable {
  func statusUpdates() async -> AsyncStream<ModelStatus>
  func prepare(model: String) async
  func retry(model: String) async
  func clearModelCache() async throws
}
