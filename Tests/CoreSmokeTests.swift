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
        print("PASS: core models, serialization, filters, iOS stream formats, quality fallback, and series episode selection plus v1.5 next-episode, subtitle parser and download path checks")
    }
}
