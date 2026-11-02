import SwiftUI

/// Keeps the personal library on the phone; no server-side account is required.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    private let storageKey = "cinemana-ios-library-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            snapshot = saved
        }
    }

    func isSaved(_ video: Video) -> Bool { snapshot.favorites.contains { $0.id == video.id } }

    func toggle(_ video: Video) {
        var next = snapshot
        if let index = next.favorites.firstIndex(where: { $0.id == video.id }) {
            next.favorites.remove(at: index)
        } else {
            next.favorites.insert(video, at: 0)
            next.favorites = Array(next.favorites.prefix(200))
        }
        commit(next)
    }

    func playback(for id: String) -> PlaybackRecord? {
        snapshot.recent.first(where: { $0.id == id })
    }

    func record(_ video: Video, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 10, duration > 20 else { return }
        var next = snapshot
        next.recent.removeAll { $0.id == video.id }
        // Completed titles no longer need a resume marker.
        if position / duration < 0.95 {
            next.recent.insert(PlaybackRecord(video: video, seconds: position,
                duration: duration, updatedAt: Date()), at: 0)
        }
        next.recent = Array(next.recent.prefix(100))
        commit(next)
    }

    func clearHistory() {
        var next = snapshot
        next.recent = []
        commit(next)
    }

    func clearWatchlist() {
        var next = snapshot
        next.favorites = []
        commit(next)
    }

    func removeRecent(_ id: String) {
        var next = snapshot
        next.recent.removeAll { $0.id == id }
        commit(next)
    }

    private func commit(_ next: LibrarySnapshot) {
        snapshot = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
