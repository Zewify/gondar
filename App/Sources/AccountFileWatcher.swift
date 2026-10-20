import Foundation
import GondarCore
import os

/// What `~/.claude.json` says about the signed-in account: the IDs that decide a switch, and the header fields
/// shown until the profile endpoint confirms them.
struct AccountFile: Sendable {
    let account: LocalAccount
    let profile: Profile?
}

/// Notices when Claude Code rewrites `~/.claude.json`, and reports the account it then names.
///
/// It watches the home directory rather than the file: Claude Code replaces the file by rename,
/// and a watch on the file itself would go dead after the first replacement.
/// Claude Code rewrites the file routinely without any account change; the watcher keeps no account of its own,
/// so `UsageModel` alone decides what is a switch, against the one account it tracks.
/// It runs for the life of the app, so it is never stopped.
@MainActor
final class AccountFileWatcher {
    nonisolated static let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")

    private let onChange: @MainActor (AccountFile?) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var pending: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "account")

    init(onChange: @escaping @MainActor (AccountFile?) -> Void) {
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
    }

    /// The signed-in account in `~/.claude.json`, read off the main actor (the file runs to hundreds of kilobytes).
    nonisolated static func read() async -> AccountFile? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL), let account = LocalAccount.parse(claudeJSON: data) else { return nil }
            return AccountFile(account: account, profile: Profile.parse(claudeJSON: data))
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
            self.onChange(account)
        }
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}
