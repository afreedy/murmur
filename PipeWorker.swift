import Foundation

final class PipeWorker {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writeQueue = DispatchQueue(label: "com.afreed.codexluna.write", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "com.afreed.codexluna.read", qos: .userInitiated)
    private var buffer = Data()
    private var stopping = false
    var onMessage: (([String: Any]) -> Void)?

    static func pythonPath() throws -> String {
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Murmur/runtime/bin/python").path
        if FileManager.default.isExecutableFile(atPath: local) { return local }
        for candidate in ["/opt/homebrew/bin/whisper", "/usr/local/bin/whisper"] {
            guard let script = try? String(contentsOfFile: candidate, encoding: .utf8),
                  let first = script.split(separator: "\n").first, first.hasPrefix("#!/") else { continue }
            let executable = String(first.dropFirst(2))
            if FileManager.default.isExecutableFile(atPath: executable) { return executable }
        }
        throw TextTarget.error("The installed Whisper Python runtime is missing. Restore the Homebrew Whisper installation.")
    }

    func start(script: String) throws {
        guard let scriptURL = Bundle.main.url(forResource: script, withExtension: "py") else {
            throw TextTarget.error("The app's \(script) worker is missing. Rebuild Murmur.")
        }
        process.executableURL = URL(fileURLWithPath: try Self.pythonPath())
        process.arguments = ["-u", scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.readQueue.async {
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer[..<newline]
                    self.buffer.removeSubrange(...newline)
                    if let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        DispatchQueue.main.async { self.onMessage?(value) }
                    }
                }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            DispatchQueue.main.async {
                if !self.stopping {
                    self.onMessage?(["type": "fatal", "message": "\(script.capitalized) stopped (\(process.terminationStatus)). Reopen Murmur to retry."])
                }
            }
        }
        try process.run()
    }

    func send(_ value: [String: Any]) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: value) else { return }
        var line = encoded; line.append(10)
        writeQueue.async { [weak self] in
            guard let self, !self.stopping, self.process.isRunning else { return }
            do { try self.input.fileHandleForWriting.write(contentsOf: line) }
            catch { DispatchQueue.main.async { self.onMessage?(["type": "fatal", "message": error.localizedDescription]) } }
        }
    }

    func stop() {
        stopping = true
        try? input.fileHandleForWriting.close()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
