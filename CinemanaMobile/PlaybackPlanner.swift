import Foundation

/// Deterministic, side-effect-free playback decisions; shared by the iOS UI and tests.
enum PlaybackPlanner {
    static func preferred(from streams: [Stream], maximumQuality: Int = 1080) -> Stream? {
        let playable = streams.filter(\.playableOnIOS)
        return playable.filter { $0.quality > 0 && $0.quality <= maximumQuality }
            .max(by: { $0.quality < $1.quality })
            ?? playable.first(where: { $0.quality == 0 })
            ?? playable.min(by: { $0.quality < $1.quality })
    }

    /// Prefer moving down in quality when a CDN source fails, not up to a larger stream.
    static func fallback(from streams: [Stream], failed: Stream, tried: Set<String>) -> Stream? {
        let available = streams.filter { $0.playableOnIOS && !tried.contains($0.id) }
        let lower = available.filter { $0.quality > 0 && $0.quality < failed.quality }
        return lower.max(by: { $0.quality < $1.quality })
            ?? available.first(where: { $0.quality == 0 })
            ?? available.min(by: { $0.quality < $1.quality })
    }

    static func playTarget(for series: Video, episodes: [Video], recent: [PlaybackRecord]) -> Video? {
        // Episodes are directly playable even though their kind is also "2".
        guard series.kind == "2" && series.episode == 0 else { return series }
        let ids = Set(episodes.map(\.id))
        if let resumed = recent.first(where: { ids.contains($0.id) && $0.fraction < 0.95 }),
           let matching = episodes.first(where: { $0.id == resumed.id }) { return matching }
        return episodes.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }.first
    }
}
