import Foundation

/// Explicit app-language setting is independent of the iPhone's system locale.
enum CinemanaLocale {
    static var isArabic: Bool {
        let language = UserDefaults.standard.string(forKey: "cinemana-app-language") ?? "system"
        return language == "ar" || (language == "system" && Locale.current.languageCode == "ar")
    }

    static func text(_ english: String) -> String {
        guard isArabic,
              let path = Bundle.main.path(forResource: "ar", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return english }
        return bundle.localizedString(forKey: english, value: english, table: "Localizable")
    }

    static func error(_ message: String) -> String {
        let translated = text(message)
        if isArabic && translated == message &&
           message.range(of: "[a-zA-Z]", options: .regularExpression) != nil {
            return "تعذّر إكمال الطلب. تحقّق من الاتصال وحاول مجدداً."
        }
        return translated
    }

    static func season(_ number: Int) -> String {
        isArabic ? "الموسم \(number)" : "Season \(number)"
    }

    static func episode(_ season: Int, _ number: Int) -> String {
        isArabic ? "الموسم \(season) · الحلقة \(number)" : "Season \(season) · Episode \(number)"
    }

    static func genre(_ english: String) -> String {
        guard isArabic else { return english }
        let names = [
            "Action": "أكشن", "Adventure": "مغامرة", "Animation": "رسوم متحركة",
            "Comedy": "كوميديا", "Crime": "جريمة", "Documentary": "وثائقي",
            "Drama": "دراما", "Family": "عائلي", "Fantasy": "خيال",
            "History": "تاريخ", "Horror": "رعب", "Music": "موسيقى",
            "Mystery": "غموض", "Romance": "رومانسي", "Science Fiction": "خيال علمي",
            "Sci-Fi": "خيال علمي", "Thriller": "إثارة", "War": "حرب",
            "Western": "غرب أمريكي", "Biography": "سيرة ذاتية",
            "Sport": "رياضة", "Sports": "رياضة", "Reality": "واقعي",
            "Kids": "أطفال", "News": "أخبار", "Talk": "حواري",
            "Soap": "دراما يومية", "War & Politics": "حرب وسياسة",
            "Action & Adventure": "أكشن ومغامرة", "Sci-Fi & Fantasy": "خيال علمي وفانتازيا"
        ]
        return names[english] ?? text(english)
    }
}

struct Video: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let arabicTitle: String
    let overview: String
    let arabicOverview: String?
    let year: String
    let rating: Double?
    let kind: String
    let poster: URL?
    let backdrop: URL?
    let genres: [String]
    /// Optional parental classification (not the IMDb rating).
    let ageRating: String?
    /// Provider-supplied adult content flag, if present.
    let adultFlag: Bool?
    /// Provider IMDb identifier, when available; never inferred from the title.
    let imdbID: String?
    let season: Int
    let episode: Int

    /// Treat common provider type aliases as series; episode records are not series roots.
    var isSeries: Bool {
        ["2", "series", "tv", "tvshow", "tv-show", "tv series", "show"].contains(
            kind.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var localizedTitle: String {
        CinemanaLocale.isArabic && !arabicTitle.isEmpty ? arabicTitle : title
    }
    var localizedOverview: String {
        if CinemanaLocale.isArabic, let arabicOverview, !arabicOverview.isEmpty {
            return arabicOverview
        }
        return overview
    }

    static func == (a: Video, b: Video) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    init?(json: [String: Any]) {
        func s(_ names: String...) -> String {
            for name in names {
                if let value = json[name] as? String, !value.isEmpty { return value }
                if let value = json[name] as? NSNumber { return value.stringValue }
            }
            return ""
        }
        let id = s("nb", "id", "videoId", "video_id", "videoNb", "episodeId", "episode_id")
        let title = s("en_title", "englishTitle", "enTitle", "english_title", "title", "name")
        let arabic = s("ar_title", "arabicTitle", "arTitle", "arabic_title")
        guard !id.isEmpty, !(title.isEmpty && arabic.isEmpty) else { return nil }
        self.id = id
        self.title = title.isEmpty ? arabic : title
        self.arabicTitle = arabic
        self.overview = s("en_content", "englishContent", "enContent", "description", "overview", "ar_content")
        let arabicSynopsis = s("ar_content", "arabicContent", "arDescription", "arabic_description")
        self.arabicOverview = arabicSynopsis.isEmpty ? nil : arabicSynopsis
        self.year = s("year")
        self.kind = s("kind", "videoKind", "video_kind")
        self.rating = Double(s("stars", "rating", "imdbRating"))
        let img = s("img", "imageUrl", "imageURL")
        let poster = s("imgMediumThumbObjUrl", "imageThumbMediumUrl", "imageMediumThumbUrl", "poster",
                       "imgThumbObjUrl", "imageThumbUrl", "imgObjUrl", "imageObjUrl", "img")
        let backdrop = s("imgObjUrl", "imageObjUrl", "img", "imageUrl")
        self.poster = URL(string: poster.isEmpty ? img : poster)
        self.backdrop = URL(string: backdrop.isEmpty ? poster : backdrop)
        self.season = Int(s("season", "seasonNumber", "seasonNummer", "season_number", "seasonNb")) ?? 1
        self.episode = Int(s("episodeNummer", "episodeNumber", "episode", "episodeNb", "episode_number", "episodeNo")) ?? 0
        let cats = json["categories"] ?? json["genres"] ?? json["genre"]
        if let strings = cats as? [String] { self.genres = strings }
        else if let strings = cats as? String { self.genres = strings.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        else if let objects = cats as? [[String: Any]] {
            self.genres = objects.compactMap { ($0["en_title"] ?? $0["name"] ?? $0["title"]) as? String }
        } else { self.genres = [] }
        let rating = s("ageRating", "age_rating", "contentRating", "content_rating",
                       "parentalRating", "parental_rating", "certification", "certificate",
                       "mpaa", "mpaa_rating", "tvRating", "tv_rating", "rated")
        self.ageRating = rating.isEmpty ? nil : rating
        func adultValue(_ value: Any?) -> Bool? {
            guard let value else { return nil }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                switch string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
                case "true", "yes", "1", "adult", "explicit", "mature": return true
                case "false", "no", "0": return false
                default: return nil
                }
            }
            return nil
        }
        let flags = ["adult", "isAdult", "is_adult", "mature", "isMature",
                     "is_mature", "explicit", "isExplicit", "is_explicit", "pornographic"]
            .compactMap { adultValue(json[$0]) }
        self.adultFlag = flags.contains(true) ? true : flags.first
        let imdb = s("imdb_id", "imdbId", "imdbID", "imdb", "imdb_code")
        self.imdbID = imdb.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) != nil
            ? imdb.lowercased() : nil
    }
}

