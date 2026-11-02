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
        print("PASS: iOS core models, search/filter, stream format checks, catalog and library persistence (22 checks)")
    }
}
