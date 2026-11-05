import Foundation

/// A *timed* segment supplied by the stream provider; never inferred from a title's age rating.
struct SceneSkipRange: Equatable, Sendable {
    let start: Double
    let end: Double
    let category: String
    var identifier: String { "\(start)-\(end)-\(category)" }
}

enum SceneSkipPlanner {
    /// Decode approved, explicit time ranges only. Missing scene timing means no skipping.
    /// Accepted keys intentionally exclude ordinary chapters, advertisements, and genre tags.
    private static let collectionKeys: Set<String> = [
        "matureScenes", "mature_scenes", "adultScenes", "adult_scenes",
        "explicitScenes", "explicit_scenes", "sensitiveScenes", "sensitive_scenes",
        "matureSegments", "mature_segments", "explicitSegments", "explicit_segments"
    ]
    private static let matureKinds: Set<String> = ["adult", "mature", "explicit", "nudity", "sexual", "sexual-content", "intimacy"]

    static func time(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        guard let string = raw as? String else { return nil }
        if let direct = Double(string) { return direct }
        let parts = string.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 && parts.count <= 3 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func field(_ row: [String: Any], _ keys: [String]) -> Any? {
        keys.compactMap { row[$0] }.first
    }

    static func decode(_ json: Any) -> [SceneSkipRange] {
        var result: [SceneSkipRange] = []
        func visit(_ value: Any, marked: Bool, depth: Int) {
            guard depth < 10, result.count < 200 else { return }
            if let rows = value as? [Any] {
                for row in rows { visit(row, marked: marked, depth: depth + 1) }
                return
            }
            guard let row = value as? [String: Any] else { return }
            let category = (field(row, ["type", "kind", "category", "label"]) as? String ?? "mature")
                .lowercased().replacingOccurrences(of: " ", with: "-")
            if marked || matureKinds.contains(category) {
                let from = time(field(row, ["start", "startTime", "start_time", "from", "begin", "beginTime"]))
                let to = time(field(row, ["end", "endTime", "end_time", "to", "finish", "finishTime"]))
                if let from, let to, from.isFinite && to.isFinite && from >= 0 && to > from && to - from < 30 * 60 {
                    result.append(SceneSkipRange(start: from, end: to, category: category))
                }
            }
            for (key, child) in row {
                if collectionKeys.contains(key) {
                    visit(child, marked: true, depth: depth + 1)
                } else if ["data", "result", "results", "video", "details", "metadata", "chapters", "segments"].contains(key) {
                    visit(child, marked: false, depth: depth + 1)
                }
            }
        }
        visit(json, marked: false, depth: 0)
        return result.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    static func active(_ ranges: [SceneSkipRange], at time: Double, duration: Double) -> SceneSkipRange? {
        guard time.isFinite && time >= 0 else { return nil }
        return ranges.first { $0.start <= time && time < $0.end - 0.4 && (duration <= 0 || $0.end < duration) }
    }

    /// Optional intro marker from provider chapter metadata. An untyped chapter
    /// called "Opening"/"Intro" is not treated as a *mature-scene* marker.
    static func introEnd(_ json: Any) -> Double? {
        let keys = ["introEnd", "introEndsAt", "intro_end", "openingEnd", "opening_end"]
        var result: Double?
        func visit(_ value: Any, depth: Int) {
            guard depth < 8, result == nil else { return }
            if let rows = value as? [Any] { for row in rows { visit(row, depth: depth + 1) }; return }
            guard let row = value as? [String: Any] else { return }
            for key in keys {
                if let number = time(row[key]), number >= 10 && number < 900 { result = number; return }
            }
            if let kind = field(row, ["type", "label", "title", "name"]) as? String,
               ["intro", "opening", "op", "opening credits"].contains(kind.lowercased()),
               let end = time(field(row, ["end", "endTime", "end_time", "to"])), end > 10 && end < 900 {
                result = end; return
            }
            for key in ["data", "result", "results", "chapters", "segments", "video", "metadata"] {
                if let nested = row[key] { visit(nested, depth: depth + 1) }
            }
        }
        visit(json, depth: 0)
        return result
    }

    /// A real provider intro timestamp is the only valid destination. There is no
    /// fixed-time fallback: jumping 90 seconds is *not* intro detection.
    static func introDestination(current: Double, duration: Double, marker: Double?) -> (time: Double, estimated: Bool)? {
        guard let marker, current.isFinite, current >= 0, marker.isFinite,
              marker > current + 2, marker < duration - 1,
              current <= min(420, duration * 0.30) else { return nil }
        return (marker, false)
    }
}