struct CatalogRow: Identifiable, Codable, Sendable {
    let title: String
    let videos: [Video]
    var id: String { title }
}

struct Stream: Identifiable, Hashable, Sendable {
    let url: URL
    let quality: Int
    var id: String { url.absoluteString }
    var label: String { quality == 0 ? CinemanaLocale.text("Auto") : "\(quality)p" }
    var playableOnIOS: Bool {
        let ext = url.pathExtension.lowercased()
        // AVPlayer supports HLS and supported progressive media, not MPEG-DASH manifests.
        return ["", "m3u8", "mp4", "m4v", "mov", "mp3", "m4a", "aac"].contains(ext)
    }
}

struct Subtitle: Identifiable, Sendable {
    let name: String
    let url: URL
    var id: String { url.absoluteString }
}

enum SearchType: String, CaseIterable, Identifiable {
    case all = "All", movies = "Movies", series = "Series"
    var id: String { rawValue }
}

enum SearchOrder: String, CaseIterable, Identifiable {
    case relevance = "Relevance", newest = "Newest", rating = "Top rated", title = "A–Z"
    var id: String { rawValue }
}

struct SearchOptions: Equatable {
    var type: SearchType = .all
    var recent: Bool = false
    var minRating: Double = 0
    var genre: String = ""
    var sort: SearchOrder = .relevance

    func apply(_ videos: [Video]) -> [Video] {
        let filtered = videos.filter { v in
            (type == .all || (type == .movies ? v.kind == "1" : v.kind == "2")) &&
            (!recent || (Int(v.year) ?? 0) >= 2025) &&
            (minRating == 0 || (v.rating ?? -1) >= minRating) &&
            (genre.isEmpty || v.genres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame })
        }
        switch sort {
        case .relevance: return filtered
        case .newest: return filtered.sorted { (Int($0.year) ?? -1) > (Int($1.year) ?? -1) }
        case .rating: return filtered.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

// Personal library state is stored only on the device, never sent to the content provider.
struct PlaybackRecord: Codable, Identifiable, Sendable {
    var video: Video
    var seconds: Double
    var duration: Double
    var updatedAt: Date
    var id: String { video.id }
    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, seconds / duration))
    }
}

struct LibrarySnapshot: Codable, Sendable {
    var favorites: [Video] = []
    var recent: [PlaybackRecord] = []
}
