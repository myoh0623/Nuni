import Foundation

enum AppInformation {
    static let repositoryURL: URL = {
        let fallbackURL = "https://github.com/myoh0623/Nuni"
        guard let fallback = URL(string: fallbackURL) else {
            preconditionFailure("Invalid built-in repository URL")
        }
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "NuniGitHubURL") as? String
        return URL(string: configuredURL ?? fallbackURL) ?? fallback
    }()

    static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, !build.isEmpty else {
            return "Version \(version)"
        }
        return "Version \(version) (\(build))"
    }
}
