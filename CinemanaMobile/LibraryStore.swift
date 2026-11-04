import SwiftUI

private struct PersonalExport: Codable {
    let library: LibrarySnapshot
    let personal: LocalViewingData
}

/// All personal library data lives on device. Existing 1.x settings remain decodable.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var extras = LocalViewingData()
    private let storageKey = "cinemana-ios-library-v1"
    private var saveTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) { snapshot = saved }
        if let data = UserDefaults.standard.data(forKey: LocalViewingData.key),
           let saved = try? JSONDecoder().decode(LocalViewingData.self, from: data) { extras = saved }
    }

    func isSaved(_ video: Video) -> Bool { snapshot.favorites.contains { $0.id == video.id } }
    func isWatched(_ id: String) -> Bool { extras.watched[id] != nil }
    func playback(for id: String) -> PlaybackRecord? { snapshot.recent.first { $0.id == id } }
    func markers(for id: String) -> ChapterMarkers { extras.markers[id] ?? ChapterMarkers() }
    func inCollection(_ videoID: String, collection: WatchCollection) -> Bool {
        extras.collections.first(where: { $0.id == collection.id })?.videoIDs.contains(videoID) == true
    }

    func toggle(_ video: Video) {
        var next = snapshot
        if let index = next.favorites.firstIndex(where: { $0.id == video.id }) {
            next.favorites.remove(at: index)
        } else {
            next.favorites.insert(video, at: 0)
            next.favorites = Array(next.favorites.prefix(300))
        }
        commit(next)
    }

    func markWatched(_ video: Video, watched: Bool) {
        var next = extras
        if watched { next.watched[video.id] = Date() } else { next.watched.removeValue(forKey: video.id) }
        commitExtras(next)
        if watched { removeRecent(video.id) }
    }

    func record(_ video: Video, position: Double, duration: Double) {
        guard extras.saveHistory, position.isFinite, duration.isFinite, position >= 10, duration > 20 else { return }
        if position / duration >= 0.95 {
            markWatched(video, watched: true)
            return
        }
        var next = snapshot
        next.recent.removeAll { $0.id == video.id }
        next.recent.insert(PlaybackRecord(video: video, seconds: position,
            duration: duration, updatedAt: Date()), at: 0)
        next.recent = Array(next.recent.prefix(150))
        commit(next)
    }

    func addCollection(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50,
              !extras.collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return }
        var next = extras
        next.collections.append(WatchCollection(name: name))
        commitExtras(next)
    }

    func deleteCollection(_ id: UUID) {
        var next = extras
        next.collections.removeAll { $0.id == id }
        commitExtras(next)
    }

    func toggle(_ video: Video, in collectionID: UUID) {
        var next = extras
        guard let index = next.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if let existing = next.collections[index].videoIDs.firstIndex(of: video.id) {
            next.collections[index].videoIDs.remove(at: existing)
        } else { next.collections[index].videoIDs.append(video.id) }
        // Keep a local title/poster record in Favorites for display when necessary.
        if next.collections[index].videoIDs.contains(video.id) && !isSaved(video) { toggle(video) }
        commitExtras(next)
    }

    func setMarkers(_ markers: ChapterMarkers, for videoID: String) {
        var next = extras
        next.markers[videoID] = markers
        commitExtras(next)
    }

    func recommendations(from candidates: [Video]) -> [Video] {
        ViewingPlanner.recommendations(candidates: candidates, favorites: snapshot.favorites,
             recent: snapshot.recent, completed: Set(extras.watched.keys))
    }

    func setSaveHistory(_ enabled: Bool) {
        var next = extras
        next.saveHistory = enabled
        commitExtras(next)
    }

    func clearHistory() {
        var next = snapshot; next.recent = []; commit(next)
        var additional = extras; additional.watched = [:]; commitExtras(additional)
    }
    func clearWatchlist() {
        var next = snapshot; next.favorites = []; commit(next)
        var additional = extras; additional.collections = []; commitExtras(additional)
    }
    func clearPersonalData() {
        snapshot = LibrarySnapshot()
        extras = LocalViewingData()
        persist()
    }
    func removeRecent(_ id: String) {
        var next = snapshot; next.recent.removeAll { $0.id == id }; commit(next)
    }
    func exportData() -> Data? {
        let bundle = PersonalExport(library: snapshot, personal: extras)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(bundle)
    }

    private func commit(_ next: LibrarySnapshot) { snapshot = next; persist() }
    private func commitExtras(_ next: LocalViewingData) { extras = next; persist() }

    private func persist() {
        // Capture both snapshots before beginning the detached disk write.
        let old = snapshot, fresh = extras, key = storageKey
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(old) { UserDefaults.standard.set(data, forKey: key) }
            if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: LocalViewingData.key) }
        }
    }
}
