import Foundation

public protocol AudioRecorder: Sendable {
  func audioFrames() async -> AsyncStream<AudioFrame>
  func startRecording(outputURL: URL) async throws -> RecordingSession
  func stopRecording() async throws -> URL
}
