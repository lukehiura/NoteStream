import Testing

@testable import NoteStreamCore

@Test func recordingStoppedCommitsEverything() async throws {
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

  #expect(update.draft.isEmpty)
  #expect(update.committed.map(\.text) == ["Hello", "world"])
  #expect(abs(update.lastCommittedEndTime - 2) < 0.0001)
  #expect(update.committed.allSatisfy { $0.status == .committed })
}

@Test func ignoresSegmentsBeforeWatermark() async throws {
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

  #expect(!update2.committed.map(\.text).contains("OLD"))
  #expect(update2.committed.map(\.text).contains("NEW"))
}

@Test func gapInsertionAdvancesWatermark() async throws {
  let coordinator = TranscriptCoordinator()
  let update = await coordinator.insertGap(start: 10, end: 12, reason: "audio_buffer_gap")
  #expect(update.committed.last?.status == .gap)
  #expect(abs(update.lastCommittedEndTime - 12) < 0.0001)
}

@Test func draftRemainsDraftBeforeCommitDelay() async throws {
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

  #expect(update.committed.isEmpty)
  #expect(update.draft.count == 1)
  #expect(update.draft.first?.status == .draft)
}

@Test func vadPauseCommitsOnlyOlderSegments() async throws {
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

  // cutoff = 5 seconds => segment ending at 2 commits; segment ending at 8 remains draft
  #expect(update.committed.map(\.text).contains("Old"))
  #expect(update.draft.map(\.text).contains("Newer"))
}

@Test func emptyTextIsIgnored() async throws {
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
  #expect(update.committed.map(\.text) == ["Ok"])
}

@Test func overlappingChunkDoesNotDuplicateCommittedText() async throws {
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

  // "B" should not be re-appended
  let committedText = update2.committed.map(\.text)
  #expect(committedText.filter { $0 == "B" }.count == 1)
  #expect(committedText.contains("C"))
}

@Test func forcedMaxDurationBehavesLikeVadPause() async throws {
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

  #expect(update.committed.map(\.text).contains("Old"))
  #expect(update.draft.map(\.text).contains("Newer"))
}
