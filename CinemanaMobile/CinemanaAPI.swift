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
        "banners", "rows", "content", "list", "episodes", "season", "files", "qualities",
        "transcodedFiles", "transcoddedFiles"
    ]

    enum APIError: LocalizedError {
        case unauthorized, providerRestricted, server(Int), invalidResponse, unreachable, noStream
        var errorDescription: String? {
            switch self {
            case .unauthorized: return "The content provider requires authorization."
            case .providerRestricted: return "This network is not authorized to access the provider."
            case .server(let code): return "Provider server responded with HTTP \(code)."
            case .invalidResponse: return "The provider returned an unsupported response."
            case .unreachable: return "Cannot reach the provider on this network."
            case .noStream: return "No compatible video stream is available."
            }
        }
    }

    private func segment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func fetch(_ path: String) async throws -> Any {
        guard let url = URL(string: base + path) else { throw APIError.invalidResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 18
        req.setValue("CinemanaMobile/1.2 (iOS)", forHTTPHeaderField: "User-Agent")
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
            guard item.kind.isEmpty, var fields = self.record(item) else { return item }
            fields["kind"] = kind
            return Video(json: fields) ?? item
        }
    }

    private func record(_ video: Video) -> [String: Any]? {
        // No need to reconstruct the entire original payload for display/search sorting.
        ["nb": video.id, "en_title": video.title, "ar_title": video.arabicTitle,
         "en_content": video.overview, "year": video.year, "kind": video.kind,
         "stars": video.rating.map { String($0) } ?? "", "img": video.poster?.absoluteString ?? "",
         "imgObjUrl": video.backdrop?.absoluteString ?? "", "season": String(video.season),
         "episodeNummer": String(video.episode), "categories": video.genres]
    }

    func detail(_ fallback: Video) async -> Video {
        do {
            let json = try await fetch("allVideoInfo/id/\(segment(fallback.id))")
            return videos(json, limit: 1).first ?? fallback
        } catch { return fallback }
    }

    func episodes(_ id: String) async -> [Video] {
        do {
            return videos(try await fetch("videoSeason/id/\(segment(id))"))
                .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        } catch { return [] }
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

    private func quality(_ text: String) -> Int {
        let text = text.lowercased()
        if text.contains("4k") || text.contains("2160") { return 2160 }
        if text.contains("1080") || text.contains("fhd") { return 1080 }
        if text.contains("720") || text == "hd" { return 720 }
        if text.contains("480") || text == "sd" { return 480 }
        let digits = text.split { !$0.isNumber }.first ?? ""
        return Int(digits) ?? 0
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

    func streams(_ id: String) async throws -> [Stream] {
        let direct = try? await fetch("transcoddedfiles/id/\(segment(id))")
        let streams = direct.map { parseStreams($0).filter(\.playableOnIOS) } ?? []
        if !streams.isEmpty { return streams }
        let fallback = parseStreams(try await fetch("allVideoInfo/id/\(segment(id))"))
            .filter(\.playableOnIOS)
        guard !fallback.isEmpty else { throw APIError.noStream }
        return fallback
    }
}
