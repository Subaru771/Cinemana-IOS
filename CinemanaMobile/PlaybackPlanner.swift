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

    /// Prefer a genuine HLS master with adaptive bitrate, not an unknown progressive file.
    static func adaptivePreferred(from streams: [Stream]) -> Stream? {
        streams.first { $0.playableOnIOS && $0.quality == 0 &&
            $0.url.pathExtension.lowercased() == "m3u8" }
            ?? preferred(from: streams)
    }

    static func explainFailure(_ raw: String?) -> String {
        let reason = (raw ?? "").lowercased()
        if reason.contains("403") || reason.contains("451") || reason.contains("forbidden") {
            return "The provider denied access to this stream. Check your network/provider permissions."
        }
        if reason.contains("401") || reason.contains("unauthorized") {
            return "This stream requires provider authorization."
        }
        if reason.contains("timed out") || reason.contains("timeout") {
            return "The media server timed out. Try again on a stable connection."
        }
        if reason.contains("unsupported") || reason.contains("format") {
            return "The source format is not supported by this iOS player."
        }
        if reason.contains("offline") || reason.contains("internet") {
            return "You appear to be offline. Reconnect or play a downloaded copy."
        }
        return "Check the connection, or choose another available quality and retry."
    }

    /// Combine choices from independent provider endpoints without keeping
    /// duplicate URLs or discarding qualities only exposed by one server.
    static func mergeStreamSources(_ groups: [[Stream]]) -> [Stream] {
        var seen = Set<String>()
        return groups.flatMap { $0 }
            .sorted { $0.quality > $1.quality }
            .filter { seen.insert($0.id).inserted }
    }

    /// A download resolution is an actual upper bound, not just a preference.
    /// Unknown/Auto sources cannot guarantee a cap, so exclude those for bounded
    /// downloads.
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
