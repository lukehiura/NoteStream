import Foundation
import XCTest

@testable import NoteStreamCore
@testable import NoteStreamInfrastructure

final class FileSessionStoreTests: XCTestCase {
  func testSaveLoadListDeleteSession() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = try FileSessionStore(baseURL: tmp)

    let session = LectureSession(
      title: "Test Lecture",
      sourceFileName: "test.m4a",
      model: "base.en",
      segments: [
        TranscriptSegment(startTime: 0, endTime: 1, text: "Hello", status: .committed),
        TranscriptSegment(startTime: 1, endTime: 2, text: "world", status: .committed),
      ]
    )

    try await store.save(session)

    let folder = tmp.appendingPathComponent(session.id.uuidString, isDirectory: true)
    let notesURL = folder.appendingPathComponent(SessionFileLayout.notesMarkdown)
    XCTAssertFalse(FileManager.default.fileExists(atPath: notesURL.path))

    let loaded = try await store.load(id: session.id)
    XCTAssertEqual(loaded.id, session.id)
    XCTAssertEqual(loaded.title, "Test Lecture")
    XCTAssertEqual(loaded.segments.count, 2)
    XCTAssertEqual(loaded.metadata.schemaVersion, SessionFileSchema.current)

    let all = try await store.list()
    XCTAssertTrue(all.contains(where: { $0.id == session.id }))

    try await store.delete(id: session.id)
    let afterDelete = try await store.list()
    XCTAssertFalse(afterDelete.contains(where: { $0.id == session.id }))
  }

  func testSaveWritesNotesMarkdownFile() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = try FileSessionStore(baseURL: tmp)

    var session = LectureSession(
      title: "With Notes",
      sourceFileName: "test.m4a",
      model: "base.en",
      segments: [
        TranscriptSegment(startTime: 0, endTime: 1, text: "Hello", status: .committed)
      ]
    )
    session.notesMarkdown = "## Summary\nHello world."

    try await store.save(session)

    let folder = tmp.appendingPathComponent(session.id.uuidString, isDirectory: true)
    let notesURL = folder.appendingPathComponent(SessionFileLayout.notesMarkdown)
    XCTAssertTrue(FileManager.default.fileExists(atPath: notesURL.path))
    let data = try Data(contentsOf: notesURL)
    let text = String(data: data, encoding: .utf8)
    XCTAssertEqual(text, "## Summary\nHello world.")
  }

  func testRecoverableAudioFilesListsIncompleteSessions() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = try FileSessionStore(baseURL: tmp)

    let incompleteID = UUID()
    let incompleteFolder = tmp.appendingPathComponent(incompleteID.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: incompleteFolder, withIntermediateDirectories: true)
    let danglingAudio = incompleteFolder.appendingPathComponent(SessionFileLayout.audioCAF)
    try Data([0x00]).write(to: danglingAudio)

    let session = LectureSession(
      title: "Complete",
      sourceFileName: "test.m4a",
      model: "base.en",
      segments: [
        TranscriptSegment(startTime: 0, endTime: 1, text: "Done", status: .committed)
      ]
    )
    try await store.save(session)

    let recovered = try await store.recoverableAudioFiles()
    XCTAssertEqual(recovered.count, 1)
    XCTAssertEqual(
      recovered[0].resolvingSymlinksInPath().path,
      danglingAudio.resolvingSymlinksInPath().path
    )

    let emptyTmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamTests-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyTmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: emptyTmp) }
    let emptyStore = try FileSessionStore(baseURL: emptyTmp)
    let recoveredEmpty = try await emptyStore.recoverableAudioFiles()
    XCTAssertTrue(recoveredEmpty.isEmpty)
  }
}
