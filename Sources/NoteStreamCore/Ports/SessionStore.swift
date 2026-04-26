import Foundation

public protocol SessionStore: Sendable {
  func save(_ session: LectureSession) async throws
  func load(id: UUID) async throws -> LectureSession
  func list() async throws -> [LectureSession]
  func delete(id: UUID) async throws
  func sessionFolderURL(id: UUID) async throws -> URL
  /// Session folders that contain `audio.caf` but no `session.json` (e.g. crash before save).
  func recoverableAudioFiles() async throws -> [URL]
}
