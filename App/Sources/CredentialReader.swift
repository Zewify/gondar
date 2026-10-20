import Foundation

/// Reads Claude Code's Keychain item through `/usr/bin/security`, never through the Keychain API:
/// the item's access list already trusts `security`, so this read does not prompt, while a direct
/// call from an ad hoc signed app would, and its grant would not survive the next release's signature.
/// Read-only: Gondar never writes the item or refreshes the token in it.
enum CredentialReader {
    /// The item's value, or nil when there is none (`security` exits 44) or it could not be read.
    /// Its output is never logged.
    static func read() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            // The value is a few kilobytes at most, well inside a pipe's buffer, so reading it after exit cannot stall the process.
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard finished.terminationReason == .exit, finished.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: trimmed.isEmpty ? nil : trimmed)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
