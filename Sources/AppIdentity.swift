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

    private static func verifiedURL(_ value: String) -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            preconditionFailure("App links must be valid HTTPS URLs")
        }
        return url
    }
}
