import Foundation
import Testing

@testable import NoteStreamCore

@Test func sessionMetadataDecodesMissingSchemaAsVersion1() throws {
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
  #expect(meta.schemaVersion == 1)
}

@Test func sessionMetadataEncodesSchemaVersion() throws {
  var meta = SessionMetadata()
  meta.schemaVersion = 1
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  let data = try encoder.encode(meta)
  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
  #expect(obj?["schemaVersion"] as? Int == 1)
}
