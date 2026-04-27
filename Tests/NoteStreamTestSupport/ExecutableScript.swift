import Foundation

public enum TestScript {
  public static func writeExecutable(directory: URL, name: String, contents: String) throws -> URL {
    let fileURL = directory.appendingPathComponent(name)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
    return fileURL
  }
}
