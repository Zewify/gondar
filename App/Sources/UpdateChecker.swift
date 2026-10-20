import AppKit
import Observation
import GondarCore

/// Once a day, asks GitHub for the latest release and remembers a newer one. Network failures are silent.
/// Off entirely while `feed` is nil.
@MainActor
@Observable
final class UpdateChecker {
    /// Both stay nil until the repository is public: with no feed there is no request, no menu item and no update row.
    static let installCommand: String? = nil
    static let feed: URL? = nil

    private enum Keys {
        static let enabled = "checkForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let latestKnown = "latestKnownVersion"
    }

    private(set) var available: AppVersion?
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                remember(defaults.string(forKey: Keys.latestKnown).flatMap(AppVersion.init))
                Task { await check(force: true) }
            } else {
                available = nil
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")

    init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        remember(defaults.string(forKey: Keys.latestKnown).flatMap(AppVersion.init))
    }

    func start() {
        guard Self.feed != nil else { return }
        Task {
            while !Task.isCancelled {
                await check(force: false)
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func check(force: Bool) async {
        guard let feed = Self.feed, isEnabled else { return }
        let last = defaults.object(forKey: Keys.lastCheck) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) >= 86_400 else { return }
        var request = URLRequest(url: feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Only a request that got an HTTP response uses up the day; offline or timeout retries on the next pass.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        defaults.set(Date(), forKey: Keys.lastCheck)
        guard http.statusCode == 200,
              let latest = try? ReleaseFeed.latestVersion(fromJSON: data) else { return }
        defaults.set(latest.description, forKey: Keys.latestKnown)
        remember(latest)
    }

    private func remember(_ latest: AppVersion?) {
        guard Self.feed != nil, isEnabled, let latest, let current, latest > current else { available = nil; return }
        available = latest
    }

    func copyInstallCommand() {
        guard let command = Self.installCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
