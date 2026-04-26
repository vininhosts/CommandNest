import Foundation

protocol UpdateServicing {
    func latestRelease() async throws -> AppRelease
}

struct AppRelease: Equatable {
    let tagName: String
    let name: String
    let pageURL: URL
    let assetNames: [String]
}

enum UpdateServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case releaseUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub release URL is invalid."
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .releaseUnavailable:
            return "No GitHub release is available yet."
        }
    }
}

final class GitHubUpdateService: UpdateServicing {
    private let endpoint: String
    private let session: URLSession

    init(endpoint: String = Constants.gitHubLatestReleaseAPIURL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func latestRelease() async throws -> AppRelease {
        guard let url = URL(string: endpoint) else {
            throw UpdateServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CommandNest", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw httpResponse.statusCode == 404 ? UpdateServiceError.releaseUnavailable : UpdateServiceError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        guard let pageURL = URL(string: release.htmlURL) else {
            throw UpdateServiceError.invalidResponse
        }

        return AppRelease(
            tagName: release.tagName,
            name: release.name ?? release.tagName,
            pageURL: pageURL,
            assetNames: release.assets.map(\.name)
        )
    }

    static func isRelease(_ releaseTag: String, newerThan currentVersion: String) -> Bool {
        compareVersions(releaseTag, currentVersion) == .orderedDescending
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Decodable {
        let name: String
    }
}
