import Foundation
import GondarCore
import os

/// Notices when Claude Code signs in to another account or organisation, by watching `~/.claude.json`.
///
/// It watches the home directory rather than the file: Claude Code replaces the file by rename,
/// and a watch on the file itself would go dead after the first replacement.
/// Claude Code rewrites the file routinely without any account change, so `onChange` fires only
/// when the account and organisation pair differs from the last one seen.
@MainActor
final class AccountFileWatcher {
    nonisolated static let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")

    private let onChange: @MainActor (LocalAccount?) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var lastSeen: LocalAccount?
    private var hasSeen = false
    private var pending: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "account")

    init(onChange: @escaping @MainActor (LocalAccount?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        let descriptor = open(NSHomeDirectory(), O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("Couldn't watch the home folder for account changes")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        lastModified = Self.modificationDate()
        source.resume()
        // The account at start is the baseline, not a change.
        pending = Task { [weak self] in
            let account = await Self.read()
            guard let self, !Task.isCancelled, !self.hasSeen else { return }
            self.lastSeen = account
            self.hasSeen = true
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    /// The signed-in account in `~/.claude.json`, read off the main actor (the file runs to hundreds of kilobytes).
    nonisolated static func read() async -> LocalAccount? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return LocalAccount.parse(claudeJSON: data)
        }.value
    }

    private func folderChanged() {
        let modified = Self.modificationDate()
        guard modified != lastModified else { return }
        lastModified = modified
        // Debounced, so a burst of writes is read once, after it settles.
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let account = await Self.read()
            guard let self, !Task.isCancelled else { return }
            let isChange = self.hasSeen && account != self.lastSeen
            self.lastSeen = account
            self.hasSeen = true
            if isChange {
                Self.logger.info("The signed-in account changed")
                self.onChange(account)
            }
        }
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}
