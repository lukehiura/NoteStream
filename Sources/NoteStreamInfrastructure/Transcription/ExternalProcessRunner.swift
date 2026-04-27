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

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    process = nil
  }

  func terminate() {
    lock.lock()
    let current = process
    lock.unlock()

    guard current?.isRunning == true else { return }
    current?.terminate()
  }
}

private final class PipeDataCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()

  func append(_ chunk: Data) {
    guard !chunk.isEmpty else { return }
    lock.lock()
    data.append(chunk)
    lock.unlock()
  }

  func snapshot() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return data
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

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      let stdoutCollector = PipeDataCollector()
      let stderrCollector = PipeDataCollector()

      stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        stdoutCollector.append(handle.availableData)
      }

      stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        stderrCollector.append(handle.availableData)
      }

      var nullIn: FileHandle?
      var stdinWritePipe: Pipe?

      if stdin != nil {
        let pipe = Pipe()
        stdinWritePipe = pipe
        process.standardInput = pipe
      } else {
        nullIn = FileHandle(forReadingAtPath: "/dev/null")
        if let nullIn {
          process.standardInput = nullIn
        }
      }

      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      processBox.set(process)

      do {
        try process.run()

        if let stdin, let pipe = stdinWritePipe {
          pipe.fileHandleForWriting.write(stdin)
          try? pipe.fileHandleForWriting.close()
        }

        let status = try await waitForTermination(
          process,
          timeoutSeconds: timeoutSeconds
        )

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        try? stdinWritePipe?.fileHandleForWriting.close()
        try? nullIn?.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        processBox.clear()

        return ExternalProcessResult(
          terminationStatus: status,
          stdout: stdoutCollector.snapshot(),
          stderr: stderrCollector.snapshot()
        )
      } catch {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
          process.terminate()
          await waitUntilExitOffCooperativePool(process)
        }

        try? stdinWritePipe?.fileHandleForWriting.close()
        try? nullIn?.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        processBox.clear()

        throw error
      }
    } onCancel: {
      processBox.terminate()
    }
  }

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
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        process.waitUntilExit()
        continuation.resume()
      }
    }
  }
}
