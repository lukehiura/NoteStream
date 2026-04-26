import Foundation
import NoteStreamCore

public actor FileDiagnosticsLogger: DiagnosticsLogging {
  private let logURL: URL
  private let maxBytes: UInt64
  private let maxRotatedFiles: Int
  private let encoder = JSONEncoder()

  public init(
    logURL: URL,
    maxBytes: UInt64 = 5_000_000,
    maxRotatedFiles: Int = 5
  ) {
    self.logURL = logURL
    self.maxBytes = maxBytes
    self.maxRotatedFiles = max(1, maxRotatedFiles)
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
  }

  public func log(_ event: DiagnosticsEvent) async {
    do {
      try FileManager.default.createDirectory(
        at: logURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      try rotateIfNeeded()

      let safeEvent = DiagnosticsRedactor.sanitize(event)

      let data = try encoder.encode(safeEvent)
      var line = data
      line.append(0x0A)

      if FileManager.default.fileExists(atPath: logURL.path) {
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
      } else {
        try line.write(to: logURL, options: .atomic)
      }
    } catch {
      #if DEBUG
        print("[Diagnostics] Failed to write log: \(error)")
      #endif
    }
  }

  private func rotateIfNeeded() throws {
    guard FileManager.default.fileExists(atPath: logURL.path) else { return }

    let attrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
    let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    guard size >= maxBytes else { return }

    let oldest = rotatedURL(maxRotatedFiles)
    if FileManager.default.fileExists(atPath: oldest.path) {
      try? FileManager.default.removeItem(at: oldest)
    }

    for index in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
      let src = rotatedURL(index)
      let dst = rotatedURL(index + 1)
      guard FileManager.default.fileExists(atPath: src.path) else { continue }
      if FileManager.default.fileExists(atPath: dst.path) {
        try? FileManager.default.removeItem(at: dst)
      }
      try FileManager.default.moveItem(at: src, to: dst)
    }

    let first = rotatedURL(1)
    if FileManager.default.fileExists(atPath: first.path) {
      try? FileManager.default.removeItem(at: first)
    }
    try FileManager.default.moveItem(at: logURL, to: first)
  }

  private func rotatedURL(_ index: Int) -> URL {
    let dir = logURL.deletingLastPathComponent()
    let baseName = logURL.deletingPathExtension().lastPathComponent
    let ext = logURL.pathExtension
    return dir.appendingPathComponent("\(baseName).\(index)").appendingPathExtension(ext)
  }
}
