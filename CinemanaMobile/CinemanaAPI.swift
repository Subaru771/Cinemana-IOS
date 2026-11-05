import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** Provider connectivity remains subject to its actual network/ISP authorization. */
struct CinemanaAPI: Sendable {
    static let shared = CinemanaAPI()
    private let base = "https://cinemana.shabakaty.com/api/android/"
    private let collectionKeys: Set<String> = [
        "data", "result", "results", "items", "videos", "video", "movies", "films", "banner",
        "banners", "rows", "content", "list", "episodes", "episodeList", "season", "seasons", "seasonList", "files", "qualities",
        "transcodedFiles", "transcoddedFiles"
    ]

    enum APIError: LocalizedError {
        case unauthorized, providerRestricted, server(Int), invalidResponse, unreachable, noStream, noEpisodes(String)
        var errorDescription: String? {
            switch self {
            case .unauthorized, .providerRestricted, .unreachable:
                return "Can't connect right now. Check your connection and try again."
            case .server, .invalidResponse:
                return "Something went wrong loading this. Please try again."
            case .noStream: return "This video isn't available to play right now."
            case .noEpisodes(let diagnostics): return "No playable episodes were found. " + diagnostics
            }
        }
    }

    private func segment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10
        config.timeoutIntervalForResource = 30
        #if canImport(Darwin)
        config.waitsForConnectivity = false
        #endif
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    private func fetch(_ path: String, timeout: TimeInterval = 10, ttl: TimeInterval = 0) async throws -> Any {
        if ttl > 0, let cached = await ResponseCache.shared.get(path, maxAge: ttl),
           let object = try? JSONSerialization.jsonObject(with: cached, options: [.fragmentsAllowed]) {
            return object
        }
        guard let url = URL(string: base + path) else { throw APIError.invalidResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        req.setValue("CinemanaMobile/\(version) (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Self.session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.unauthorized
            case 403, 451: throw APIError.providerRestricted
            default: throw APIError.server(http.statusCode)
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                if ttl > 0 { await ResponseCache.shared.put(path, data: data) }
                return object
            } catch {
                // A 200 response containing HTML is not a successful JSON response.
                throw APIError.invalidResponse
            }
        } catch let known as APIError { throw known }
        catch is CancellationError { throw CancellationError() }
        catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            throw APIError.unreachable
        }
        catch { throw APIError.unreachable }
    }

    private func videos(_ input: Any, limit: Int = 120) -> [Video] {
        var seen = Set<String>()
        var result = [Video]()
        func visit(_ item: Any, depth: Int) {
            if depth > 5 || result.count >= limit { return }
            if let array = item as? [Any] {
                for element in array { visit(element, depth: depth + 1) }
            } else if let obj = item as? [String: Any] {
                if let video = Video(json: obj), seen.insert(video.id).inserted { result.append(video) }
                for (key, value) in obj where collectionKeys.contains(key) { visit(value, depth: depth + 1) }
            }
        }
        visit(input, depth: 0)
        return result
    }

    private enum CatalogPart: Sendable { case trending0, trending1, new0, new1, top }

    private struct CatalogPage: Sendable {
        let kind: Int
        let part: CatalogPart
        let videos: [Video]?
        let failure: APIError?
    }

    /// Delivers catalog rows one by one as soon as each is ready, so the first
    /// row appears after the fastest request instead of the slowest.
    func catalogStream(_ kind: Int? = nil) -> AsyncThrowingStream<CatalogRow, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                let kinds = kind.map { [$0] } ?? [1, 2]
                let specs: [(CatalogPart, String, Int)] = [
                    (.trending0, "views_desc", 0), (.new0, "desc", 0), (.top, "stars_desc", 0),
                    (.trending1, "views_desc", 1), (.new1, "desc", 1)
                ]
                var restriction: APIError?
                var emitted = 0
                var parts: [Int: [String: [Video]]] = [:]

                func label(_ k: Int) -> String { k == 1 ? "Movies" : "Series" }
                func emit(_ base: String, _ k: Int, _ items: [Video]) {
                    guard !items.isEmpty else { return }
                    emitted += 1
                    continuation.yield(CatalogRow(title: "\(base) \(label(k))", videos: items))
                }
                func unique(_ lists: [Video]...) -> [Video] {
                    var seen = Set<String>()
                    return lists.flatMap { $0 }.filter { seen.insert($0.id).inserted }
                }
                func looksSortedByRating(_ items: [Video]) -> Bool {
                    let values = items.compactMap(\.rating)
                    guard values.count >= 6 else { return false }
                    var ordered = 0
                    for index in 0..<(values.count - 1) where values[index] >= values[index + 1] { ordered += 1 }
                    return Double(ordered) >= 0.8 * Double(values.count - 1)
                }
                func partKey(_ part: CatalogPart) -> String {
                    switch part {
                    case .trending0: return "t0"
                    case .trending1: return "t1"
                    case .new0: return "n0"
                    case .new1: return "n1"
                    case .top: return "top"
                    }
                }

                await withTaskGroup(of: CatalogPage.self) { group in
                    for k in kinds {
                        for (part, sort, page) in specs {
                            group.addTask {
                                do {
                                    let json = try await fetch("video/videoKind/\(k)/categoryNb/0/langNb/0/sortParam/\(sort)/itemsPerPage/20/searchTextValue/-/pageNumber/\(page)", timeout: 10, ttl: 60)
                                    return CatalogPage(kind: k, part: part,
                                                       videos: videos(fetchOrThrow: json, kind: String(k)), failure: nil)
                                } catch {
                                    return CatalogPage(kind: k, part: part, videos: nil,
                                                       failure: (error as? APIError) ?? .unreachable)
                                }
                            }
                        }
                    }
                    for await page in group {
                        if Task.isCancelled { group.cancelAll(); break }
                        guard let fetched = page.videos else {
                            if let failure = page.failure {
                                switch failure {
                                case .unauthorized, .providerRestricted: restriction = failure
                                default: break
                                }
                            }
                            continue
                        }
                        var items = fetched
                        // Ignore a "top rated" list the provider did not really sort by rating.
                        if page.part == .top && !looksSortedByRating(items) { items = [] }
                        parts[page.kind, default: [:]][partKey(page.part)] = items
                        let have = parts[page.kind] ?? [:]
                        switch page.part {
                        case .trending0: emit("Trending", page.kind, items)
                        case .new0, .new1:
                            emit("New", page.kind, unique(have["n0"] ?? [], have["n1"] ?? []))
                        case .top: emit("Top Rated", page.kind, items)
                        case .trending1: break
                        }
                    }
                }

                if !Task.isCancelled {
                    // Extra sections built from everything that was fetched.
                    let year = Calendar.current.component(.year, from: Date())
                    for k in kinds {
                        let have = parts[k] ?? [:]
                        let pool = unique(have["t0"] ?? [], have["t1"] ?? [], have["n0"] ?? [],
                                          have["n1"] ?? [], have["top"] ?? [])
                        let byRating: (Video, Video) -> Bool = { ($0.rating ?? 0) > ($1.rating ?? 0) }
                        if (have["top"] ?? []).isEmpty {
                            let rated = pool.filter { ($0.rating ?? 0) >= 6.5 }.sorted(by: byRating)
                            emit("Top Rated", k, Array(rated.prefix(30)))
                        }
                        let trendingIDs = Set((have["t0"] ?? []).map(\.id))
                        emit("Popular", k, (have["t1"] ?? []).filter { !trendingIDs.contains($0.id) })
                        let recent = pool.filter { (Int($0.year) ?? 0) >= year - 2 && ($0.rating ?? 0) >= 6 }
                            .sorted(by: byRating)
                        if recent.count >= 6 { emit("Recent Hit", k, Array(recent.prefix(30))) }
                        let classics = pool.filter { (Int($0.year) ?? 9999) <= 2005 && ($0.rating ?? 0) >= 6 }
                            .sorted(by: byRating)
                        if classics.count >= 6 { emit("Classic", k, Array(classics.prefix(30))) }
                        var byGenre: [String: [Video]] = [:]
                        for video in pool {
                            for genre in video.genres {
                                let name = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty {
                                    byGenre[name, default: []].append(video)
                                }
                            }
                        }
                        let topGenres = byGenre.filter { $0.value.count >= 8 }.sorted {
                            $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key
                        }.prefix(4)
                        for (name, items) in topGenres { emit(name, k, Array(items.prefix(30))) }
                    }
                }

                if emitted == 0 {
                    continuation.finish(throwing: restriction ?? APIError.unreachable)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    func catalog(_ kind: Int? = nil) async throws -> [CatalogRow] {
        var rows: [String: CatalogRow] = [:]
        for try await row in catalogStream(kind) { rows[row.title] = row }
        return rows.values.sorted { $0.sortKey < $1.sortKey }
    }

    func search(_ text: String) async throws -> [Video] {
        let query = Data(text.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let (output, success, restriction) = await withTaskGroup(of: Result<[Video], Error>.self) { group in
            for kind in [1, 2] {
                group.addTask {
                    do {
                        let path = "video/V/2/videoKind/\(kind)/itemsPerPage/20/video_title_search/\(segment(query))"
                        let json = try await fetch(path)
                        return .success(videos(fetchOrThrow: json, kind: String(kind)))
                    } catch { return .failure(error) }
                }
            }
            var output = [Video]()
            var success = 0
            var restriction: APIError?
            for await result in group {
                switch result {
                case .success(let items): output += items; success += 1
                case .failure(let error):
                    if let reason = error as? APIError {
                        switch reason {
                        case .unauthorized, .providerRestricted: restriction = reason
                        default: break
                        }
                    }
                }
            }
            return (output, success, restriction)
        }
        if success == 0 { throw restriction ?? APIError.unreachable }
        var seen = Set<String>()
        return output.filter { seen.insert($0.id).inserted }
    }

    private func videos(fetchOrThrow json: Any, kind: String) -> [Video] {
        // A type-scoped endpoint is authoritative even when response omits `kind`.
        videos(json).map { item in
            guard item.kind != kind, var fields = self.record(item) else { return item }
            fields["kind"] = kind
            return Video(json: fields) ?? item
        }
    }

    private func record(_ video: Video) -> [String: Any]? {
        // No need to reconstruct the entire original payload for display/search sorting.
        var fields: [String: Any] = ["nb": video.id, "en_title": video.title,
            "ar_title": video.arabicTitle, "en_content": video.overview,
            "year": video.year, "kind": video.kind,
            "stars": video.rating.map { String($0) } ?? "",
            "img": video.poster?.absoluteString ?? "",
            "imgObjUrl": video.backdrop?.absoluteString ?? "",
            "season": String(video.season),
            "episodeNummer": String(video.episode), "categories": video.genres]
        if let rating = video.ageRating { fields["ageRating"] = rating }
        if let adult = video.adultFlag { fields["adult"] = adult }
        return fields
    }

    func detail(_ fallback: Video) async -> Video {
        await detailIfAvailable(fallback) ?? fallback
    }

    /// The provider's full record, or nil when it could not be loaded.
    func detailIfAvailable(_ fallback: Video) async -> Video? {
        do {
            let json = try await fetch("allVideoInfo/id/\(segment(fallback.id))", timeout: 8, ttl: 600)
            return videos(json, limit: 1).first ?? fallback
        } catch { return nil }
    }

    /// Episode parsing is isolated and testable. Only media records underneath
    /// episode collections are playable; a season wrapper or series root is not.
    /// Provider schemas differ between series, seasons and individual entries.
    static func decodeEpisodes(_ raw: Any, seriesID: String) -> [Video] {
        let episodeKeys: Set<String> = ["episodes", "episodeList", "episode_list", "episodeVideos",
            "videos", "videoList", "video_list", "videoSeason", "videoSeasons", "items", "entries"]
        let seasonKeys: Set<String> = ["seasons", "seasonList", "season_list", "videoSeasons", "videoSeason", "season"]
        let containerKeys: Set<String> = ["data", "result", "results", "list", "content", "response"]
        let allKeys = episodeKeys.union(seasonKeys).union(containerKeys)
        // Preserve the provider's raw episode numbers until the full collection
        // is known. Some seasons start at zero; others start at one.
        var candidates: [(fields: [String: Any], season: Int, episode: Int)] = []
        var unique = Set<String>()

        func digits(_ value: Any?) -> Int? {
            if let n = value as? NSNumber { return n.intValue }
            guard let str = value as? String else { return nil }
            if let direct = Int(str.trimmingCharacters(in: .whitespaces)) { return direct }
            let matched = str.range(of: #"[0-9]+"#, options: .regularExpression)
            return matched.flatMap { Int(str[$0]) }
        }
        func number(_ row: [String: Any], keys: [String]) -> Int? {
            for k in keys { if let n = digits(row[k]) { return n } }
            return nil
        }
        func scalar(_ row: [String: Any], keys: [String]) -> String? {
            for k in keys {
                if let text = row[k] as? String, !text.isEmpty { return text }
                if let n = row[k] as? NSNumber { return n.stringValue }
            }
            return nil
        }
        func walk(_ value: Any, season: Int, ordinal: Int?, inEpisodes: Bool, depth: Int) {
            guard depth <= 14, candidates.count < 2000 else { return }
            if let list = value as? [Any] {
                for (index, child) in list.enumerated() {
                    walk(child, season: season, ordinal: index+1, inEpisodes: inEpisodes, depth: depth+1)
                }
                return
            }
            guard let row = value as? [String: Any] else { return }
            // A scalar `season` is metadata, not a nested collection. Treating
            // every row with a `season` key as a parent made the real provider's
            // flat {nb, season, episodeNummer} records disappear completely.
            let hasChildren = row.contains { key, value in
                allKeys.contains(key) && (value is [Any] || value is [String: Any])
            }
            let isSeasonContainer = (ordinal != nil && !inEpisodes) ||
                row.keys.contains(where: { seasonKeys.contains($0) }) ||
                (hasChildren && !row.keys.contains(where: { episodeKeys.contains($0) }))
            let seasonNumber = number(row, keys: ["seasonNumber", "seasonNummer", "season_number",
                "seasonNb", "seasonNo", "seasonIndex", "season"])
                ?? (isSeasonContainer ? (ordinal ?? season) : season)
            let episodeNumber = number(row, keys: ["episodeNumber", "episodeNummer", "episode_number",
                "episodeNb", "episodeNo", "episodeIndex", "ep", "episode"])
                ?? ((inEpisodes && !hasChildren) ? ordinal : nil)

            // Some provider responses omit episode title or label. The ID must be
            // present, and a fallback title is generated only for genuine episodes.
            // Important: the first episode may reuse the series catalog ID.
            // Do not discard it solely because identity == seriesID: the
            // explicit episode number identifies a playable episode record.
            if inEpisodes, !hasChildren, let ep = episodeNumber, ep >= 0,
               let identity = scalar(row, keys: ["nb", "id", "videoId", "video_id", "videoNb", "episodeId", "episode_id"]),
               !unique.contains(identity) {
                var fields = row
                fields["season"] = max(1, seasonNumber)
                fields["kind"] = "2"
                // A lone catalog root without an episode number and without
                // a position in an episode array is never a playable episode.
                candidates.append((fields: fields, season: max(1, seasonNumber), episode: ep))
                unique.insert(identity)
            }
            for (key, child) in row where allKeys.contains(key) {
                if let list = child as? [Any], seasonKeys.contains(key) {
                    // A `videoSeason` value can itself be an episode list or a
                    // group of season wrappers. Inspect the entries, not its name.
                    for (index, wrapper) in list.enumerated() {
                        let isEpisode = (wrapper as? [String: Any]).map { entry in
                            let nested = entry.contains { k, v in
                                allKeys.contains(k) && (v is [Any] || v is [String: Any])
                            }
                            // Some seasons supply an ordered list of episode IDs
                            // without explicit episode numbers. Use the list index.
                            return number(entry, keys: ["episodeNumber", "episodeNummer", "episodeNb", "episodeNo", "episode"]) != nil
                                || (!nested && scalar(entry, keys: ["nb", "id", "videoId", "episodeId"]) != nil)
                        } ?? false
                        walk(wrapper, season: seasonNumber, ordinal: index+1,
                             inEpisodes: isEpisode, depth: depth+1)
                    }
                } else {
                    walk(child, season: seasonNumber, ordinal: nil,
                         inEpisodes: episodeKeys.contains(key) || (inEpisodes && !seasonKeys.contains(key)), depth: depth+1)
                }
            }
        }
        walk(raw, season: 1, ordinal: nil, inEpisodes: true, depth: 0)
        // A provider may number a season 0,1,2... instead of 1,2,3... .
        // Normalize that season as a group so two source entries never both
        // become "Episode 1". Do not shift correctly numbered seasons.
        let zeroBasedSeasons = Set(candidates.filter { $0.episode == 0 }.map(\.season))
        let entries: [Video] = candidates.compactMap { candidate in
            var row = candidate.fields
            let normalized = candidate.episode + (zeroBasedSeasons.contains(candidate.season) ? 1 : 0)
            row["episodeNummer"] = normalized
            if scalar(row, keys: ["en_title", "englishTitle", "enTitle", "english_title", "title", "name", "ar_title", "arabicTitle"]) == nil {
                row["title"] = "Episode \(normalized)"
            }
            return Video(json: row)
        }
        return entries.sorted { ($0.season, $0.episode, $0.id) < ($1.season, $1.episode, $1.id) }
    }

    /// Diagnostic summary contains only array counts and field names; it never
    /// copies streaming URLs or untrusted response bodies into the UI.
    static func episodePayloadSummary(_ json: Any) -> String {
        if let items = json as? [Any] {
            let fields = (items.first as? [String: Any])?.keys.sorted().prefix(12).joined(separator: ",") ?? "none"
            return "array count=\(items.count), fields=\(fields)"
        }
        if let object = json as? [String: Any] {
            let keys = object.keys.sorted().prefix(12).joined(separator: ",")
            let nested = ["episodes", "videoSeason", "seasons", "data", "result", "items"]
                .compactMap { key -> String? in
                    guard let collection = object[key] as? [Any] else { return nil }
                    return "\(key)=\(collection.count)"
                }.joined(separator: ",")
            return "object fields=\(keys)\(nested.isEmpty ? "" : "; " + nested)"
        }
        if json is NSNull { return "null JSON" }
        return "unexpected \(String(describing: type(of: json))) response"
    }

    /// Do not silently return an empty collection. Report whether the provider
    /// returned an empty list or a shape the parser could not understand.
    func episodesDetailed(_ id: String) async throws -> [Video] {
        var reports: [String] = []
        for (name, path) in [
            ("videoSeason", "videoSeason/id/\(segment(id))"),
            ("allVideoInfo", "allVideoInfo/id/\(segment(id))")
        ] {
            do {
                let payload = try await fetch(path, timeout: 12, ttl: 0)
                let episodes = Self.decodeEpisodes(payload, seriesID: id)
                if !episodes.isEmpty { return episodes }
                reports.append("\(name): \(Self.episodePayloadSummary(payload))")
            } catch is CancellationError { throw CancellationError() }
            catch {
                if let api = error as? APIError {
                    switch api {
                    case .unauthorized, .providerRestricted: throw api
                    case .server(let code): reports.append("\(name): HTTP \(code)")
                    case .invalidResponse: reports.append("\(name): invalid JSON")
                    case .unreachable: reports.append("\(name): network unreachable")
                    default: reports.append("\(name): request failed")
                    }
                } else { reports.append("\(name): request failed") }
            }
        }
        // The id is an ordinary public catalog ID, useful for diagnosing cases
        // where the provider's season endpoint expects a different series ID.
        throw APIError.noEpisodes("Series ID \(id). " + reports.joined(separator: " | "))
    }

    func episodes(_ id: String) async -> [Video] { (try? await episodesDetailed(id)) ?? [] }

    /// Optional provider chapter metadata; nil/empty when the provider has no
    /// time-coded scenes. We do NOT guess scene boundaries from age ratings.
    func playbackSkipMarkers(_ id: String) async -> (scenes: [SceneSkipRange], introEnd: Double?, imdbID: String?) {
        do {
            let response = try await fetch("allVideoInfo/id/\(segment(id))", timeout: 7, ttl: 600)
            return (SceneSkipPlanner.decode(response), SceneSkipPlanner.introEnd(response), CommunitySkipTimes.imdbID(in: response))
        } catch { return ([], nil, nil) }
    }

    /// Public SkipDB read API; requests only the IMDb title ID, season/episode and
    /// playback length, never the user's name, history, or app credentials.
    /// Caller must require the user's explicit opt-in first.
    func communityIntro(imdbID: String, season: Int, episode: Int, duration: Double) async -> VerifiedIntroSegment? {
        guard let url = CommunitySkipTimes.requestURL(imdbID: imdbID, season: season,
                                                      episode: episode, duration: duration) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  body.count < 64_000,
                  let payload = try? JSONSerialization.jsonObject(with: body) else { return nil }
            return CommunitySkipTimes.decodeIntro(payload, duration: duration)
        } catch { return nil }
    }

    func related(_ id: String) async -> [Video] {
        do { return videos(try await fetch("relatedVideos/id/\(segment(id))", timeout: 8, ttl: 300)) }
        catch { return [] }
    }

    private func validMediaURL(_ candidate: String?) -> URL? {
        guard let candidate, let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        let ext = url.pathExtension.lowercased()
        guard !["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(ext) else { return nil }
        return url
    }

    private func quality(_ text: String) -> Int { Self.parseQuality(text) }

    /// Maps a provider label ("1080p", "FHD", "4K", "720") to a known resolution.
    /// Unknown numbers (for example "Server 2") are treated as Auto (0) instead of a tiny resolution.
    static func parseQuality(_ text: String) -> Int {
        let text = text.lowercased()
        if text.contains("4k") || text.contains("2160") { return 2160 }
        if text.contains("1080") || text.contains("fhd") { return 1080 }
        if text.contains("720") || text == "hd" { return 720 }
        if text.contains("480") || text == "sd" { return 480 }
        if text.contains("360") { return 360 }
        if text.contains("240") { return 240 }
        return 0
    }

    private func parseStreams(_ root: Any) -> [Stream] {
        let keys: Set<String> = ["data", "results", "items", "files", "qualities", "videoFile", "videoFiles",
                                 "transcodedFiles", "transcoddedFiles", "video", "sources", "streams"]
        let paths = ["videoUrl", "videoURL", "url", "file", "path", "src", "link", "videoFileUrl"]
        var collected = [Stream]()
        var seen = Set<String>()
        func add(_ text: String?, quality: Int) {
            guard let url = validMediaURL(text), seen.insert(url.absoluteString).inserted else { return }
            collected.append(Stream(url: url, quality: quality))
        }
        func visit(_ value: Any, depth: Int, quality: Int) {
            if depth > 5 || collected.count >= 35 { return }
            if let arr = value as? [Any] { arr.forEach { visit($0, depth: depth + 1, quality: quality) } }
            else if let dict = value as? [String: Any] {
                let value = dict["resolution"] ?? dict["quality"] ?? dict["height"] ?? dict["name"] ?? dict["label"]
                let named = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
                let current = named.isEmpty ? quality : self.quality(named)
                for key in paths { if let text = dict[key] as? String { add(text, quality: current) } }
                for (k, v) in dict where keys.contains(k) { visit(v, depth: depth + 1, quality: current) }
                for (k, v) in dict where self.quality(k) > 0 {
                    if let url = v as? String { add(url, quality: self.quality(k)) }
                }
            } else if let text = value as? String { add(text, quality: quality) }
        }
        visit(root, depth: 0, quality: 0)
        return collected.sorted { $0.quality > $1.quality }
    }

    /// Playback returns promptly; download source selection can request a more
    /// complete list, including qualities only returned by the slower endpoint.
    /// Neither path is allowed to stall forever. Provider restrictions are respected.
    func streams(_ id: String, preferComplete: Bool = false) async throws -> [Stream] {
        if !preferComplete, let cached = await PlaybackStreamCache.shared.get(id) {
            return cached
        }
        let encoded = segment(id)
        let paths = ["transcoddedfiles/id/\(encoded)", "allVideoInfo/id/\(encoded)"]
        let timeoutNanos: UInt64 = preferComplete ? 6_000_000_000 : 2_500_000_000
        enum Outcome {
            case sources([Stream])
            case failed(APIError)
            case deadline
        }
        let result = await withTaskGroup(of: Outcome.self) { group -> (streams: [Stream], restriction: APIError?) in
            for path in paths {
                group.addTask {
                    do {
                        let value = try await fetch(path, timeout: preferComplete ? 6 : 3)
                        return .sources(parseStreams(value).filter(\.playableOnIOS))
                    } catch let problem as APIError { return .failed(problem) }
                    catch { return .failed(.unreachable) }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return .deadline
            }
            var sources = [[Stream]]()
            var finishedEndpoints = 0
            var restriction: APIError?
            for await outcome in group {
                if Task.isCancelled { break }
                var finish = false
                switch outcome {
                case .sources(let streams):
                    finishedEndpoints += 1
                    if !streams.isEmpty {
                        sources.append(streams)
                        // Playback takes the first valid endpoint immediately.
                        // Downloads still aggregate sources to expose all qualities.
                        if !preferComplete { finish = true }
                    }
                case .failed(let problem):
                    finishedEndpoints += 1
                    switch problem {
                    case .unauthorized, .providerRestricted: restriction = problem
                    default: break
                    }
                case .deadline:
                    finish = true
                }
                if finish || finishedEndpoints == paths.count { break }
            }
            group.cancelAll()
            return (PlaybackPlanner.mergeStreamSources(sources), restriction)
        }
        if Task.isCancelled { throw CancellationError() }
        guard !result.streams.isEmpty else { throw result.restriction ?? APIError.noStream }
        await PlaybackStreamCache.shared.put(result.streams, for: id)
        return result.streams
    }

    func invalidateStreams(_ id: String) async {
        await PlaybackStreamCache.shared.remove(id)
    }
    // MARK: Subtitles

    /// External SRT/VTT subtitle files the provider publishes for a title (may be empty).
    func subtitles(_ id: String) async -> [Subtitle] {
        for path in ["translationFiles/id/\(segment(id))", "allVideoInfo/id/\(segment(id))"] {
            if let json = try? await fetch(path) {
                let found = parseSubtitles(json)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private func parseSubtitles(_ root: Any) -> [Subtitle] {
        var found = [Subtitle]()
        var seen = Set<String>()
        func visit(_ value: Any, depth: Int) {
            if depth > 6 || found.count >= 40 { return }
            if let list = value as? [Any] {
                list.forEach { visit($0, depth: depth + 1) }
            } else if let dict = value as? [String: Any] {
                let declared = ((dict["extention"] ?? dict["extension"] ?? dict["type"]) as? String)?.lowercased() ?? ""
                let file = (dict["file"] ?? dict["url"] ?? dict["path"] ?? dict["link"]) as? String
                if let file, let url = URL(string: file),
                   url.scheme?.lowercased().hasPrefix("http") == true,
                   ["srt", "vtt"].contains(url.pathExtension.lowercased()) || ["srt", "vtt"].contains(declared),
                   seen.insert(file).inserted {
                    let label = (dict["name"] ?? dict["language"] ?? dict["label"] ?? dict["lang"]) as? String
                    let name = (label?.isEmpty == false) ? label! : "Subtitle \(found.count + 1)"
                    found.append(Subtitle(name: name, url: url))
                }
                for (_, child) in dict where child is [Any] || child is [String: Any] {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(root, depth: 0)
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

    
/// Bounded, in-memory cache. No persistence of expiring/signed streaming URLs.
private actor PlaybackStreamCache {
    static let shared = PlaybackStreamCache()
    private var entries: [String: (date: Date, streams: [Stream])] = [:]
    func get(_ id: String) -> [Stream]? {
        guard let entry = entries[id], Date().timeIntervalSince(entry.date) < 90 else {
            entries.removeValue(forKey: id)
            return nil
        }
        return entry.streams
    }
    func put(_ streams: [Stream], for id: String) {
        if entries.count > 40 { entries.removeAll() }
        entries[id] = (Date(), streams)
    }
    func remove(_ id: String) { entries.removeValue(forKey: id) }
}


/// Short-lived memory cache for catalog, detail and episode responses so
/// revisiting a screen is instant. Stream URLs are never stored here.
private actor ResponseCache {
    static let shared = ResponseCache()
    private var entries: [String: (date: Date, data: Data)] = [:]
    func get(_ key: String, maxAge: TimeInterval) -> Data? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.date) < maxAge else { return nil }
        return entry.data
    }
    func put(_ key: String, data: Data) {
        if entries.count > 80 { entries.removeAll() }
        entries[key] = (Date(), data)
    }
}
