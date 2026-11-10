import SwiftUI
import Foundation

/// Checks the public GitHub release at launch. No account or tracking needed.
/// Apple background push would require a separate APNs service and signing.
@MainActor
final class CinemanaReleaseMonitor: ObservableObject {
    @Published private(set) var latestRevision: String?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var checking = false
    @Published private(set) var checked = false
    @Published private(set) var error = false

    static let telegramURL = URL(string: "https://t.me/CinemanaHub")!
    static let localRevision: String = {
        Bundle.main.object(forInfoDictionaryKey: "CinemanaBuildRevision") as? String ?? "development"
    }()

    func refresh() async {
        guard !checking else { return }
        checking = true
        latestRevision = nil
        downloadURL = nil
        defer { checking = false; checked = true }
        do {
            let url = URL(string: "https://api.github.com/repos/Subaru771/Cinemana-IOS/releases/tags/cinemana-ios-latest-unsigned")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let body = release.body,
                  let source = body.components(separatedBy: "Source commit:").last,
                  let match = source.range(of: #"[0-9a-f]{40}"#, options: .regularExpression),
                  let ipa = release.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }),
                  let link = URL(string: ipa.browser_download_url) else {
                throw URLError(.cannotParseResponse)
            }
            let revision = String(source[match])
            // An older release must never be presented as a new update.
            // GitHub's compare status is "ahead" only when the release commit
            // actually comes after the installed application's commit.
            guard revision != Self.localRevision,
                  Self.localRevision.range(of: #"^[0-9a-f]{40}$"#,
                                          options: .regularExpression) != nil else {
                latestRevision = nil
                downloadURL = nil
                error = false
                return
            }
            let comparisonURL = URL(string:
                "https://api.github.com/repos/Subaru771/Cinemana-IOS/compare/\(Self.localRevision)...\(revision)")!
            var comparisonRequest = URLRequest(url: comparisonURL,
                cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            comparisonRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (comparisonBytes, comparisonResponse) = try await URLSession.shared.data(for: comparisonRequest)
            guard let comparedHTTP = comparisonResponse as? HTTPURLResponse,
                  (200..<300).contains(comparedHTTP.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let comparison = try JSONDecoder().decode(CommitComparison.self, from: comparisonBytes)
            let isNewer = comparison.status == "ahead" && comparison.ahead_by > 0
            latestRevision = isNewer ? revision : nil
            downloadURL = isNewer ? link : nil
            error = false
        } catch {
            self.error = true
        }
    }

    private struct CommitComparison: Decodable {
        let status: String
        let ahead_by: Int
    }

    private struct Release: Decodable {
        let body: String?
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
