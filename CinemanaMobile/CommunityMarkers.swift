import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A validated community intro/recap window. Missing metadata never implies a skip.
struct CommunitySegment: Sendable, Hashable {
    let kind: String
    let start: Double
    let end: Double
    let confidence: Double
    let source: String
    var autoEligible: Bool { confidence >= 0.8 }
    func contains(_ time: Double) -> Bool {
        time.isFinite && time >= max(0, start - 1) && time < end - 0.5
    }
}

actor CommunityMarkerService {
    static let shared = CommunityMarkerService()
    private var cache: [String: (Date, [CommunitySegment])] = [:]

    func segments(for video: Video, duration: Double) async -> [CommunitySegment] {
        guard let imdb = video.imdbID, duration.isFinite, duration >= 60 else { return [] }
        let season = video.episode > 0 ? video.season : 0
        let episode = max(0, video.episode)
        let key = "\(imdb)-\(season)-\(episode)-\(Int(duration))"
        if let entry = cache[key], Date().timeIntervalSince(entry.0) < 3600 { return entry.1 }

        let providers: [(String, String, [URLQueryItem])] = [
            ("SkipDB", "https://api.skipdb.tv/api/segments", [
                URLQueryItem(name: "imdb_id", value: imdb),
                URLQueryItem(name: "duration", value: "\(Int(duration.rounded()))"),
                URLQueryItem(name: "adjust", value: "conservative")
            ]),
            ("TheIntroDB", "https://api.theintrodb.org/v4/media", [
                URLQueryItem(name: "imdb_id", value: imdb),
                URLQueryItem(name: "duration_ms", value: "\(Int((duration * 1000).rounded()))")
            ])
        ]
        var result: [CommunitySegment] = []
        for (source, endpoint, query) in providers {
            guard var components = URLComponents(string: endpoint) else { continue }
            components.queryItems = query + (episode > 0 ? [
                URLQueryItem(name: "season", value: "\(season)"),
                URLQueryItem(name: "episode", value: "\(episode)")
            ] : [])
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 7
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), data.count <= 524288,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if source == "SkipDB" {
                guard let segments = json["segments"] as? [String: Any] else { continue }
                for kind in ["intro", "recap"] {
                    guard let record = segments[kind] as? [String: Any],
                          let start = (record["start_ms"] as? NSNumber)?.doubleValue,
                          let end = (record["end_ms"] as? NSNumber)?.doubleValue,
                          let confidence = (record["confidence"] as? NSNumber)?.doubleValue,
                          ["exact", "shifted"].contains(record["match"] as? String ?? ""),
                          let segment = Self.validated(kind, start / 1000, end / 1000, confidence, duration, source)
                    else { continue }
                    result.append(segment)
                }
            } else {
                for kind in ["intro", "recap"] {
                    guard let records = json[kind] as? [[String: Any]] else { continue }
                    for record in records {
                        let start = (record["start_ms"] as? NSNumber)?.doubleValue ?? 0
                        guard let end = (record["end_ms"] as? NSNumber)?.doubleValue else { continue }
                        let confidence = (record["confidence"] as? NSNumber)?.doubleValue ?? 0.85
                        if let segment = Self.validated(kind, start / 1000, end / 1000,
                                                        confidence, duration, source) {
                            result.append(segment)
                        }
                    }
                }
            }
        }
        var distinct: [CommunitySegment] = []
        for item in result.sorted(by: { $0.confidence > $1.confidence }) {
            if distinct.contains(where: { $0.kind == item.kind && abs($0.start - item.start) <= 3 }) { continue }
            distinct.append(item)
        }
        let answer = distinct.sorted { $0.start < $1.start }
        cache[key] = (Date(), answer)
        return answer
    }

    static func validated(_ kind: String, _ start: Double, _ end: Double,
                          _ confidence: Double, _ duration: Double, _ source: String) -> CommunitySegment? {
        guard kind == "intro" || kind == "recap",
              start.isFinite, end.isFinite, confidence.isFinite,
              confidence >= 0.70 && confidence <= 1, start >= 0,
              end - start > 0.5, end - start <= 300,
              start < duration - 1, end <= duration + 3 else { return nil }
        return CommunitySegment(kind: kind, start: start, end: min(end, duration),
                                confidence: confidence, source: source)
    }
}

/// Preloads next-episode stream metadata, not video bytes; no hidden media download.
actor NextEpisodePreloader {
    static let shared = NextEpisodePreloader()
    private var ready: [String: [Stream]] = [:]

    func warm(_ video: Video) async {
        guard ready[video.id] == nil else { return }
        if let streams = try? await CinemanaAPI.shared.streams(video.id), !streams.isEmpty {
            ready = [video.id: streams]
        }
    }

    func take(_ id: String) -> [Stream]? {
        defer { ready.removeValue(forKey: id) }
        return ready[id]
    }
}
