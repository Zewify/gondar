import Foundation
import GondarCore
import os

/// Gondar's own folder in Application Support, where `gondar-feed` writes `statusline.json` and the app keeps `last.json`.
enum GondarFolder {
    nonisolated static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Gondar", isDirectory: true)
    nonisolated static let feedURL = url.appendingPathComponent("statusline.json")
    nonisolated static let lastURL = url.appendingPathComponent("last.json")

    /// Creates the folder, owner-only, as `gondar-feed` does, if it is missing.
    nonisolated static func create() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// Writes `data` to `url` atomically, readable by its owner only: a temporary file created 0600, then renamed over the old one.
    nonisolated static func writeAtomically(_ data: Data, to url: URL) -> Bool {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let closed = close(fd)
        guard written == data.count, closed == 0, rename(temp, url.path) == 0 else {
            unlink(temp)
            return false
        }
        return true
    }
}

/// Notices when `gondar-feed` rewrites `statusline.json`, and reports what it now holds (nil when it is gone or unreadable).
///
/// It watches the folder rather than the file, as `AccountFileWatcher` does, because the file is replaced by rename.
/// Writes to the folder's other files (`last.json`, the lock) leave the feed's modification date alone, so they are skipped.
/// It runs for the life of the app, so it is never stopped.
@MainActor
final class FeedWatcher {
    private let onChange: @MainActor (FeedSnapshot?) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var pending: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "feed")

    init(onChange: @escaping @MainActor (FeedSnapshot?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        GondarFolder.create()
        let descriptor = open(GondarFolder.url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("Couldn't watch Gondar's folder for the status line feed")
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

    /// The feed file as it is now, read off the main actor.
    nonisolated static func read() async -> FeedSnapshot? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: GondarFolder.feedURL) else { return nil }
            return try? StatusLineFeed.parse(data)
        }.value
    }

    private func folderChanged() {
        let modified = Self.modificationDate()
        guard modified != lastModified else { return }
        lastModified = modified
        // Debounced, so a burst of status line refreshes is read once, after it settles.
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let feed = await Self.read()
            guard let self, !Task.isCancelled else { return }
            self.onChange(feed)
        }
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: GondarFolder.feedURL.path))?[.modificationDate] as? Date
    }
}
