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

    /// Combine sources without duplicating URLs or hiding a resolution only
    /// exposed by one of the provider endpoints.
    static func mergeStreamSources(_ groups: [[Stream]]) -> [Stream] {
        var seen = Set<String>()
        return groups.flatMap { $0 }
            .sorted { $0.quality > $1.quality }
            .filter { seen.insert($0.id).inserted }
    }

    /// Strict download ceiling; unknown qualities cannot guarantee a limit.
    static func downloadStream(from streams: [Stream], maximumQuality: Int) -> Stream? {
        let supported = DownloadPolicy.supported(streams)
        if maximumQuality == Int.max {
            return supported.filter { $0.quality > 0 }.max(by: { $0.quality < $1.quality })
                ?? supported.first
        }
        guard maximumQuality > 0 else { return nil }
        return supported.filter { $0.quality > 0 && $0.quality <= maximumQuality }
            .max(by: { $0.quality < $1.quality })
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

    /// The episode that follows `current` in season/episode order, if any.
    static func nextEpisode(after current: Video, in episodes: [Video]) -> Video? {
        let ordered = episodes.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard let index = ordered.firstIndex(where: { $0.id == current.id }),
              index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }
}
