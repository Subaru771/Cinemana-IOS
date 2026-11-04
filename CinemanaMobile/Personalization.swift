import Foundation

/// Personal viewing metadata. Never sent to the catalog provider or a developer server.
struct WatchCollection: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var videoIDs: [String] = []
}

struct ChapterMarkers: Codable, Equatable, Sendable {
    var introEndsAt: Double? = nil
    var recapEndsAt: Double? = nil
    var creditsBeginAt: Double? = nil

    func validFor(_ duration: Double) -> Bool {
        let values = [introEndsAt, recapEndsAt, creditsBeginAt].compactMap { $0 }
        return values.allSatisfy { $0.isFinite && $0 >= 0 && (duration <= 0 || $0 <= duration) }
    }
}

struct LocalViewingData: Codable, Sendable {
    var watched: [String: Date] = [:]
    var collections: [WatchCollection] = []
    var markers: [String: ChapterMarkers] = [:]
    var saveHistory: Bool = true

    // A separate storage key preserves compatibility with all existing 1.x library JSON.
    static let key = "cinemana-ios-personal-data-v2"
}

enum ViewingPlanner {
    static func recommendations(candidates: [Video], favorites: [Video], recent: [PlaybackRecord],
                                completed: Set<String>, limit: Int = 16) -> [Video] {
        let liked = favorites + recent.map(\.video)
        let preferredGenres = liked.flatMap(\.genres).reduce(into: [String: Int]()) { map, name in
            let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty { map[normalized, default: 0] += 1 }
        }
        let excluded = Set(liked.map(\.id)).union(completed)
        let unique = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.values.filter { !excluded.contains($0.id) }.sorted { a, b in
            func score(_ video: Video) -> Double {
                let genreScore = video.genres.reduce(0.0) { acc, genre in
                    acc + Double(min(4, preferredGenres[genre.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), default: 0]))
                }
                return genreScore * 3 + min(10, video.rating ?? 0) * 0.35
            }
            let ascore = score(a), bscore = score(b)
            return ascore == bscore ? a.title < b.title : ascore > bscore
        }.prefix(max(0, limit)).map { $0 }
    }

    static func shouldOfferSkip(position: Double, end: Double?, duration: Double) -> Bool {
        guard let end, end.isFinite, position.isFinite, position >= 0 else { return false }
        return end > position + 2 && end >= 3 && (duration <= 0 || end < duration)
    }

    static func nextUnwatched(episodes: [Video], watched: Set<String>) -> Video? {
        episodes.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
            .first { !watched.contains($0.id) }
    }
}
