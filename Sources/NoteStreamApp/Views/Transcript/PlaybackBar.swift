import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct PlaybackBar: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    HStack(spacing: 10) {
      Button {
        model.playback.playPause()
      } label: {
        Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(.bordered)

      Text(DurationFormatting.timestamp(model.playback.currentTime))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

      Slider(
        value: Binding(
          get: { model.playback.currentTime },
          set: { model.seekPlayback(to: $0) }
        ),
        in: 0...max(model.playback.duration, 0.001)
      )

      Text(DurationFormatting.timestamp(model.playback.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

      Picker(
        "Speed",
        selection: Binding(
          get: { model.playback.playbackRate },
          set: { model.playback.setRate($0) }
        )
      ) {
        Text("0.75x").tag(Float(0.75))
        Text("1x").tag(Float(1.0))
        Text("1.25x").tag(Float(1.25))
        Text("1.5x").tag(Float(1.5))
        Text("2x").tag(Float(2.0))
      }
      .frame(width: 90)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(AppSurface.card)
  }
}
