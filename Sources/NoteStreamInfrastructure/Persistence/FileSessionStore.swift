import Foundation
import NoteStreamCore

public actor FileSessionStore: SessionStore {
  private let baseURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(baseURL: URL? = nil) throws {
    if let baseURL {
      self.baseURL = baseURL
    } else {
      let docs = try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      self.baseURL =
        docs
        .appendingPathComponent(SessionFileLayout.rootFolderName, isDirectory: true)
        .appendingPathComponent(SessionFileLayout.sessionsFolderName, isDirectory: true)
    }

    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func save(_ session: LectureSession) async throws {
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

    let folder = baseURL.appendingPathComponent(session.id.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let jsonURL = folder.appendingPathComponent(SessionFileLayout.sessionJSON)
    let mdURL = folder.appendingPathComponent(SessionFileLayout.transcriptMarkdown)

    let jsonData = try encoder.encode(session)
    try jsonData.write(to: jsonURL, options: .atomic)

    let markdown = TranscriptMarkdownFormatter.markdown(from: session.segments)
    guard let mdData = markdown.data(using: .utf8) else {
      throw NoteStreamError.utf8EncodingFailed("transcript markdown")
    }
    try mdData.write(to: mdURL, options: .atomic)

    if let notes = session.notesMarkdown,
      !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let notesURL = folder.appendingPathComponent(SessionFileLayout.notesMarkdown)

      guard let notesData = notes.data(using: .utf8) else {
        throw NoteStreamError.utf8EncodingFailed("notes markdown")
      }

      try notesData.write(to: notesURL, options: .atomic)
    }
  }

  public func load(id: UUID) async throws -> LectureSession {
    let folder = baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
    let jsonURL = folder.appendingPathComponent(SessionFileLayout.sessionJSON)
    let data = try Data(contentsOf: jsonURL)
    let session = try decoder.decode(LectureSession.self, from: data)
    return SessionPersistedMigration.migrateLoadedSession(session)
  }

  public func list() async throws -> [LectureSession] {
    guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
    let entries = try FileManager.default.contentsOfDirectory(
      at: baseURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    var sessions: [LectureSession] = []
    for dir in entries where dir.hasDirectoryPath {
      let jsonURL = dir.appendingPathComponent(SessionFileLayout.sessionJSON)
      guard FileManager.default.fileExists(atPath: jsonURL.path) else { continue }
      if let data = try? Data(contentsOf: jsonURL),
        let session = try? decoder.decode(LectureSession.self, from: data)
      {
        sessions.append(SessionPersistedMigration.migrateLoadedSession(session))
      }
    }

    return sessions.sorted(by: { $0.createdAt > $1.createdAt })
  }

  public func delete(id: UUID) async throws {
    let folder = baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
  }

  public func sessionFolderURL(id: UUID) async throws -> URL {
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    let folder = baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  public func recoverableAudioFiles() async throws -> [URL] {
    guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }

    let dirs = try FileManager.default.contentsOfDirectory(
      at: baseURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    var results: [URL] = []

    for dir in dirs where dir.hasDirectoryPath {
      let audioURL = dir.appendingPathComponent(SessionFileLayout.audioCAF)
      let jsonURL = dir.appendingPathComponent(SessionFileLayout.sessionJSON)

      if FileManager.default.fileExists(atPath: audioURL.path),
        !FileManager.default.fileExists(atPath: jsonURL.path)
      {
        results.append(audioURL)
      }
    }

    return results
  }
}
