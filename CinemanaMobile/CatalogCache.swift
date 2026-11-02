import Foundation

/// Persist only public catalog rows, not user account details or expiring stream URLs.
actor CatalogCache {
    static let shared = CatalogCache()
    private struct Snapshot: Codable {
        let savedAt: Date
        let rows: [CatalogRow]
    }

    private func url(for kind: Int?) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("catalog-ios-\(kind.map(String.init) ?? "all").json")
    }

    func read(kind: Int?) -> [CatalogRow]? {
        guard let file = url(for: kind), let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < 7 * 86_400 else { return nil }
        return snapshot.rows
    }

    func save(_ rows: [CatalogRow], kind: Int?) {
        guard !rows.isEmpty, let file = url(for: kind),
              let data = try? JSONEncoder().encode(Snapshot(savedAt: Date(), rows: rows)) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
