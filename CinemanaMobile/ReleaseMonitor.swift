import SwiftUI
import Foundation
import CryptoKit

/// Checks the Cinemana-owned Cloudflare update feed. The iPhone does not
/// contact third-party code hosting or follow redirects off the update host.
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
    static let updateFeedURL = URL(string: "https://cinemana-updates-e8l.pages.dev/updates.json")!
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

            let manifest = try JSONDecoder().decode(CombinedManifest.self, from: data)
            guard manifest.schema == 1 else { throw UpdateError.invalidMetadata }
            guard manifest.ios.enabled else {
                error = false
                return
            }
            let release = manifest.ios
            let installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            let supported = CinemanaUpdateVersion.supports(
                minimumOS: release.minOSVersion ?? "16.0",
                systemOS: ProcessInfo.processInfo.operatingSystemVersion)
            guard supported, CinemanaUpdateVersion.isNewer(
                installedBuild: installedBuild, publishedBuild: String(release.build)) else {
                error = false
                return
            }
            guard let url = Self.validatedURL(for: release) else {
                throw UpdateError.invalidMetadata
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
    /// share with SideStore/Files. Never sends the user to an external update site.
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
        guard let checksum = release.sha256,
              digest == checksum.lowercased() else {
            throw UpdateError.checksumMismatch
        }

        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaUpdates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(link.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func validatedURL(for release: UpdateManifest) -> URL? {
        guard let checksum = release.sha256, let bytes = release.size,
              let releaseLink = release.downloadUrl,
              release.version.range(of: #"^[0-9]+(?:\.[0-9]+){0,3}$"#,
                                    options: .regularExpression) != nil,
              release.build >= 1,
              checksum.range(of: #"^[a-fA-F0-9]{64}$"#,
                                      options: .regularExpression) != nil,
              bytes > 100_000, bytes <= maxIPABytes,
              let url = URL(string: releaseLink),
              url.scheme == "https",
              url.host == updateFeedURL.host,
              url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2,
              url.lastPathComponent.range(
                  of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.ipa$"#,
                  options: .regularExpression) != nil,
              !url.lastPathComponent.contains("..") else { return nil }
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

    private struct CombinedManifest: Decodable {
        let schema: Int
        let ios: UpdateManifest
    }

    private struct UpdateManifest: Decodable {
        let enabled: Bool
        let version: String
        let build: Int
        let minOSVersion: String?
        let downloadUrl: String?
        let size: Int?
        let sha256: String?
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
        // Reject every redirect to prevent leaving the configured update origin.
        completionHandler(nil)
    }
}
