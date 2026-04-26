import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackController {
  @ObservationIgnored private var player: AVPlayer?
  @ObservationIgnored private var timeObserver: Any?

  var audioURL: URL?
  var isPlaying: Bool = false
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var playbackRate: Float = 1.0

  func load(url: URL) {
    cleanup()

    audioURL = url
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer

    Task {
      let seconds = try? await item.asset.load(.duration).seconds
      await MainActor.run {
        self.duration = (seconds?.isFinite == true) ? (seconds ?? 0) : 0
      }
    }

    addTimeObserver()
  }

  func playPause() {
    guard let player else { return }

    if isPlaying {
      player.pause()
      isPlaying = false
    } else {
      player.rate = playbackRate
      player.play()
      isPlaying = true
    }
  }

  func seek(to seconds: TimeInterval) {
    guard let player else { return }

    let maxT = duration > 0 ? duration : seconds
    let clamped = max(0, min(seconds, maxT))
    let time = CMTime(seconds: clamped, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    currentTime = clamped
  }

  func setRate(_ rate: Float) {
    playbackRate = rate
    if isPlaying {
      player?.rate = rate
    }
  }

  func cleanup() {
    if let timeObserver, let player {
      player.removeTimeObserver(timeObserver)
    }

    timeObserver = nil
    player?.pause()
    player = nil
    isPlaying = false
    currentTime = 0
    duration = 0
    audioURL = nil
  }

  private func addTimeObserver() {
    guard let player else { return }

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        self?.currentTime = time.seconds
      }
    }
  }
}
