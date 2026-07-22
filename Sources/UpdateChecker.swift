import Foundation
import Observation
import os

/// A dotted numeric version such as `0.2.0`. Tags with any non-numeric
/// component (for example prereleases) are rejected rather than misordered.
struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    let components: [Int]

    init?(tag: String) {
        var text = tag.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") {
            text = String(text.dropFirst())
        }
        guard !text.isEmpty else { return nil }

        var parsed: [Int] = []
        for piece in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(piece), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct AvailableUpdate: Sendable, Equatable {
    let version: AppVersion
    let downloadURL: URL
}

/// How this copy of Resonance was installed. App Store builds update through
/// the App Store, so the in-app update check only serves direct downloads.
enum AppDistribution {
    /// The App Store leaves a receipt inside the bundle; Developer ID and
    /// development builds have none. Checked by path to avoid the deprecated
    /// `appStoreReceiptURL` and a StoreKit dependency.
    static var isAppStore: Bool {
        let receipt = Bundle.main.bundleURL
            .appendingPathComponent("Contents/_MASReceipt/receipt", isDirectory: false)
        return FileManager.default.fileExists(atPath: receipt.path)
    }
}

typealias LatestReleaseFetcher = @Sendable () async throws -> (tag: String, pageURL: URL)

/// Compares the newest GitHub release against the running version. This is a
/// notifier, not an installer: updating stays a deliberate download so the
/// sandboxed app needs no self-modification machinery.
@MainActor
@Observable
final class UpdateChecker {
    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isChecking = false
    private(set) var lastCheckFailed = false
    private(set) var lastSuccessfulCheck: Date?

    @ObservationIgnored private let fetchLatest: LatestReleaseFetcher
    @ObservationIgnored private let currentVersion: AppVersion?
    @ObservationIgnored private let settings: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let log = Logger(
        subsystem: AppIdentity.bundleIdentifier,
        category: "update"
    )

    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheckDate"

    init(
        currentVersionText: String? = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        fetchLatest: @escaping LatestReleaseFetcher = UpdateChecker.fetchLatestGitHubRelease,
        settings: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        currentVersion = currentVersionText.flatMap(AppVersion.init(tag:))
        self.fetchLatest = fetchLatest
        self.settings = settings
        self.now = now
    }

    /// Runs at most one automatic check per day; failures stay silent.
    func checkAutomaticallyIfDue() async {
        let lastCheck = settings.object(forKey: Self.lastCheckKey) as? Date
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.automaticCheckInterval {
            return
        }
        await check()
    }

    func checkNow() async {
        await check()
    }

    private func check() async {
        guard !isChecking, let currentVersion else { return }

        isChecking = true
        lastCheckFailed = false
        defer { isChecking = false }

        do {
            let latest = try await fetchLatest()
            settings.set(now(), forKey: Self.lastCheckKey)
            lastSuccessfulCheck = now()
            guard let latestVersion = AppVersion(tag: latest.tag) else {
                log.info("skipping non-release tag: \(latest.tag, privacy: .public)")
                return
            }
            if latestVersion > currentVersion {
                availableUpdate = AvailableUpdate(
                    version: latestVersion,
                    downloadURL: latest.pageURL
                )
            } else {
                availableUpdate = nil
            }
        } catch {
            lastCheckFailed = true
            log.error("update check failed: \(error.localizedDescription)")
        }
    }

    @Sendable
    static func fetchLatestGitHubRelease() async throws -> (tag: String, pageURL: URL) {
        var request = URLRequest(
            url: AppLinks.latestReleaseAPI,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(GitHubLatestReleasePayload.self, from: data)
        guard payload.htmlURL.scheme == "https" else {
            throw URLError(.badURL)
        }
        return (payload.tagName, payload.htmlURL)
    }
}

private struct GitHubLatestReleasePayload: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
