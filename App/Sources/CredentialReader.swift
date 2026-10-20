import Foundation

/// What reading Claude Code's Keychain item found.
enum KeychainRead: Sendable, Equatable {
    case item(String)
    /// There is no item: Claude Code is signed out (`security` exits 44).
    case noItem
    /// The read failed or timed out; says nothing about whether Claude Code is signed in.
    case failed
}

/// Reads Claude Code's Keychain item through `/usr/bin/security`, never through the Keychain API:
/// the item's access list already trusts `security`, so this read does not prompt, while a direct
/// call from an ad hoc signed app would, and its grant would not survive the next release's signature.
/// Read-only: Gondar never writes the item or refreshes the token in it.
enum CredentialReader {
    private static let timeout: TimeInterval = 10

    /// The item's value is never logged.
    static func read() async -> KeychainRead {
        await withCheckedContinuation { continuation in
            let run = Run(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { finished in
                run.exited(normally: finished.terminationReason == .exit, status: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                run.finish(.failed)
                return
            }
            // Drained while the process runs, on a GCD thread rather than a cooperative one, so a full pipe cannot stall it.
            DispatchQueue.global(qos: .utility).async {
                run.received(output.fileHandleForReading.readDataToEndOfFile())
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard run.finish(.failed) else { return }
                process.terminate()
            }
        }
    }

    /// Collects the output and the exit status, whichever arrives first, and resumes the caller exactly once.
    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<KeychainRead, Never>?
        private var output: Data?
        private var exit: (normally: Bool, status: Int32)?

        init(_ continuation: CheckedContinuation<KeychainRead, Never>) {
            self.continuation = continuation
        }

        func received(_ data: Data) {
            lock.lock()
            output = data
            lock.unlock()
            settleIfComplete()
        }

        func exited(normally: Bool, status: Int32) {
            lock.lock()
            exit = (normally, status)
            lock.unlock()
            settleIfComplete()
        }

        /// Resumes the caller with `result` unless it was already resumed; true when this call resumed it.
        @discardableResult
        func finish(_ result: KeychainRead) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: result)
            return pending != nil
        }

        private func settleIfComplete() {
            lock.lock()
            let output = self.output
            let exit = self.exit
            lock.unlock()
            guard let output, let exit else { return }
            guard exit.normally else { finish(.failed); return }
            switch exit.status {
            case 0:
                let text = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                finish(text.isEmpty ? .failed : .item(text))
            case 44:
                finish(.noItem)
            default:
                finish(.failed)
            }
        }
    }
}
