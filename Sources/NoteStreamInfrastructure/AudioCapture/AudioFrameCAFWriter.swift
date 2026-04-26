import AVFoundation
import Foundation
import NoteStreamCore

/// Writes a contiguous sequence of ``AudioFrame``s to a Core Audio File (mono Float32 PCM).
public enum AudioFrameCAFWriter {
  public static func write(frames: [AudioFrame], to url: URL) throws {
    guard let first = frames.first else {
      throw NSError(
        domain: "NoteStream", code: 150,
        userInfo: [NSLocalizedDescriptionKey: "No audio frames to write."]
      )
    }

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Double(first.sampleRateHz),
      channels: AVAudioChannelCount(max(1, first.channelCount)),
      interleaved: false
    )

    guard let format else {
      throw NSError(
        domain: "NoteStream", code: 151,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat."]
      )
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)

    for frame in frames {
      guard frame.sampleRateHz == first.sampleRateHz,
        frame.channelCount == first.channelCount
      else { continue }

      let frameCount = AVAudioFrameCount(frame.samples.count / max(1, frame.channelCount))
      guard frameCount > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
      else { continue }

      buffer.frameLength = frameCount

      if frame.channelCount <= 1 {
        guard let channel = buffer.floatChannelData?[0] else { continue }
        frame.samples.withUnsafeBufferPointer { src in
          guard let base = src.baseAddress else { return }
          channel.update(from: base, count: Int(frameCount))
        }
      } else {
        for channelIndex in 0..<frame.channelCount {
          guard let channel = buffer.floatChannelData?[channelIndex] else { continue }
          for sampleIndex in 0..<Int(frameCount) {
            channel[sampleIndex] =
              frame.samples[sampleIndex * frame.channelCount + channelIndex]
          }
        }
      }

      try file.write(from: buffer)
    }
  }
}
