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
        case unauthorized, providerRestricted, server(Int), invalidResponse, unreachable, noStream, noEpisodes
        var errorDescription: String? {
            switch self {
            case .unauthorized: return "The content provider requires authorization."
            case .providerRestricted: return "This network is not authorized to access the provider."
            case .server(let code): return "Provider server responded with HTTP \(code)."
            case .invalidResponse: return "The provider returned an unsupported response."
            case .unreachable: return "Cannot reach the provider on this network."
            case .noStream: return "No compatible video stream is available."
            case .noEpisodes: return "The provider returned no episode records for this series. Please retry or check the source."
            }
        }
    }

    private func segment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func fetch(_ path: String, timeout: TimeInterval = 18) async throws -> Any {
        guard let url = URL(string: base + path) else { throw APIError.invalidResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        req.setValue("CinemanaMobile/\(version) (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.unauthorized
            case 403, 451: throw APIError.providerRestricted
            default: throw APIError.server(http.statusCode)
            }
            do {
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
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

    func catalog(_ kind: Int? = nil) async throws -> [CatalogRow] {
        let kinds = kind.map { [$0] } ?? [1, 2]
        let (rows, failures, restriction) = await withTaskGroup(of: Result<(String, [Video]), Error>.self) { group in
            for k in kinds {
                for (sort, heading) in [("views_desc", "Trending"), ("desc", "New")] {
                    let title = "\(heading) \(k == 1 ? "Movies" : "Series")"
                    group.addTask {
                        do {
                            let json = try await fetch("video/videoKind/\(k)/categoryNb/0/langNb/0/sortParam/\(sort)/itemsPerPage/20/searchTextValue/-/pageNumber/0")
                            return .success((title, videos(fetchOrThrow: json, kind: String(k))))
                        } catch { return .failure(error) }
                    }
                }
            }
            var rows = [CatalogRow]()
            var failures = 0
            var restriction: APIError?
            for await awaitResult in group {
                switch awaitResult {
                case .success(let (title, items)):
                    if !items.isEmpty { rows.append(CatalogRow(title: title, videos: items)) }
                case .failure(let error):
                    failures += 1
                    if let reason = error as? APIError {
                        switch reason {
                        case .unauthorized, .providerRestricted: restriction = reason
                        default: break
                        }
                    }
                }
            }
            return (rows, failures, restriction)
        }
        if rows.isEmpty && failures == kinds.count * 2 { throw restriction ?? APIError.unreachable }
        let order = ["Trending Movies", "New Movies", "Trending Series", "New Series"]
        return rows.sorted { (order.firstIndex(of: $0.title) ?? 99) < (order.firstIndex(of: $1.title) ?? 99) }
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
        do {
            let json = try await fetch("allVideoInfo/id/\(segment(fallback.id))")
            return videos(json, limit: 1).first ?? fallback
        } catch { return fallback }
    }

    /// Decode season wrappers and nested episode lists, retaining the season number.
    /// Do not mistake a series description (episode == 0) for a playable episode.
    static func decodeEpisodes(_ raw: Any, seriesID: String) -> [Video] {
        let childKeys = ["episodes", "episodeList", "videos", "videoList", "items", "seasons", "seasonList", "season", "result", "results", "data", "list"]
        var found = [Video]()
        var seen = Set<String>()
        func numeric(_ input: Any?) -> Int? {
            if let number = input as? NSNumber { return number.intValue }
            if let string = input as? String { return Int(string) }
            return nil
        }
        func walk(_ entry: Any, season: Int, episodeIndex: Int?, insideList: Bool, depth: Int) {
            guard depth <= 10, found.count < 1500 else { return }
            if let items = entry as? [Any] {
                for (index, child) in items.enumerated() {
                    walk(child, season: season, episodeIndex: index + 1,
                         insideList: insideList, depth: depth + 1)
                }
                return
            }
            guard let object = entry as? [String: Any] else { return }
            let seasonNumber = numeric(object["seasonNumber"]) ?? numeric(object["season_number"])
                ?? numeric(object["seasonNummer"]) ?? numeric(object["seasonNb"])
                ?? numeric(object["season"]) ?? season
            let explicitEpisode = numeric(object["episodeNumber"]) ?? numeric(object["episodeNummer"])
                ?? numeric(object["episodeNb"]) ?? numeric(object["episode_number"])
                ?? numeric(object["episode"])
            let looksLikeSeason = childKeys.prefix(7).contains(where: { object[$0] != nil })
            // The provider sometimes omits episodeNummer inside an episodes array.
            let ordinal = (explicitEpisode ?? 0) > 0
                ? explicitEpisode
                : (insideList && !looksLikeSeason ? episodeIndex : nil)
            // An E1 numbered zero still occupies the first position in the episode array.
            if let ordinal, ordinal > 0, !looksLikeSeason {
                var fields = object
                fields["episodeNummer"] = ordinal
                fields["season"] = seasonNumber
                fields["kind"] = "2"
                if let video = Video(json: fields),
                   (video.id != seriesID || episodeIndex != nil),
                   seen.insert(video.id).inserted { found.append(video) }
            }
            for key in childKeys {
                guard let child = object[key] else { continue }
                let isEpisodeList = ["episodes", "episodeList", "videos", "videoList", "items"].contains(key)
                walk(child, season: seasonNumber, episodeIndex: nil,
                     insideList: isEpisodeList, depth: depth + 1)
            }
        }
        walk(raw, season: 1, episodeIndex: nil, insideList: true, depth: 0)
        return found.sorted { ($0.season, $0.episode, $0.id) < ($1.season, $1.episode, $1.id) }
    }

    /// The first episode may be omitted from the season response; look for
    /// an E1 in embedded detail episodes before accepting an incomplete list.
    static func missingFirstEpisode(_ episodes: [Video]) -> Bool {
        guard let season = episodes.map(\.season).min() else { return false }
        return !episodes.contains { $0.season == season && $0.episode == 1 }
    }

    static func mergeEpisodes(_ primary: [Video], backup: [Video]) -> [Video] {
        var merged = primary
        var ids = Set(primary.map(\.id))
        var positions = Set(primary.map { "\($0.season):\($0.episode)" })
        for episode in backup {
            let position = "\(episode.season):\(episode.episode)"
            guard !ids.contains(episode.id), !positions.contains(position) else { continue }
            merged.append(episode)
            ids.insert(episode.id)
            positions.insert(position)
        }
        return merged.sorted { ($0.season, $0.episode, $0.id) < ($1.season, $1.episode, $1.id) }
    }

    func episodesDetailed(_ id: String) async throws -> [Video] {
        var firstError: Error?
        var result = [Video]()
        for path in ["videoSeason/id/\(segment(id))", "allVideoInfo/id/\(segment(id))"] {
            do {
                let raw = try await fetch(path, timeout: 14)
                result = Self.mergeEpisodes(result, backup: Self.decodeEpisodes(raw, seriesID: id))
                if !result.isEmpty && !Self.missingFirstEpisode(result) { return result }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstError == nil { firstError = error }
                if let status = error as? APIError {
                    switch status {
                    case .unauthorized, .providerRestricted:
                        if !result.isEmpty { return result }
                        throw status
                    default: break
                    }
                }
            }
        }
        if !result.isEmpty { return result }
        if let firstError { throw firstError }
        throw APIError.noEpisodes
    }

    func episodes(_ id: String) async -> [Video] {
        (try? await episodesDetailed(id)) ?? []
    }

    func related(_ id: String) async -> [Video] {
        do { return videos(try await fetch("relatedVideos/id/\(segment(id))")) }
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
