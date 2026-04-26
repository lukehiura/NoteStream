import XCTest

@testable import NoteStreamCore

final class TranscriptCoordinatorTests: XCTestCase {
  func testRecordingStoppedCommitsEverything() async throws {
    let coordinator = TranscriptCoordinator()

    let incoming = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "Hello", status: .draft),
      TranscriptSegment(startTime: 1, endTime: 2, text: "world", status: .draft),
    ]

    let update = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 2,
      segments: incoming,
      currentAudioTime: 2,
      boundary: .recordingStopped
    )

    XCTAssertTrue(update.draft.isEmpty)
    XCTAssertEqual(update.committed.map(\.text), ["Hello", "world"])
    XCTAssertEqual(update.lastCommittedEndTime, 2, accuracy: 0.0001)
    XCTAssertTrue(update.committed.allSatisfy { $0.status == .committed })
  }

  func testIgnoresSegmentsBeforeWatermark() async throws {
    let coordinator = TranscriptCoordinator()

    _ = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 10,
      segments: [
        TranscriptSegment(startTime: 0, endTime: 4, text: "A", status: .draft),
        TranscriptSegment(startTime: 4, endTime: 9, text: "B", status: .draft),
      ],
      currentAudioTime: 10,
      boundary: .recordingStopped
    )

    let update2 = await coordinator.ingestRollingSegments(
      chunkStart: 8,
      chunkEnd: 18,
      segments: [
        TranscriptSegment(startTime: 0, endTime: 2, text: "OLD", status: .draft),
        TranscriptSegment(startTime: 9, endTime: 12, text: "NEW", status: .draft),
      ],
      currentAudioTime: 18,
      boundary: .recordingStopped
    )

    XCTAssertFalse(update2.committed.map(\.text).contains("OLD"))
    XCTAssertTrue(update2.committed.map(\.text).contains("NEW"))
  }

  func testGapInsertionAdvancesWatermark() async throws {
    let coordinator = TranscriptCoordinator()
    let update = await coordinator.insertGap(start: 10, end: 12, reason: "audio_buffer_gap")
    XCTAssertEqual(update.committed.last?.status, .gap)
    XCTAssertEqual(update.lastCommittedEndTime, 12, accuracy: 0.0001)
  }

  func testDraftRemainsDraftBeforeCommitDelay() async throws {
    let coordinator = TranscriptCoordinator()
    let incoming = [
      TranscriptSegment(startTime: 0, endTime: 3, text: "Hello", status: .draft)
    ]

    let update = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 3,
      segments: incoming,
      currentAudioTime: 3,
      boundary: .vadPause,
      commitDelaySeconds: 5
    )

    XCTAssertTrue(update.committed.isEmpty)
    XCTAssertEqual(update.draft.count, 1)
    XCTAssertEqual(update.draft.first?.status, .draft)
  }

  func testVadPauseCommitsOnlyOlderSegments() async throws {
    let coordinator = TranscriptCoordinator()
    let incoming = [
      TranscriptSegment(startTime: 0, endTime: 2, text: "Old", status: .draft),
      TranscriptSegment(startTime: 2, endTime: 8, text: "Newer", status: .draft),
    ]

    let update = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 8,
      segments: incoming,
      currentAudioTime: 10,
      boundary: .vadPause,
      commitDelaySeconds: 5
    )

    XCTAssertTrue(update.committed.map(\.text).contains("Old"))
    XCTAssertTrue(update.draft.map(\.text).contains("Newer"))
  }

  func testEmptyTextIsIgnored() async throws {
    let coordinator = TranscriptCoordinator()
    let incoming = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "   ", status: .draft),
      TranscriptSegment(startTime: 1, endTime: 2, text: "Ok", status: .draft),
    ]
    let update = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 2,
      segments: incoming,
      currentAudioTime: 2,
      boundary: .recordingStopped
    )
    XCTAssertEqual(update.committed.map(\.text), ["Ok"])
  }

  func testOverlappingChunkDoesNotDuplicateCommittedText() async throws {
    let coordinator = TranscriptCoordinator()

    _ = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 10,
      segments: [
        TranscriptSegment(startTime: 0, endTime: 6, text: "A", status: .draft),
        TranscriptSegment(startTime: 6, endTime: 9, text: "B", status: .draft),
      ],
      currentAudioTime: 10,
      boundary: .recordingStopped
    )

    let update2 = await coordinator.ingestRollingSegments(
      chunkStart: 8,
      chunkEnd: 18,
      segments: [
        TranscriptSegment(startTime: 6, endTime: 9, text: "B", status: .draft),  // overlap
        TranscriptSegment(startTime: 9, endTime: 12, text: "C", status: .draft),
      ],
      currentAudioTime: 18,
      boundary: .recordingStopped
    )

    let committedText = update2.committed.map(\.text)
    XCTAssertEqual(committedText.filter { $0 == "B" }.count, 1)
    XCTAssertTrue(committedText.contains("C"))
  }

  func testForcedMaxDurationBehavesLikeVadPause() async throws {
    let coordinator = TranscriptCoordinator()
    let incoming = [
      TranscriptSegment(startTime: 0, endTime: 2, text: "Old", status: .draft),
      TranscriptSegment(startTime: 2, endTime: 8, text: "Newer", status: .draft),
    ]

    let update = await coordinator.ingestRollingSegments(
      chunkStart: 0,
      chunkEnd: 8,
      segments: incoming,
      currentAudioTime: 10,
      boundary: .forcedMaxDuration,
      commitDelaySeconds: 5
    )

    XCTAssertTrue(update.committed.map(\.text).contains("Old"))
    XCTAssertTrue(update.draft.map(\.text).contains("Newer"))
  }
}
