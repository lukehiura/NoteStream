import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptView: View {
  @Bindable var model: TranscriptionViewModel
  @Binding var followTail: Bool
  @Binding var showingNotesPanel: Bool
  @Binding var copiedTranscript: Bool
  let onRenameSpeaker: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      if model.liveCaptureShowsBlockedAudioBanner {
        audioCaptureBlockedBanner
      }

      if model.liveCaptureShowsRecordingChrome, model.allSegments.isEmpty {
        recordingView
      } else if model.allSegments.isEmpty {
        dropZone
          .padding(.top, 40)
      } else {
        transcriptToolbar
        debugSpeakerLabelsBanner
        Divider()
        if model.playback.audioURL != nil {
          PlaybackBar(model: model)
          Divider()
        }
        transcriptScrollView
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppSurface.content)
  }

  private var audioCaptureBlockedBanner: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .font(.title3)

      VStack(alignment: .leading, spacing: 4) {
        Text("Audio Capture Blocked")
          .font(.headline)
        Text(
          "ScreenCaptureKit is reporting silent audio. This can happen with DRM-protected playback (Safari, Apple Music, Netflix). Close protected apps or switch sources to resume transcription."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding()
    .background(.orange.opacity(0.1))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
    )
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  private var dropZone: some View {
    VStack(spacing: 18) {
      Text("Start a new transcript")
        .font(.title2.weight(.semibold))

      Text("Record system audio or import an existing lecture file.")
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        Button {
          model.startRecording()
        } label: {
          VStack(spacing: 8) {
            Image(systemName: "record.circle")
              .font(.system(size: 32))
            Text("Record system audio")
              .font(.headline)
            Text("Capture lecture audio playing on this Mac")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(width: 240, height: 130)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy)

        Button {
          model.chooseFile()
        } label: {
          VStack(spacing: 8) {
            Image(systemName: "waveform")
              .font(.system(size: 32))
            Text("Import audio file")
              .font(.headline)
            Text(".wav, .mp3, .m4a, .flac")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(width: 240, height: 130)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
      }

      Text("You can also drag and drop an audio file anywhere in this window.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(36)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(AppSurface.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18)
        .strokeBorder(AppSurface.separator.opacity(0.5))
    )
    .padding(.horizontal, 36)
  }

  private var recordingView: some View {
    VStack(spacing: 16) {
      Image(systemName: "record.circle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.red)

      Text(model.statusText ?? "Recording…")
        .font(.title2.weight(.semibold))

      VStack(spacing: 6) {
        Text(recordingStatusDetail)
          .foregroundStyle(.secondary)

        Text(
          "Frames: \(model.rollingFrameCount)  Chunks: \(model.rollingChunkCount)  RMS: \(String(format: "%.4f", model.lastRMS))"
        )
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      }

      Button("Stop & Transcribe") {
        model.stopAndTranscribeRecording()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var recordingStatusDetail: String {
    if model.rollingFrameCount == 0 {
      return "Waiting for system audio frames…"
    }

    if model.rollingChunkCount == 0 {
      return
        "Audio is being captured. Waiting for enough speech to create the first transcript chunk."
    }

    return "Rolling transcript is active."
  }

  @ViewBuilder
  private var debugSpeakerLabelsBanner: some View {
    if model.isUsingDebugSpeakerLabels,
      model.allSegments.contains(where: { $0.speakerID != nil })
    {
      Label(
        "Debug speaker labels are fake. Configure a real diarizer in Settings → Speakers to identify actual voices.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(.orange)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .padding(.horizontal, 16)
      .padding(.top, 8)
    }
  }

  private var transcriptToolbar: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.selectedFileName ?? "Transcript")
          .font(.headline)
          .lineLimit(1)

        Text("\(model.allSegments.count) segments")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if model.liveCaptureShowsRecordingChrome {
        Button {
          followTail.toggle()
        } label: {
          Image(systemName: followTail ? "arrow.down.to.line" : "pause.circle")
        }
        .help(followTail ? "Following newest" : "Auto-scroll paused")
      }

      Button {
        showingNotesPanel.toggle()
      } label: {
        Image(systemName: showingNotesPanel ? "sidebar.trailing" : "note.text")
      }
      .buttonStyle(.bordered)
      .help(showingNotesPanel ? "Hide notes" : "Show notes")

      Button {
        model.setSpeakerDiarizationEnabled(!model.speakerDiarizationEnabled)
      } label: {
        Label(
          model.speakerToolbarTitle,
          systemImage: model.speakerDiarizationEnabled ? "person.2.wave.2.fill" : "person.2.slash"
        )
      }
      .buttonStyle(.bordered)
      .labelStyle(.titleAndIcon)
      .help(
        model.isUsingDebugSpeakerLabels
          ? "DEBUG: labels are fake. Configure a real diarizer executable for real speaker detection."
          : "Turn speaker labeling on or off. Configure an external tool in Settings for real voices."
      )
      .disabled(model.liveCaptureShowsRecordingChrome)

      Button {
        model.setSpeakerDiarizationEnabled(true)
        model.diarizeSelectedSession()
      } label: {
        Label("Detect Speakers", systemImage: "person.2.wave.2")
      }
      .buttonStyle(.bordered)
      .labelStyle(.titleAndIcon)
      .help("Detect Speaker 1, Speaker 2, etc. for this saved recording")
      .disabled(model.selectedSessionID == nil)

      Button {
        copyTranscript()
      } label: {
        Image(systemName: copiedTranscript ? "checkmark" : "doc.on.doc")
          .frame(width: 18)
      }
      .buttonStyle(.bordered)
      .tint(copiedTranscript ? .green : .accentColor)
      .help(copiedTranscript ? "Copied" : "Copy transcript")
      .disabled(model.transcriptMarkdown.isEmpty)

      TranscriptExportMenu(model: model)

      Button {
        model.openSelectedSessionFolder()
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.bordered)
      .help("Open session folder")
      .disabled(model.selectedSessionID == nil)

      Button(role: .destructive) {
        model.clear()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.bordered)
      .help("Clear")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(AppSurface.card)
  }

  private func copyTranscript() {
    ClipboardExporter.copyToClipboard(text: model.transcriptMarkdown)

    withAnimation(.easeOut(duration: 0.15)) {
      copiedTranscript = true
    }

    Task {
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      await MainActor.run {
        withAnimation(.easeIn(duration: 0.2)) {
          copiedTranscript = false
        }
      }
    }
  }

  private var transcriptScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(model.allSegments.sorted(by: { $0.startTime < $1.startTime })) { seg in
            TranscriptRowView(
              segment: seg,
              currentPlaybackTime: model.playback.currentTime,
              onSeek: { model.seekPlayback(to: $0) },
              onUpdateText: { id, text in model.updateSegmentText(segmentID: id, text: text) },
              onDelete: { model.deleteSegment(segmentID: $0) },
              onMergePrevious: { model.mergeSegmentWithPrevious(segmentID: $0) },
              onSplit: { id, offset in
                model.splitSegment(segmentID: id, atCharacterOffset: offset)
              },
              onRenameSpeakerID: onRenameSpeaker
            )
            .id(seg.id)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .gesture(
        DragGesture(minimumDistance: 5)
          .onChanged { _ in
            if followTail { followTail = false }
          }
      )
      .onChange(of: model.allSegments.count) { _, _ in
        guard followTail,
          model.liveCaptureShowsRecordingChrome,
          let last = model.allSegments.last
        else { return }

        withAnimation(.easeOut(duration: 0.2)) {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
    }
  }
}
