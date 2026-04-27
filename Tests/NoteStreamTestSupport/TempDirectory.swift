import Foundation

public enum TestTemp {
  /// Creates a unique directory under the system temp folder, then removes it when the block completes.
  @discardableResult
  public static func withTemporaryDirectory<T>(
    prefix: String = "NoteStream",
    _ body: (URL) async throws -> T
  ) async throws -> T {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try await body(url)
  }
}
