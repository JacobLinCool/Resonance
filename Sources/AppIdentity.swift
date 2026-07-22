import Foundation

enum AppIdentity {
    static let bundleIdentifier: String = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("The application bundle must define CFBundleIdentifier")
        }
        return bundleIdentifier
    }()
}

enum AppLinks {
    static let privacyPolicy = verifiedURL(
        "https://github.com/JacobLinCool/Resonance/blob/main/PRIVACY.md"
    )
    static let repository = verifiedURL("https://github.com/JacobLinCool/Resonance")
    static let support = verifiedURL("https://github.com/JacobLinCool/Resonance/issues")
    static let releases = verifiedURL("https://github.com/JacobLinCool/Resonance/releases")
    static let latestReleaseAPI = verifiedURL(
        "https://api.github.com/repos/JacobLinCool/Resonance/releases/latest"
    )

    /// Deep links into the System Settings privacy panes named by error
    /// recovery guidance.
    static let microphonePrivacySettings = verifiedSettingsURL(
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )
    static let mediaPrivacySettings = verifiedSettingsURL(
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
    )

    private static func verifiedSettingsURL(_ value: String) -> URL {
        guard let url = URL(string: value), url.scheme == "x-apple.systempreferences" else {
            preconditionFailure("Settings links must use the systempreferences scheme")
        }
        return url
    }

    private static func verifiedURL(_ value: String) -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            preconditionFailure("App links must be valid HTTPS URLs")
        }
        return url
    }
}
