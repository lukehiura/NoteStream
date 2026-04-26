import Foundation

enum DiarizationCredentialStore {
  static let service = "NoteStream"
  static let huggingFaceAccount = "diarization.huggingFaceToken"

  static func readHuggingFaceToken() -> String? {
    KeychainStore.read(
      service: service,
      account: huggingFaceAccount
    )?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func saveHuggingFaceToken(_ token: String) throws {
    try KeychainStore.save(
      token.trimmingCharacters(in: .whitespacesAndNewlines),
      service: service,
      account: huggingFaceAccount
    )
  }

  static func clearHuggingFaceToken() {
    KeychainStore.delete(
      service: service,
      account: huggingFaceAccount
    )
  }
}
