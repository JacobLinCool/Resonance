import Foundation

enum AppIdentity {
    static let bundleIdentifier: String = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("The application bundle must define CFBundleIdentifier")
        }
        return bundleIdentifier
    }()
}
