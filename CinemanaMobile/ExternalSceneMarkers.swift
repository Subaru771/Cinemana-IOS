import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A shared segment vocabulary. All times are seconds internally; every source is attributed.
/// No segments are inferred from an age rating or from the length of a video.
struct ExternalSceneMarker: Hashable, Sendable {
    let kind: String // intro, recap, outro, preview, mature
    let start: Double
    let end: Double
    let source: String
    let confidence: Double
    let category: String

    func destination(at seconds: Double, duration: Double) -> Double? {
        guard seconds.isFinite, duration.isFinite, duration > 0,
              seconds >= max(0, start - 3), seconds < end - 0.5,
              end < duration - 1 else { return nil }
        return end
    }
}

enum ExternalSceneMarkers {
    static let segmentTypes = ["intro", "recap", "outro", "preview"]
    static let sexualCategories: Set<String> = [
        "nudity", "sex", "sex_scene", "sexual", "sexual-content", "sexual_content",
        "explicit", "erotic", "intimacy", "sexuality"
    ]

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    static func valid(_ marker: ExternalSceneMarker, duration: Double) -> Bool {
        guard duration.isFinite, duration >= 60,
              marker.start.isFinite, marker.end.isFinite,
              marker.start >= 0, marker.end > marker.start + 0.5,
              marker.end < duration - 0.5 else { return false }
        let maximum = marker.kind == "mature" ? 20 * 60 : marker.kind == "intro" || marker.kind == "recap" ? 5 * 60 : 15 * 60
        return marker.end - marker.start <= Double(maximum)
    }

    static func skipDBURL(imdbID: String, season: Int, episode: Int, duration: Double) -> URL? {
        guard let id = CommunitySkipTimes.imdbID(in: imdbID),
              duration.isFinite, duration >= 60 else { return nil }
        var components = URLComponents(string: "https://api.skipdb.tv/api/segments")
        var query = [URLQueryItem(name: "imdb_id", value: id),
                     URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
                     URLQueryItem(name: "adjust", value: "conservative")]
        if season > 0 && episode > 0 {
            query += [URLQueryItem(name: "season", value: String(season)),
                      URLQueryItem(name: "episode", value: String(episode))]
        }
        components?.queryItems = query
        return components?.url
    }

    static func introDBURL(imdbID: String, season: Int, episode: Int) -> URL? {
        guard let id = CommunitySkipTimes.imdbID(in: imdbID) else { return nil }
        var components = URLComponents(string: "https://api.introdb.app/segments")
        var query = [URLQueryItem(name: "imdb_id", value: id)]
        if season > 0 && episode > 0 {
            query += [URLQueryItem(name: "season", value: String(season)),
                      URLQueryItem(name: "episode", value: String(episode))]
        } else { query.append(URLQueryItem(name: "is_movie", value: "true")) }
        components?.queryItems = query
        return components?.url
    }

    static func movieHavenURL(imdbID: String) -> URL? {
        guard let id = CommunitySkipTimes.imdbID(in: imdbID) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/arman-kh/MovieHavenDB/master/movies/\(id).json")
    }

    /// SkipDB uses 0..1 confidence and an explicit duration match flag.
    /// Never automatically seek on `agnostic` or `out-of-range` timestamps.
    static func decodeSkipDB(_ payload: Any, duration: Double) -> [ExternalSceneMarker] {
        guard let json = payload as? [String: Any],
              let segments = json["segments"] as? [String: Any] else { return [] }
        return segmentTypes.compactMap { kind in
            guard let row = segments[kind] as? [String: Any],
                  let start = number(row["start_ms"]), let end = number(row["end_ms"]),
                  let confidence = number(row["confidence"]), confidence >= 0.70,
                  let match = row["match"] as? String, ["exact", "shifted"].contains(match) else { return nil }
            let marker = ExternalSceneMarker(kind: kind, start: start / 1000, end: end / 1000,
                                             source: "SkipDB (ODbL)", confidence: confidence, category: kind)
            return valid(marker, duration: duration) ? marker : nil
        }
    }

