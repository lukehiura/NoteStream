import AVFAudio
import CoreMedia
import Foundation
import NoteStreamCore

/// A stateful audio converter that safely extracts `CMSampleBuffer`s and
/// performs hardware-accelerated downmixing and anti-aliased resampling.
public final class AudioResampler: @unchecked Sendable {
  private var converter: AVAudioConverter?
  private var inputFormat: AVAudioFormat?
  private let outputFormat: AVAudioFormat

  public init() {
    // Whisper demands 16kHz, Mono, Float32.
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    else {
      fatalError("Failed to build required 16kHz mono float output format.")
    }
    self.outputFormat = outputFormat
  }

  public func process(sampleBuffer: CMSampleBuffer) -> AudioFrame? {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    let currentInputFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)

    let inputFrameCount = AVAudioFrameCount(sampleBuffer.numSamples)
    guard
      let inputPCMBuffer = AVAudioPCMBuffer(
        pcmFormat: currentInputFormat,
        frameCapacity: inputFrameCount
      )
    else { return nil }

    inputPCMBuffer.frameLength = inputPCMBuffer.frameCapacity
    CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(sampleBuffer.numSamples),
      into: inputPCMBuffer.mutableAudioBufferList
    )

    // If the stream format changes (e.g. device route changes), rebuild the converter.
    if converter == nil || inputFormat != currentInputFormat {
      inputFormat = currentInputFormat
      converter = AVAudioConverter(from: currentInputFormat, to: outputFormat)
    }
    guard let converter else { return nil }

    let sampleRateRatio = outputFormat.sampleRate / currentInputFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(inputPCMBuffer.frameLength) * sampleRateRatio) + 1024
    guard let outputPCMBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
    else {
      return nil
    }

    var error: NSError?
    var allConsumed = false

    let status = converter.convert(to: outputPCMBuffer, error: &error) { _, outStatus in
      if allConsumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      allConsumed = true
      outStatus.pointee = .haveData
      return inputPCMBuffer
    }

    if status == .error || error != nil {
      return nil
    }

    guard let channelData = outputPCMBuffer.floatChannelData else { return nil }
    let frameCount = Int(outputPCMBuffer.frameLength)
    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

    return AudioFrame(
      startTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
      samples: samples,
      sampleRateHz: 16_000,
      channelCount: 1
    )
  }
}
