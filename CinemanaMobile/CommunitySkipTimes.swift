import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An intro segment for the *exact* title, season, episode, and source duration.
/// Never substitute an arbitrary number of seconds when the timing is missing.
struct VerifiedIntroSegment: Equatable, Sendable {
    let start: Double
    let end: Double
    let source: String
}

enum CommunitySkipTimes {
    /// Provider imdbUrlRef is typically a URL; reject ambiguous title-only matches.
    static func imdbID(in raw: String) -> String? {
        guard let range = raw.range(of: #"tt[0-9]{7,10}"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(raw[range]).lowercased()
    }

    /// Search only explicit IMDb metadata fields, not unrelated descriptions or titles.
    static func imdbID(in json: Any) -> String? {
        let keys = ["imdbID", "imdbId", "imdb_id", "imdbUrlRef", "imdbURL", "imdbUrl", "imdb_url", "imdbLink"]
        let nested = ["data", "result", "results", "video", "details", "metadata", "items"]
        func visit(_ object: Any, depth: Int) -> String? {
            guard depth < 6 else { return nil }
            if let list = object as? [Any] {
                for item in list.prefix(8) { if let match = visit(item, depth: depth+1) { return match } }
                return nil
            }
            guard let row = object as? [String: Any] else { return nil }
            for key in keys {
                if let value = row[key] as? String, let match = imdbID(in: value) { return match }
            }
            for key in nested {
                if let value = row[key], let match = visit(value, depth: depth+1) { return match }
            }
            return nil
        }
        return visit(json, depth: 0)
    }

    static func requestURL(imdbID: String, season: Int, episode: Int, duration: Double) -> URL? {
        guard let imdbID = Self.imdbID(in: imdbID), season > 0, episode > 0,
              duration.isFinite, duration >= 300 else { return nil }
        var parts = URLComponents(string: "https://api.skipdb.tv/api/segments")
        parts?.queryItems = [URLQueryItem(name: "imdb_id", value: imdbID),
                             URLQueryItem(name: "season", value: String(season)),
                             URLQueryItem(name: "episode", value: String(episode)),
                             URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
                             URLQueryItem(name: "type", value: "intro")]
        return parts?.url
    }

    /// SkipDB returns approved timestamps in milliseconds. Reject unsupported stream
    /// versions and low-confidence matches rather than skip part of a real scene.
    static func decodeIntro(_ payload: Any, duration: Double) -> VerifiedIntroSegment? {
        guard duration.isFinite && duration >= 300,
              let response = payload as? [String: Any],
              let segments = response["segments"] as? [String: Any],
              let intro = segments["intro"] as? [String: Any],
              let start = (intro["start_ms"] as? NSNumber)?.doubleValue,
              let end = (intro["end_ms"] as? NSNumber)?.doubleValue else { return nil }
        let match = (intro["match"] as? String ?? "").lowercased()
        let confidence = (intro["confidence"] as? NSNumber)?.doubleValue ?? 0
        guard (match == "exact" || match == "shifted"), confidence >= 0.65 else { return nil }
        let startSeconds = start / 1000
        let endSeconds = end / 1000
        guard startSeconds.isFinite, endSeconds.isFinite, startSeconds >= 0,
              endSeconds > startSeconds + 5, endSeconds - startSeconds <= 300,
              endSeconds < duration - 1 else { return nil }
        return VerifiedIntroSegment(start: startSeconds, end: endSeconds, source: "SkipDB")
    }

    static func skipDestination(current: Double, duration: Double, segment: VerifiedIntroSegment?) -> Double? {
        guard let segment, current.isFinite, current >= max(0, segment.start - 4),
              current < segment.end - 2, segment.end < duration else { return nil }
        return segment.end
    }
}
