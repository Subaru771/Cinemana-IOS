import Foundation

@main
struct CoreSmokeTests {
    static func main() throws {
        let raw: [String: Any] = [
            "nb": "123", "en_title": "A Test Film", "kind": "1",
            "stars": "8.5", "year": "2026", "categories": ["Drama", "Adventure"],
            "imgMediumThumbObjUrl": "https://example.org/poster.jpg"
        ]
        guard let movie = Video(json: raw) else { fatalError("Parsing failed") }
        precondition(movie.id == "123")
        precondition(movie.title == "A Test Film")
        precondition(movie.rating == 8.5)
        precondition(movie.poster?.host == "example.org")
        precondition(movie.genres.count == 2)
        // Regressions from the One Piece report: series aliases and nested
        // provider season/episode records must not silently become empty.
        let seriesAlias = Video(json: ["id": "onepiece", "title": "One Piece", "kind": "series"])!
        precondition(seriesAlias.isSeries)
        let nested: [String: Any] = ["seasons": [
            ["seasonNumber": 1, "episodes": [
                ["id": "s1e1", "title": "Pilot"],
                ["id": "s1e2", "title": "Episode Two", "episodeNumber": 2]]],
            ["seasonNumber": 2, "episodes": [
                ["id": "s2e1", "title": "Season Two"]]]]]
        let nestedEpisodes = CinemanaAPI.decodeEpisodes(nested, seriesID: "onepiece")
        precondition(nestedEpisodes.map(\.id) == ["s1e1", "s1e2", "s2e1"])
        precondition(nestedEpisodes.map(\.season) == [1, 1, 2])
        precondition(nestedEpisodes.map(\.episode) == [1, 2, 1])
        precondition(CinemanaAPI.decodeEpisodes(["id": "onepiece", "title": "One Piece", "kind": "2"], seriesID: "onepiece").isEmpty)
        let flagged = Video(json: ["id": "restricted", "title": "Mature", "adult": true])!
        let teen = Video(json: ["id": "teen", "title": "Teen", "ageRating": "PG-13"])!
        precondition(MatureContentFilter.isMature(flagged))
        precondition(MatureContentFilter.allows(flagged, hideMature: false))
        precondition(MatureContentFilter.allows(flagged, hideMature: true))
        precondition(MatureContentFilter.allows(teen, hideMature: true))
        precondition(MatureContentFilter.visible([flagged, teen], hideMature: true).count == 2)
        let unrated = Video(json: ["id": "unrated", "title": "No rating", "adult": false])!
        precondition(MatureContentFilter.allows(unrated, hideMature: true, strict: true))
        precondition(MatureContentFilter.allows(unrated, hideMature: true, strict: false))
        precondition(MatureContentFilter.allows(unrated, hideMature: false, strict: true))
        // Films and series remain visible even if the old strict-hide setting is enabled.
        precondition(MatureContentFilter.visibleRows([
            CatalogRow(title: "Series", videos: [flagged, unrated, teen])
        ], hideMature: true, strict: true).first?.videos.count == 3)
        // Skipping a mature scene is legal only when the provider supplies an explicit range.
        let chapterJSON: [String: Any] = ["data": ["matureScenes": [
            ["start": "00:02:00", "end": "00:02:24", "type": "nudity"],
            ["start": 360, "end": 381, "type": "explicit"]],
            "introEnd": 105]]
        let timedScenes = SceneSkipPlanner.decode(chapterJSON)
        precondition(timedScenes.count == 2)
        precondition(timedScenes[0].start == 120 && timedScenes[0].end == 144)
        precondition(SceneSkipPlanner.active(timedScenes, at: 128, duration: 1200)?.end == 144)
        precondition(SceneSkipPlanner.active(timedScenes, at: 160, duration: 1200) == nil)
        precondition(SceneSkipPlanner.decode(["genres": ["Adult"], "ageRating": "18+"]).isEmpty)
        precondition(SceneSkipPlanner.introEnd(chapterJSON) == 105)
        let markedIntro = SceneSkipPlanner.introDestination(current: 30, duration: 1500, marker: 105)
        precondition(markedIntro?.time == 105 && markedIntro?.estimated == false)
        // No arbitrary +90 second fallback if precise timestamps are unavailable.
        precondition(SceneSkipPlanner.introDestination(current: 30, duration: 1500, marker: nil) == nil)
        precondition(CommunitySkipTimes.imdbID(in: "https://www.imdb.com/title/tt0944947/") == "tt0944947")
        precondition(CommunitySkipTimes.imdbID(in: "Game of Thrones") == nil)
        let withIMDb = Video(json: ["id": "got", "title": "Game of Thrones", "imdbUrlRef": "https://imdb.com/title/tt0944947/"])!
        precondition(withIMDb.imdbID == "tt0944947")
        precondition(CommunitySkipTimes.imdbID(in: ["data": ["imdbUrlRef": "https://www.imdb.com/title/tt0944947/"]]) == "tt0944947")
        let skipDBResponse: [String: Any] = ["segments": ["intro": ["start_ms": 61000, "end_ms": 91000,
            "match": "exact", "confidence": 0.93]]]
        let verified = CommunitySkipTimes.decodeIntro(skipDBResponse, duration: 2820)
        precondition(verified?.start == 61 && verified?.end == 91)
        precondition(CommunitySkipTimes.skipDestination(current: 70, duration: 2820, segment: verified) == 91)
        precondition(CommunitySkipTimes.skipDestination(current: 140, duration: 2820, segment: verified) == nil)
        let inaccurate: [String: Any] = ["segments": ["intro": ["start_ms": 61000, "end_ms": 91000,
            "match": "out-of-range", "confidence": 0.99]]]
        precondition(CommunitySkipTimes.decodeIntro(inaccurate, duration: 2820) == nil)
        precondition(CommunitySkipTimes.requestURL(imdbID: "tt0944947", season: 1, episode: 1, duration: 2820)?.host == "api.skipdb.tv")
        precondition(CommunitySkipTimes.requestURL(imdbID: "invalid", season: 1, episode: 1, duration: 2820) == nil)
        precondition(MatureContentFilter.hasVerifiedSafeRating(teen))
        precondition(!MatureContentFilter.hasVerifiedSafeRating(unrated))
        // Root lists, nested seasons, sequential episodes without titles,
        // and `videoSeason` arrays are explicitly supported.
        let roots: [String: Any] = ["seasons": [
            ["videoList": [["nb": "root-1", "episodeNummer": 1]]],
            ["episodeList": [["id": "root-2", "episodeNummer": 1]]]
        ]]
        let rootEpisodes = CinemanaAPI.decodeEpisodes(roots, seriesID: "root")
        precondition(rootEpisodes.map(\.season) == [1, 2])
        precondition(rootEpisodes.map(\.id) == ["root-1", "root-2"])
        precondition(rootEpisodes[0].title == "Episode 1")
        let wrapped: [String: Any] = ["data": ["videoSeason": [
            ["id": "wrapped1", "title": "First", "episodeNumber": 1],
            ["id": "wrapped2", "title": "Second", "episodeNumber": 2]
        ]]]
        precondition(CinemanaAPI.decodeEpisodes(wrapped, seriesID: "root").map(\.episode) == [1, 2])
        // Real Shabakaty videoSeason rows are flat and contain a scalar
        // `season`. This was erroneously classified as a nested collection.
        let flatProviderEpisodes: [[String: Any]] = [
            ["nb": 101, "season": 1, "episodeNummer": 1],
            ["nb": "102", "season": "1", "episodeNummer": "2"],
            ["nb": 103, "season": 2, "episodeNummer": 1]
        ]
        let flat = CinemanaAPI.decodeEpisodes(flatProviderEpisodes, seriesID: "onepiece")
        precondition(flat.map(\.id) == ["101", "102", "103"])
        precondition(flat.map(\.season) == [1, 1, 2])
        precondition(flat.map(\.episode) == [1, 2, 1])
        precondition(flat[0].title == "Episode 1")
        // Episode 1 can share the series ID; it is a playable row, not a
        // duplicate catalog root. This caused Episode 2 to appear first.
        let reusedSeriesID: [[String: Any]] = [
            ["nb": "got-series", "season": 1, "episodeNummer": 1],
            ["nb": "got-second", "season": 1, "episodeNummer": 2]
        ]
        let reusedResult = CinemanaAPI.decodeEpisodes(reusedSeriesID, seriesID: "got-series")
        precondition(reusedResult.map(\.id) == ["got-series", "got-second"])
        precondition(reusedResult.map(\.episode) == [1, 2])
        // Some catalogs number a season from zero; preserve both entries and
        // display one-based episode labels without creating duplicate numbers.
        let zeroBased: [[String: Any]] = [
            ["nb": "zero-first", "season": 1, "episodeNummer": 0],
            ["nb": "zero-second", "season": 1, "episodeNummer": 1]
        ]
        let normalized = CinemanaAPI.decodeEpisodes(zeroBased, seriesID: "series")
        precondition(normalized.map(\.episode) == [1, 2])
        precondition(normalized.map(\.id) == ["zero-first", "zero-second"])
        precondition(CinemanaAPI.episodePayloadSummary(flatProviderEpisodes).contains("count=3"))
        let keyWrapped: [String: Any] = ["data": ["videoSeason": flatProviderEpisodes]]
        precondition(CinemanaAPI.decodeEpisodes(keyWrapped, seriesID: "onepiece").map(\.id) == flat.map(\.id))
        let tvma = Video(json: ["id": "tvma", "title": "Late Show", "contentRating": "TV-MA"])!
        let arabicTag = Video(json: ["id": "ar-tag", "title": "Film", "categories": [["en_title": "Drama", "ar_title": "للكبار فقط"]]])!
        precondition(MatureContentFilter.isMature(tvma) && MatureContentFilter.isMature(arabicTag))
        precondition(arabicTag.genres == ["للكبار فقط"])
        let rowOrder = [CatalogRow(title: "Action Series", videos: []), CatalogRow(title: "New Movies", videos: []),
                        CatalogRow(title: "Trending Series", videos: []), CatalogRow(title: "Trending Movies", videos: [])]
            .sorted { $0.sortKey < $1.sortKey }.map(\.title)
        precondition(rowOrder == ["Trending Movies", "Trending Series", "New Movies", "Action Series"])
        // Old library JSON contains no age classifications: decoding stays backwards compatible.
        let oldVideo = try JSONEncoder().encode(movie)
        var payload = try JSONSerialization.jsonObject(with: oldVideo) as! [String: Any]
        payload.removeValue(forKey: "adultFlag")
        payload.removeValue(forKey: "ageRating")
        let restoredOldVideo = try JSONDecoder().decode(Video.self, from: JSONSerialization.data(withJSONObject: payload))
        precondition(restoredOldVideo.ageRating == nil && restoredOldVideo.adultFlag == nil)

        precondition(SearchOptions(minRating: 8).apply([movie]).count == 1)
        precondition(SearchOptions(minRating: 9).apply([movie]).isEmpty)
        precondition(SearchOptions(type: .series).apply([movie]).isEmpty)
        precondition(SearchOptions(type: .movies, recent: true, minRating: 8, genre: "drama").apply([movie]).count == 1)
        precondition(SearchOptions(recent: true, minRating: 9).apply([movie]).isEmpty)
        precondition(Stream(url: URL(string: "https://x.test/movie.mpd")!, quality: 1080).playableOnIOS == false)
        precondition(Stream(url: URL(string: "https://x.test/movie.m3u8")!, quality: 720).playableOnIOS)
        precondition(Stream(url: URL(string: "https://x.test/movie.mp4")!, quality: 720).playableOnIOS)
        precondition(Stream(url: URL(string: "https://x.test/movie.mkv")!, quality: 720).playableOnIOS == false)
        precondition(Stream(url: URL(string: "https://x.test/stream?id=1")!, quality: 720).playableOnIOS)
        precondition(Stream(url: URL(string: "https://x.test/movie.avi")!, quality: 720).playableOnIOS == false)
        let data = try JSONEncoder().encode(movie)
        let decoded = try JSONDecoder().decode(Video.self, from: data)
        precondition(decoded == movie)
        let row = CatalogRow(title: "Trending", videos: [movie])
        let rowBytes = try JSONEncoder().encode([row])
        let decodedRows = try JSONDecoder().decode([CatalogRow].self, from: rowBytes)
        precondition(decodedRows.first?.videos.count == 1)
        let record = PlaybackRecord(video: movie, seconds: 80, duration: 400, updatedAt: Date())
        precondition(abs(record.fraction - 0.2) < 0.0001)
        precondition(PlaybackRecord(video: movie, seconds: 900, duration: 400, updatedAt: Date()).fraction == 1)
        let lib = LibrarySnapshot(favorites: [movie], recent: [record])
        let libData = try JSONEncoder().encode(lib)
        let decodedLib = try JSONDecoder().decode(LibrarySnapshot.self, from: libData)
        precondition(decodedLib.recent.count == 1)
        let source2160 = Stream(url: URL(string: "https://cdn.example/2160.mp4")!, quality: 2160)
        let source1080 = Stream(url: URL(string: "https://cdn.example/1080.m3u8")!, quality: 1080)
        let source720 = Stream(url: URL(string: "https://cdn.example/720.m3u8")!, quality: 720)
        let unsupported = Stream(url: URL(string: "https://cdn.example/film.mpd")!, quality: 1080)
        let sources = [source2160, source1080, source720, unsupported]
        precondition(PlaybackPlanner.preferred(from: sources)?.id == source1080.id)
        precondition(PlaybackPlanner.preferred(from: [source2160, source720])?.id == source720.id)
        precondition(PlaybackPlanner.preferred(from: [source2160])?.id == source2160.id)
        precondition(PlaybackPlanner.preferred(from: [unsupported]) == nil)
        precondition(PlaybackPlanner.fallback(from: sources, failed: source1080,
                                              tried: [source1080.id])?.id == source720.id)
        precondition(PlaybackPlanner.fallback(from: sources, failed: source1080,
                                              tried: [source1080.id, source720.id])?.id == source2160.id)
        precondition(PlaybackPlanner.fallback(from: sources, failed: source720,
                                              tried: Set(sources.map(\.id))) == nil)
        precondition(CinemanaAPI.parseQuality("1080p") == 1080)
        precondition(CinemanaAPI.parseQuality("4K") == 2160)
        precondition(CinemanaAPI.parseQuality("HD") == 720)
        precondition(CinemanaAPI.parseQuality("360p") == 360)
        precondition(CinemanaAPI.parseQuality("Server 2") == 0)
        precondition(CinemanaAPI.parseQuality("") == 0)
        precondition(PlaybackPlanner.preferred(from: [source2160, source1080, source720], maximumQuality: 480)?.id == source720.id)
        precondition(PlaybackPlanner.preferred(from: [source2160, source1080, source720], maximumQuality: Int.max)?.id == source2160.id)
        let series = Video(json: ["nb": "series-1", "en_title": "Test Series", "kind": "2"])!
        let ep1 = Video(json: ["nb": "ep-1", "en_title": "Pilot", "kind": "2", "season": 1, "episode": 1])!
        let ep2 = Video(json: ["nb": "ep-2", "en_title": "Next", "kind": "2", "season": 1, "episode": 2])!
        precondition(PlaybackPlanner.playTarget(for: series, episodes: [ep2, ep1], recent: [])?.id == ep1.id)
        precondition(PlaybackPlanner.playTarget(for: series, episodes: [], recent: []) == nil)
        let savedEp2 = PlaybackRecord(video: ep2, seconds: 240, duration: 1000, updatedAt: Date())
        precondition(PlaybackPlanner.playTarget(for: series, episodes: [ep1, ep2], recent: [savedEp2])?.id == ep2.id)
        precondition(PlaybackPlanner.playTarget(for: movie, episodes: [], recent: [])?.id == movie.id)
        precondition(PlaybackPlanner.playTarget(for: ep1, episodes: [], recent: [])?.id == ep1.id)
        // v1.6.4: per-video download quality survives app restarts, and old
        // download index records (without requestedQuality) still decode.
        let requested = OfflineEntry(video: movie, status: .queued, format: nil,
            progress: 0, localPath: nil, bytesReceived: 0, bytesExpected: 0,
            message: nil, updatedAt: Date(), requestedQuality: 720)
        let requestedJSON = try JSONEncoder().encode(requested)
        let requestedRestored = try JSONDecoder().decode(OfflineEntry.self, from: requestedJSON)
        precondition(requestedRestored.requestedQuality == 720)
        var legacyRecord = try JSONSerialization.jsonObject(with: requestedJSON) as! [String: Any]
        legacyRecord.removeValue(forKey: "requestedQuality")
        let legacyJSON = try JSONSerialization.data(withJSONObject: legacyRecord)
        let decodedLegacyEntry = try JSONDecoder().decode(OfflineEntry.self, from: legacyJSON)
        precondition(decodedLegacyEntry.requestedQuality == nil)
        precondition(PlaybackPlanner.preferred(from: sources, maximumQuality: 720)?.id == source720.id)
        precondition(PlaybackPlanner.preferred(from: sources, maximumQuality: Int.max)?.id == source2160.id)

        // v1.6.5: download quality must never silently exceed the chosen maximum.
        precondition(PlaybackPlanner.downloadStream(from: sources, maximumQuality: 480) == nil)
        precondition(PlaybackPlanner.downloadStream(from: sources, maximumQuality: 720)?.quality == 720)
        precondition(PlaybackPlanner.downloadStream(from: sources, maximumQuality: 1080)?.quality == 1080)
        precondition(PlaybackPlanner.downloadStream(from: sources, maximumQuality: Int.max)?.quality == 2160)
        let unknown = Stream(url: URL(string: "https://cdn.example/unknown.mp4")!, quality: 0)
        precondition(PlaybackPlanner.downloadStream(from: [unknown], maximumQuality: 720) == nil)
        precondition(PlaybackPlanner.downloadStream(from: [unknown], maximumQuality: Int.max) != nil)
        let other = Stream(url: URL(string: "https://cdn.example/480.mp4")!, quality: 480)
        let combined = PlaybackPlanner.mergeStreamSources([[source1080], [other, source1080]])
        precondition(combined.count == 2)
        precondition(combined.first?.quality == 1080)
        precondition(combined.last?.quality == 480)
        let master = URL(string: "https://video.example/master.m3u8")!
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=650000,RESOLUTION=854x480
        480/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1700000,RESOLUTION=1280x720
        720/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080
        1080/index.m3u8
        """
        let renditions = HLSQuality.variants(in: playlist, relativeTo: master)
        precondition(renditions.count == 3)
        precondition(HLSQuality.choose(renditions, ceiling: 480)?.url.absoluteString == "https://video.example/480/index.m3u8")
        precondition(HLSQuality.choose(renditions, ceiling: 720)?.height == 720)
        precondition(HLSQuality.choose(renditions, ceiling: Int.max)?.height == 1080)
        precondition(HLSQuality.choose(renditions, ceiling: 360) == nil)
        // v1.5: next episode, subtitles, download paths and policy
        precondition(PlaybackPlanner.nextEpisode(after: ep1, in: [ep2, ep1])?.id == ep2.id)
        precondition(PlaybackPlanner.nextEpisode(after: ep2, in: [ep1, ep2]) == nil)
        precondition(PlaybackPlanner.nextEpisode(after: movie, in: [ep1, ep2]) == nil)
        let srt = "1\n00:00:01,000 --> 00:00:03,500\nHello <i>world</i>\n\n2\n00:00:04,000 --> 00:00:06,000\n{\\an8}Second line\nwraps\n"
        let cues = SubtitleParser.parse(srt)
        precondition(cues.count == 2)
        precondition(cues[0].text == "Hello world")
        precondition(cues[1].text == "Second line\nwraps")
        precondition(SubtitleParser.cue(at: 2, in: cues)?.start == 1)
        precondition(SubtitleParser.cue(at: 3.7, in: cues) == nil)
        precondition(SubtitleParser.cue(at: 5, in: cues)?.text.hasPrefix("Second") == true)
        precondition(SubtitleParser.cue(at: 0.2, in: cues) == nil)
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nHi\n\n"
        precondition(SubtitleParser.parse(vtt).first?.end == 2)
        precondition(SubtitleParser.decodeText(Data([0xEF, 0xBB, 0xBF, 0x68, 0x69])) == "hi")
        precondition(DownloadPolicy.format(for: URL(string: "https://x.test/a.m3u8")!) == .hls)
        precondition(DownloadPolicy.format(for: URL(string: "https://x.test/a.mp4")!) == .file)
        precondition(DownloadPolicy.format(for: URL(string: "https://x.test/a.mkv")!) == nil)
        let sample = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/x.mp4")
        precondition(OfflinePath.store(sample) == "Library/x.mp4")
        precondition(OfflinePath.resolve("Library/x.mp4").path.hasSuffix("/Library/x.mp4"))
        precondition(OfflineEntry.Status(rawValue: "ready") == .ready)
        precondition(OfflineEntry.Status(rawValue: "queued") == .queued)
        precondition(ByteFormat.duration(75) == "1 min")
        // v2.0 adaptive playback and diagnostics: no fabricated adaptive sources.
        let adaptiveMaster = Stream(url: URL(string: "https://cdn.example/master.m3u8")!, quality: 0)
        precondition(PlaybackPlanner.adaptivePreferred(from: [source1080, adaptiveMaster])?.id == adaptiveMaster.id)
        precondition(PlaybackPlanner.adaptivePreferred(from: [source720])?.id == source720.id)
        precondition(PlaybackPlanner.explainFailure("HTTP 403").contains("provider denied"))
        precondition(PlaybackPlanner.explainFailure("timed out").contains("timed out"))
        precondition(PlaybackPlanner.explainFailure("not connected to internet").contains("offline"))
        // v2.0 local personalization, independent of UIKit/SwiftUI.
        let markers = ChapterMarkers(introEndsAt: 88, recapEndsAt: nil, creditsBeginAt: 950)
        precondition(markers.validFor(1100))
        precondition(!markers.validFor(800))
        precondition(ViewingPlanner.shouldOfferSkip(position: 20, end: markers.introEndsAt, duration: 1100))
        precondition(!ViewingPlanner.shouldOfferSkip(position: 90, end: markers.introEndsAt, duration: 1100))
        var extras = LocalViewingData()
        extras.watched[ep1.id] = Date()
        extras.collections = [WatchCollection(name: "Favorites to rewatch", videoIDs: [ep2.id])]
        extras.markers[movie.id] = markers
        let extrasBytes = try JSONEncoder().encode(extras)
        let restored = try JSONDecoder().decode(LocalViewingData.self, from: extrasBytes)
        precondition(restored.watched[ep1.id] != nil)
        precondition(restored.collections[0].videoIDs == [ep2.id])
        precondition(ViewingPlanner.nextUnwatched(episodes: [ep2, ep1], watched: Set(restored.watched.keys))?.id == ep2.id)
        precondition(ViewingPlanner.recommendations(candidates: [movie, ep1, ep2],
          favorites: [movie], recent: [], completed: []).allSatisfy { $0.id != movie.id })
        print("PASS: core models, serialization, filters, iOS stream formats, quality fallback, and series episode selection plus v1.5 next-episode, subtitle parser and download path checks")
    }
}