    /// IntroDB's read API is a fallback when SkipDB lacks a segment. It doesn't
    /// supply edition/duration match information, so these are button-only skips.
    static func decodeIntroDB(_ payload: Any, duration: Double) -> [ExternalSceneMarker] {
        guard let json = payload as? [String: Any] else { return [] }
        return ["intro", "recap", "outro", "post_credits"].compactMap { key -> ExternalSceneMarker? in
            guard let row = json[key] as? [String: Any],
                  let start = number(row["start_ms"]), let end = number(row["end_ms"]),
                  let confidence = number(row["confidence"]), confidence >= 0.80 else { return nil }
            let kind = key == "post_credits" ? "preview" : key
            let marker = ExternalSceneMarker(kind: kind, start: start / 1000, end: end / 1000,
                                             source: "IntroDB", confidence: confidence, category: kind)
            return valid(marker, duration: duration) ? marker : nil
        }
    }

    /// MovieHavenDB CC BY 4.0: a small, movie-only, community dataset. Only
    /// entries explicitly marked skip=true in a sexual/nudity category may be used.
    /// Require a matching duration (different cuts can have different scene offsets).
    static func decodeMovieHaven(_ payload: Any, imdbID: String, duration: Double) -> [ExternalSceneMarker] {
        guard let id = CommunitySkipTimes.imdbID(in: imdbID),
              let json = payload as? [String: Any],
              (json["imdb_id"] as? String)?.lowercased() == id,
              let storedDuration = number(json["duration"]), storedDuration > 0,
              abs(storedDuration - duration) <= 5,
              let scenes = json["scenes"] as? [[String: Any]] else { return [] }
        return scenes.compactMap { row in
            let reason = (row["reason"] as? String ?? "").lowercased().replacingOccurrences(of: " ", with: "_")
            guard sexualCategories.contains(reason), (row["skip"] as? Bool) == true,
                  let start = number(row["start"]), let end = number(row["end"]) else { return nil }
            let marker = ExternalSceneMarker(kind: "mature", start: start, end: end,
                                             source: "MovieHavenDB (CC BY 4.0)", confidence: 0.80, category: reason)
            return valid(marker, duration: duration) ? marker : nil
        }
    }

    static func merge(primary: [ExternalSceneMarker], fallback: [ExternalSceneMarker]) -> [ExternalSceneMarker] {
        var seen = Set(primary.map(\.kind))
        var result = primary
        for marker in fallback where !seen.contains(marker.kind) {
            result.append(marker)
            seen.insert(marker.kind)
        }
        return result.sorted { $0.start < $1.start }
    }
}

actor ExternalSceneService {
    static let shared = ExternalSceneService()
    private struct CacheEntry { let at: Date; let markers: [ExternalSceneMarker] }
    private var cache: [String: CacheEntry] = [:]

    private func json(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count < 256_000 else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch { return nil }
    }

    /// Lightweight remote reads only. No video frame processing; requests carry
    /// public IMDb ID, season/episode and duration, never the user's history.
    func markers(imdbID: String, season: Int, episode: Int, duration: Double,
                 includeCommunity: Bool, includeMature: Bool) async -> [ExternalSceneMarker] {
        guard let id = CommunitySkipTimes.imdbID(in: imdbID), duration > 60 else { return [] }
        let isEpisode = season > 0 && episode > 0
        let key = "\(id)|\(isEpisode ? season : 0)|\(isEpisode ? episode : 0)|\(Int(duration))|\(includeCommunity)|\(includeMature)"
        if let cached = cache[key], Date().timeIntervalSince(cached.at) < 3600 { return cached.markers }
        var result: [ExternalSceneMarker] = []
        if includeCommunity {
            if let url = ExternalSceneMarkers.skipDBURL(imdbID: id, season: isEpisode ? season : 0,
                                                       episode: isEpisode ? episode : 0, duration: duration),
               let response = await json(url) {
                result = ExternalSceneMarkers.decodeSkipDB(response, duration: duration)
            }
            if result.count < 4,
               let url = ExternalSceneMarkers.introDBURL(imdbID: id, season: isEpisode ? season : 0, episode: isEpisode ? episode : 0),
               let response = await json(url) {
                result = ExternalSceneMarkers.merge(primary: result,
                    fallback: ExternalSceneMarkers.decodeIntroDB(response, duration: duration))
            }
        }
        if includeMature && !isEpisode,
           let url = ExternalSceneMarkers.movieHavenURL(imdbID: id),
           let response = await json(url) {
            result += ExternalSceneMarkers.decodeMovieHaven(response, imdbID: id, duration: duration)
        }
        cache[key] = CacheEntry(at: Date(), markers: result)
        if cache.count > 30 { cache.removeValue(forKey: cache.keys.first!) }
        return result
    }
}
