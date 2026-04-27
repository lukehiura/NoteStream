import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func mutateAllSegmentBuckets(
    _ transform: (TranscriptSegment) -> TranscriptSegment
  ) {
    committedSegments = committedSegments.map(transform)
    draftSegments = draftSegments.map(transform)
    liveTranscriptSegments = liveTranscriptSegments.map(transform)
  }
}
