import Foundation

/// Optional, on-device catalog display filter. It never changes or deletes the provider's data.
/// It does NOT inspect individual video frames or guarantee a title contains no mature scenes.
enum MatureContentFilter {
    static let preferenceKey = "cinemana-hide-mature-content"

    // Match exact genre/tags, not arbitrary words in movie titles or descriptions.
    private static let matureTags: Set<String> = [
        "adult", "adults only", "adult only", "adult content", "mature",
        "explicit", "explicit content", "sexual content", "nudity", "erotic",
        "erotica", "porn", "pornography", "hentai", "ecchi", "18+", "+18",
        "للكبار فقط", "للبالغين فقط", "اباحي", "إباحي", "اباحية", "إباحية"
    ]
    private static let matureRatings: Set<String> = [
        "tv-ma", "nc-17", "r", "r18", "r18+", "r-18", "r-18+", "18", "18+",
        "18a", "21", "21+", "ao", "a", "x", "xxx", "adult", "adults-only",
        "18-years", "restricted-18+", "restricted", "adults-only"
    ]

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    static func isMature(_ video: Video) -> Bool {
        if video.adultFlag == true { return true }
        if let rating = video.ageRating, matureRatings.contains(normalized(rating)) { return true }
        return video.genres.contains { genre in
            matureTags.contains(genre.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func allows(_ video: Video, hideMature: Bool) -> Bool {
        !hideMature || !isMature(video)
    }

    static func visible(_ videos: [Video], hideMature: Bool) -> [Video] {
        hideMature ? videos.filter { !isMature($0) } : videos
    }

    static func visibleRows(_ rows: [CatalogRow], hideMature: Bool) -> [CatalogRow] {
        guard hideMature else { return rows }
        return rows.compactMap { row in
            let visible = row.videos.filter { !isMature($0) }
            return visible.isEmpty ? nil : CatalogRow(title: row.title, videos: visible)
        }
    }
}
