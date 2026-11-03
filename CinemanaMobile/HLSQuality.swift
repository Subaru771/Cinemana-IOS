import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Selects a concrete HLS rendition instead of downloading an unconstrained
/// master playlist when a resolution ceiling has been requested.
enum HLSQuality {
    struct Variant: Equatable {
        let height: Int
        let bandwidth: Int
        let url: URL
    }

    static func variants(in manifest: String, relativeTo master: URL) -> [Variant] {
        let lines = manifest.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var found: [Variant] = []
        for i in lines.indices where lines[i].hasPrefix("#EXT-X-STREAM-INF:") {
            let attrs = lines[i]
            guard let match = attrs.range(of: #"RESOLUTION=[0-9]+x[0-9]+"#, options: .regularExpression) else { continue }
            let dimensions = String(attrs[match].dropFirst("RESOLUTION=".count)).split(separator: "x")
            guard dimensions.count == 2, let height = Int(dimensions[1]), height > 0 else { continue }
            let bitrateMatch = attrs.range(of: #"BANDWIDTH=[0-9]+"#, options: .regularExpression)
            let bandwidth = bitrateMatch.flatMap { Int(attrs[$0].dropFirst("BANDWIDTH=".count)) } ?? 0
            let next = (i+1..<lines.count).first { !lines[$0].isEmpty && !lines[$0].hasPrefix("#") }
            guard let j = next, let url = URL(string: lines[j], relativeTo: master)?.absoluteURL,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            found.append(Variant(height: height, bandwidth: bandwidth, url: url))
        }
        return found
    }

    static func choose(_ variants: [Variant], ceiling: Int) -> Variant? {
        let usable = ceiling == Int.max ? variants : variants.filter { $0.height <= ceiling }
        return usable.max { a, b in
            if a.height == b.height { return a.bandwidth < b.bandwidth }
            return a.height < b.height
        }
    }

    static func resolve(_ stream: Stream, maximumQuality: Int, allowsCellular: Bool) async throws -> URL {
        var request = URLRequest(url: stream.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.allowsCellularAccess = allowsCellular
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 2_000_000, let manifest = String(data: data, encoding: .utf8),
              manifest.hasPrefix("#EXTM3U") else {
            throw QualityError.invalidPlaylist
        }
        if manifest.contains("#EXT-X-STREAM-INF") {
            guard let variant = choose(variants(in: manifest, relativeTo: stream.url), ceiling: maximumQuality) else {
                throw QualityError.unavailable(maximumQuality)
            }
            return variant.url
        }
        guard maximumQuality == Int.max || (stream.quality > 0 && stream.quality <= maximumQuality) else {
            throw QualityError.unavailable(maximumQuality)
        }
        return stream.url
    }

    enum QualityError: LocalizedError {
        case invalidPlaylist
        case unavailable(Int)
        var errorDescription: String? {
            switch self {
            case .invalidPlaylist: return "The provider's HLS playlist is unavailable or invalid."
            case .unavailable(let limit):
                return limit == Int.max ? "No usable HLS rendition was found." : "No HLS rendition at or below \(limit)p is available. Choose a higher quality."
            }
        }
    }
}
