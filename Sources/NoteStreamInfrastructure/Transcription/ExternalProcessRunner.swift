import Foundation

struct ExternalProcessResult: Sendable {
  let terminationStatus: Int32
  let stdout: Data
  let stderr: Data
}

private final class RunningProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?

  func set(_ process: Process) {
    lock.lock()
    defer { lock.unlock() }
    self.process = process
  }

  func terminate() {
    lock.lock()
    let current = process
    lock.unlock()

    if current?.isRunning == true {
      current?.terminate()
    }
  }
}

enum ExternalProcessRunner {
  static func run(
    executableURL: URL,
    arguments: [String] = [],
    stdin: Data? = nil,
    additionalEnvironment: [String: String] = [:],
    timeoutSeconds: UInt64 = 120
  ) async throws -> ExternalProcessResult {
    let processBox = RunningProcessBox()

    return try await withTaskCancellationHandler {
      let process = Process()
      process.executableURL = executableURL
      process.arguments = arguments

      if !additionalEnvironment.isEmpty {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in additionalEnvironment {
          environment[key] = value
        }
        process.environment = environment
      }

      let stdinPipe = Pipe()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()

      if stdin != nil {
        process.standardInput = stdinPipe
      }

      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      processBox.set(process)

      try process.run()

      if let stdin {
        stdinPipe.fileHandleForWriting.write(stdin)
        try stdinPipe.fileHandleForWriting.close()
      }

      let stdoutTask = Task.detached(priority: .utility) {
        stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      }

      let stderrTask = Task.detached(priority: .utility) {
        stderrPipe.fileHandleForReading.readDataToEndOfFile()
      }

      let status = try await waitForTermination(
        process,
        timeoutSeconds: timeoutSeconds
      )

      let stdout = await stdoutTask.value
      let stderr = await stderrTask.value

      return ExternalProcessResult(
        terminationStatus: status,
        stdout: stdout,
        stderr: stderr
      )
    } onCancel: {
      processBox.terminate()
    }
  }

  /// `Process.waitUntilExit()` blocks indefinitely; running it on the Swift default executor can
  /// starve concurrent tasks (including our timeout `Task.sleep`) on small CI thread pools. Poll
  /// with async sleep and reap exit on a utility queue instead.
  private static func waitForTermination(
    _ process: Process,
    timeoutSeconds: UInt64
  ) async throws -> Int32 {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

    while process.isRunning {
      if Date() >= deadline {
        if process.isRunning {
          process.terminate()
        }
        await waitUntilExitOffCooperativePool(process)
        throw NSError(
          domain: "NoteStream",
          code: 71,
          userInfo: [
            NSLocalizedDescriptionKey:
              "External process timed out after \(timeoutSeconds) seconds."
          ]
        )
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    await waitUntilExitOffCooperativePool(process)
    return process.terminationStatus
  }

  private static func waitUntilExitOffCooperativePool(_ process: Process) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .utility).async {
        process.waitUntilExit()
        continuation.resume()
      }
    }
  }
}
