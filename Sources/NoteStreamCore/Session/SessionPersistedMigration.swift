import Foundation

/// Normalizes sessions loaded from disk before they enter the view model.
public enum SessionPersistedMigration {
  /// Apply migrations when `session.metadata.schemaVersion` is below `SessionFileSchema.current`.
  public static func migrateLoadedSession(_ session: LectureSession) -> LectureSession {
    var session = session
    let from = session.metadata.schemaVersion
    guard from < SessionFileSchema.current else {
      return session
    }

    // Future versions: branch on `from` and apply transforms before bumping.

    session.metadata.schemaVersion = SessionFileSchema.current
    return session
  }
}
