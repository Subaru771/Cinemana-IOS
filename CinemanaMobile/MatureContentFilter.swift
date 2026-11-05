import Foundation

/// Thread-safe, persistent record of which titles the provider classifies as mature.
/// Many catalog list entries carry no classification, so the detail record is looked
/// up once per title and the answer is remembered on this device.
final class MatureVerdictStore: @unchecked Sendable {
    static let shared = MatureVerdictStore()
    private let lock = NSLock()
    private let defaultsKey = "cinemana-mature-verdicts-v3-verified"
    private var verdicts: [String: Bool]

    private init() {
        verdicts = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool]) ?? [:]
    }

    func verdict(for id: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return verdicts[id]
    }

    func record(_ id: String, mature: Bool) {
        lock.lock()
        verdicts[id] = mature
        if verdicts.count > 6000 {
            for key in verdicts.keys.prefix(1500) { verdicts.removeValue(forKey: key) }
        }
        let snapshot = verdicts
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    func recordMany(_ items: [(String, Bool)]) {
        guard !items.isEmpty else { return }
        lock.lock()
        for (id, mature) in items { verdicts[id] = mature }
        let snapshot = verdicts
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    func clear() {
        lock.lock(); verdicts = [:]; lock.unlock()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// On-device, metadata-based title filter. Not a frame-by-frame censor or age-verification lock.
enum MatureContentFilter {
    static let preferenceKey = "cinemana-hide-mature-content"
    /// Conservative behavior. When enabled, titles without a positively safe
    /// provider age rating stay hidden instead of briefly appearing during fetch.
    static let strictPreferenceKey = "cinemana-hide-unrated-content"
    private static let safeRatings: Set<String> = [
        "g", "pg", "pg-13", "tv-y", "tv-y7", "tv-g", "tv-pg", "tv-14",
        "u", "u-a", "ua", "all", "everyone", "general", "family",
        "0", "0+", "6", "6+", "7", "7+", "12", "12+", "13", "13+"
    ]

    private static let matureTags: Set<String> = [
        "adult", "adults only", "adult only", "adult content", "mature", "explicit",
        "explicit content", "sexual content", "nudity", "erotic", "erotica", "porn",
        "pornography", "hentai", "ecchi", "18+", "+18", "18 plus", "for adults", "xxx",
        "للكبار فقط", "للبالغين فقط", "للكبار", "للبالغين", "اباحي", "إباحي", "اباحية", "إباحية",
        "افلام للكبار", "أفلام للكبار", "افلام اباحية", "أفلام إباحية"
    ]
    private static let matureRatings: Set<String> = [
        "tv-ma", "nc-17", "r", "r18", "r18+", "r-18", "r-18+", "18", "18+", "+18",
        "18a", "21", "21+", "ao", "x", "xxx", "adult", "adults-only", "18-years",
        "restricted-18+", "restricted", "mature", "tvma", "ma", "18-plus", "18plus"
    ]
    private static let titleKeywords: [String] = [
        "porn", "hentai", "erotic", "18+", "+18", "اباحي", "إباحي", "للكبار فقط", "للبالغين فقط"
    ]

    private static func tag(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rating(_ text: String) -> String {
        tag(text).replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    static func isMatureTag(_ text: String) -> Bool { matureTags.contains(tag(text)) }

    /// True when the list or detail record itself says the title is mature.
    static func metadataSaysMature(_ video: Video) -> Bool {
        if video.adultFlag == true { return true }
        if let age = video.ageRating, matureRatings.contains(rating(age)) { return true }
        if video.genres.contains(where: { isMatureTag($0) }) { return true }
        let names = (video.title + " " + video.arabicTitle).lowercased()
        return titleKeywords.contains { names.contains($0) }
    }

    /// True when the record already carries a classification, so no lookup is needed.
    static func hasClassification(_ video: Video) -> Bool {
        video.adultFlag != nil || video.ageRating != nil
    }

    static func hasVerifiedSafeRating(_ video: Video) -> Bool {
        guard !metadataSaysMature(video), let age = video.ageRating else { return false }
        return safeRatings.contains(rating(age))
    }

    static func isMature(_ video: Video) -> Bool {
        if metadataSaysMature(video) { return true }
        return MatureVerdictStore.shared.verdict(for: video.id) == true
    }

    private static var strictPreference: Bool {
        (UserDefaults.standard.object(forKey: strictPreferenceKey) as? Bool) ?? true
    }

    static func allows(_ video: Video, hideMature: Bool, strict: Bool? = nil) -> Bool {
        guard hideMature else { return true }
        if isMature(video) { return false }
        guard strict ?? strictPreference else { return true }
        // A missing age classification cannot establish that a title is safe.
        return hasVerifiedSafeRating(video) || MatureVerdictStore.shared.verdict(for: video.id) == false
    }

    static func visible(_ videos: [Video], hideMature: Bool, strict: Bool? = nil) -> [Video] {
        videos.filter { allows($0, hideMature: hideMature, strict: strict) }
    }

    static func visibleRows(_ rows: [CatalogRow], hideMature: Bool, strict: Bool? = nil) -> [CatalogRow] {
        guard hideMature else { return rows }
        return rows.compactMap { row in
            let filtered = visible(row.videos, hideMature: true, strict: strict)
            return filtered.isEmpty ? nil : CatalogRow(title: row.title, videos: filtered)
        }
    }
}

#if canImport(Combine)
import Combine
/// Looks up the provider's full record for titles whose list entry has no
/// classification, then remembers the result so each title is checked once.
@MainActor
final class MatureClassifier: ObservableObject {
    @Published private(set) var revision = 0
    private var inFlight = Set<String>()
    private var unreachable = Set<String>()

    private var enabled: Bool { UserDefaults.standard.bool(forKey: MatureContentFilter.preferenceKey) }

    private func pending(_ videos: [Video]) -> [Video] {
        var seen = Set<String>()
        return videos.filter { video in
            !MatureContentFilter.hasClassification(video) &&
            !MatureContentFilter.metadataSaysMature(video) &&
            MatureVerdictStore.shared.verdict(for: video.id) == nil &&
            !inFlight.contains(video.id) && !unreachable.contains(video.id) &&
            seen.insert(video.id).inserted
        }
    }

    /// Starts checking in the background without waiting.
    func start(_ videos: [Video]) {
        guard enabled else { return }
        let todo = Array(pending(videos).prefix(300))
        guard !todo.isEmpty else { return }
        inFlight.formUnion(todo.map(\.id))
        Task { await self.run(todo) }
    }

    /// Checks and waits until finished or the timeout passes, so mature titles
    /// never flash on screen first. Anything unfinished keeps going in the background.
    func prepare(_ videos: [Video], timeout: Double = 2.5) async {
        guard enabled else { return }
        let todo = Array(pending(videos).prefix(300))
        guard !todo.isEmpty else { return }
        inFlight.formUnion(todo.map(\.id))
        let ids = Set(todo.map(\.id))
        Task { await self.run(todo) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !inFlight.isDisjoint(with: ids) {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
        }
    }

    private func run(_ videos: [Video]) async {
        let limit = 6
        var index = 0
        var foundMature = false
        await withTaskGroup(of: (String, Video?).self) { group in
            while index < min(limit, videos.count) {
                let item = videos[index]; index += 1
                group.addTask { (item.id, await CinemanaAPI.shared.detailIfAvailable(item)) }
            }
            while let (id, detail) = await group.next() {
                inFlight.remove(id)
                if let detail {
                    let mature = MatureContentFilter.metadataSaysMature(detail)
                    // Never promote an unclassified detail response to "safe".
                    if mature || MatureContentFilter.hasVerifiedSafeRating(detail) {
                        MatureVerdictStore.shared.record(id, mature: mature)
                    }
                    if mature { foundMature = true; revision += 1 }
                } else {
                    unreachable.insert(id)
                }
                if index < videos.count {
                    let item = videos[index]; index += 1
                    group.addTask { (item.id, await CinemanaAPI.shared.detailIfAvailable(item)) }
                }
            }
        }
        if !foundMature { revision += 1 }
    }
}

#endif // canImport(Combine)
