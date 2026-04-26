import AppKit
import CoreGraphics

public enum ScreenRecordingPermission {
  public static func hasPermission() -> Bool {
    CGPreflightScreenCaptureAccess()
  }

  public static func request() async -> Bool {
    // CGRequestScreenCaptureAccess has no completion handler; it returns synchronously.
    // It will prompt the user and the app must be restarted after enabling in Settings.
    CGRequestScreenCaptureAccess()
    return CGPreflightScreenCaptureAccess()
  }

  public static func openSystemSettings() {
    // Privacy & Security → Screen Recording
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
