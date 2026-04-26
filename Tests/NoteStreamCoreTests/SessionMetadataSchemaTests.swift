import Foundation
import XCTest

@testable import NoteStreamCore

final class SessionMetadataSchemaTests: XCTestCase {
  func testSessionMetadataDecodesMissingSchemaAsVersion1() throws {
    let json = """
      {
        "appVersion" : "1.0",
        "createdAt" : "2024-01-01T12:00:00Z",
        "updatedAt" : "2024-01-01T12:00:00Z"
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let meta = try decoder.decode(SessionMetadata.self, from: Data(json.utf8))
    XCTAssertEqual(meta.schemaVersion, 1)
  }

  func testSessionMetadataEncodesSchemaVersion() throws {
    var meta = SessionMetadata()
    meta.schemaVersion = 1
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(meta)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(obj?["schemaVersion"] as? Int, 1)
  }
}
