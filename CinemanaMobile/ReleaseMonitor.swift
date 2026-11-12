import SwiftUI
import Foundation
import CryptoKit

/// Checks the Cinemana-owned Cloudflare update feed. The iPhone does not
/// contact GitHub, open GitHub URLs or follow redirects off the update host.
/// Hosting is configured separately; unsigned IPAs still need a valid signer.
@MainActor
final class CinemanaReleaseMonitor: ObservableObject {
    @Published private(set) var latestRevision: String?
    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var checking = false
    @Published private(set) var checked = false
    @Published private(set) var error = false

    static let telegramURL = URL(string: "https://t.me/CinemanaHub")!
    static let updateFeedURL = URL(string: "https://cinemana-ios-updates.pages.dev/latest.json")!
    private static let maxIPABytes = 200_000_000
    private var pendingRelease: UpdateManifest?

    func refresh() async {
        guard !checking else { return }
        checking = true
        latestRevision = nil
        latestVersion = nil
        downloadURL = nil
        pendingRelease = nil
        defer { checking = false; checked = true }

        let session = Self.lockedSession()
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: Self.updateFeedURL,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard Self.successful(response),
                  data.count <= 16_384 else { throw UpdateError.invalidMetadata }

            let release = try JSONDecoder().decode(UpdateManifest.self, from: data)
            guard let url = Self.validatedURL(for: release) else {
                throw UpdateError.invalidMetadata
            }
            let installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            let supported = CinemanaUpdateVersion.supports(
                minimumOS: release.minOSVersion,
                systemOS: ProcessInfo.processInfo.operatingSystemVersion)
            guard supported, CinemanaUpdateVersion.isNewer(
                installedBuild: installedBuild, publishedBuild: release.build) else {
                error = false
                return
            }

            pendingRelease = release
            latestRevision = "\(release.version)-b\(release.build)"
            latestVersion = "\(release.version) (Build \(release.build))"
            downloadURL = url
            error = false
        } catch {
            self.error = true
        }
    }

    /// Download in-app, verify checksum and length, then return a local IPA to
    /// share with SideStore/Files. Never sends the user to a GitHub page.
    func downloadLatest() async throws -> URL {
        guard let release = pendingRelease,
              let link = Self.validatedURL(for: release) else {
            throw UpdateError.noAvailableUpdate
        }
        let session = Self.lockedSession()
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: link)
        guard Self.successful(response) else { throw UpdateError.downloadFailed }

        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: temporary.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue == release.size else {
            throw UpdateError.downloadFailed
        }
        let digest = SHA256.hash(data: try Data(contentsOf: temporary, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256.lowercased() else {
            throw UpdateError.checksumMismatch
        }

        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaUpdates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(release.ipa)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func validatedURL(for release: UpdateManifest) -> URL? {
        guard release.version.range(of: #"^[0-9]+(?:\.[0-9]+){0,3}$"#,
                                    options: .regularExpression) != nil,
              release.build.range(of: #"^[0-9]{1,12}$"#, options: .regularExpression) != nil,
              release.ipa.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.ipa$"#,
                                   options: .regularExpression) != nil,
              !release.ipa.contains(".."),
              release.sha256.range(of: #"^[a-fA-F0-9]{64}$"#,
                                      options: .regularExpression) != nil,
              release.size > 100_000, release.size <= maxIPABytes else { return nil }
        let base = updateFeedURL.deletingLastPathComponent()
        guard let url = URL(string: release.ipa, relativeTo: base)?.absoluteURL,
              url.scheme == "https",
              url.host == updateFeedURL.host,
              url.deletingLastPathComponent() == base,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    private static func successful(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme == "https",
              http.url?.host == updateFeedURL.host else { return false }
        return true
    }

    private static func lockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: RejectAllRedirects(), delegateQueue: nil)
    }

    private struct UpdateManifest: Decodable {
        let version: String
        let build: String
        let minOSVersion: String
        let ipa: String
        let size: Int
        let sha256: String
    }

    private enum UpdateError: LocalizedError {
        case invalidMetadata, noAvailableUpdate, downloadFailed, checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidMetadata: return "Update information is invalid or unavailable."
            case .noAvailableUpdate: return "No newer Cinemana update is available."
            case .downloadFailed: return "Could not download the complete Cinemana IPA."
            case .checksumMismatch: return "Download verification failed. Please retry."
            }
        }
    }
}

private final class RejectAllRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Prevent a CDN or server misconfiguration from ever redirecting to GitHub.
        completionHandler(nil)
    }
}
