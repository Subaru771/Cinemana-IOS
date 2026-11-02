import Foundation

struct OfflineEntry: Codable, Identifiable {
    enum Status: String, Codable {
        case queued, preparing, downloading, paused, ready, failed, cancelled
    }
    enum Format: String, Codable { case file, hls }

    let video: Video
    var status: Status
    var format: Format?
    var progress: Double
    /// Path relative to the app's home directory (older builds stored an absolute path).
    var localPath: String?
    var bytesReceived: Int64
    var bytesExpected: Int64
    var message: String?
    var updatedAt: Date
    var id: String { video.id }

    /// A transfer is actually running (or resolving its source) right now.
    var isBusy: Bool { status == .preparing || status == .downloading }
    /// The download is unfinished but still wanted by the user.
    var isActive: Bool { isBusy || status == .queued || status == .paused }
}

enum DownloadPolicy {
    static func format(for url: URL) -> OfflineEntry.Format? {
        switch url.pathExtension.lowercased() {
        case "m3u8": return .hls
        case "mp4", "m4v", "mov": return .file
        default: return nil
        }
    }
    static func supported(_ streams: [Stream]) -> [Stream] {
        streams.filter { $0.playableOnIOS && format(for: $0.url) != nil }
    }
}

/// App containers can move (updates, restores), so file locations are stored relative to home.
enum OfflinePath {
    private static func normalized(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    static func store(_ url: URL) -> String {
        let home = normalized(NSHomeDirectory())
        let path = normalized(url.path)
        if path.hasPrefix(home + "/") { return String(path.dropFirst(home.count + 1)) }
        return path
    }

    static func resolve(_ stored: String) -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if !stored.hasPrefix("/") { return home.appendingPathComponent(stored) }
        if FileManager.default.fileExists(atPath: stored) { return URL(fileURLWithPath: stored) }
        // Legacy absolute path from a previous container: re-root everything after "/Library/".
        if let range = stored.range(of: "/Library/") {
            return home.appendingPathComponent("Library")
                .appendingPathComponent(String(stored[range.upperBound...]))
        }
        return URL(fileURLWithPath: stored)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60) min" }
        return "\(total / 3600) h \((total % 3600) / 60) min"
    }
}
