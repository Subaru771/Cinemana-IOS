import Foundation
import AVFoundation
import Combine
import UIKit
import Network

/// Local, sandboxed download manager. Only provider-supplied, directly downloadable streams
/// are accepted. The manager never bypasses DRM or a provider's network authorization.
///
/// v1.5: queue (2 at a time), pause/resume, automatic retry with resume data, Wi-Fi only,
/// live speed/ETA, free-space checks, relative file paths and exclusion from iCloud backup.
final class DownloadCenter: NSObject, ObservableObject, URLSessionDownloadDelegate, AVAssetDownloadDelegate {
    static let shared = DownloadCenter()
    static let maxConcurrent = 2
    static let wifiOnlyKey = "cinemana-wifi-only"

    private static let fileID = "app.cinemana.mobile.ios.background-media-v1"
    private static let hlsID = "app.cinemana.mobile.ios.background-hls-v1"

    @Published private(set) var items: [OfflineEntry] = []
    /// Smoothed transfer speed in bytes per second, for files that are downloading right now.
    @Published private(set) var rates: [String: Double] = [:]

    private let fm = FileManager.default
    private let root: URL
    private var fileSession: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!
    private var completionHandlers: [String: () -> Void] = [:]
    private var hlsDestinations: [String: URL] = [:]
    private var attempts: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]
    private var samples: [String: (time: Double, bytes: Int64, rate: Double)] = [:]
    private var persistWork: DispatchWorkItem?
    private let networkMonitor = NWPathMonitor()
    private var wifiAvailable = false
    /// Downloads suspended by the Wi-Fi-only policy (distinct from user-paused downloads).
    private var policyPaused = Set<String>()

    private override init() {
        var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaOffline", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Downloaded videos are re-downloadable, so keep them out of iCloud/iTunes backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        root = folder
        super.init()
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([OfflineEntry].self, from: data) {
            items = saved
        }
        let files = URLSessionConfiguration.background(withIdentifier: Self.fileID)
        files.sessionSendsLaunchEvents = true
        files.isDiscretionary = false
        fileSession = URLSession(configuration: files, delegate: self, delegateQueue: .main)
        let hls = URLSessionConfiguration.background(withIdentifier: Self.hlsID)
        hls.sessionSendsLaunchEvents = true
        hls.isDiscretionary = false
        hlsSession = AVAssetDownloadURLSession(configuration: hls, assetDownloadDelegate: self, delegateQueue: .main)
        // Evaluate the current interface and monitor Wi-Fi transitions. The first path
        // update is asynchronous; Wi-Fi-only queues remain safely held until then.
        policyPaused = Set(items.filter {
            $0.status == .paused && $0.message == "Waiting for Wi-Fi"
        }.map(\.id))
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.wifiAvailable = path.status == .satisfied && path.usesInterfaceType(.wifi)
                self.updateNetworkPolicy()
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "app.cinemana.download-network"))
        restoreTasks()
    }

    // MARK: - Persistence

    private var indexURL: URL { root.appendingPathComponent("downloads.json") }

    private func resumeURL(_ id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safe).resume")
    }

    private func persist() {
        persistWork?.cancel()
        persistWork = nil
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// Progress callbacks arrive many times a second; write them to disk at most every 2 seconds.
    private func persistSoon() {
        guard persistWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.persistWork = nil
            self?.persist()
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func change(_ id: String, save: Bool = true, _ mutation: (inout OfflineEntry) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
        items[index].updatedAt = Date()
        if save { persist() } else { persistSoon() }
    }

    // MARK: - Queries

    func entry(for id: String) -> OfflineEntry? { items.first { $0.id == id } }

    func localURL(for id: String) -> URL? {
        guard let item = entry(for: id), item.status == .ready, let path = item.localPath else { return nil }
        let url = OfflinePath.resolve(path)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// Bytes used by finished downloads.
    var usedBytes: Int64 {
        items.filter { $0.status == .ready }
            .reduce(Int64(0)) { $0 + max($1.bytesExpected, $1.bytesReceived) }
    }

    var freeBytes: Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Public actions

    /// Adds a video to the download queue. Safe to call repeatedly.
    func enqueue(_ video: Video, preferredQuality: Int? = nil) {
        if localURL(for: video.id) != nil { return }
        if let existing = entry(for: video.id), existing.isActive { return }
        items.removeAll { $0.id == video.id }
        items.insert(OfflineEntry(video: video, status: .queued, format: nil, progress: 0,
                                  localPath: nil, bytesReceived: 0, bytesExpected: 0,
                                  message: nil, updatedAt: Date(),
                                  requestedQuality: preferredQuality), at: 0)
        attempts[video.id] = 0
        retryAfter[video.id] = nil
        persist()
        pump()
    }

    func enqueue(_ videos: [Video], preferredQuality: Int? = nil) {
        // Insert in reverse so the first episode ends up first in the queue.
        for video in videos.reversed() { enqueue(video, preferredQuality: preferredQuality) }
    }

    func pause(_ id: String) {
        guard let status = entry(for: id)?.status,
              status == .downloading || status == .preparing || status == .queued else { return }
        policyPaused.remove(id)
        change(id) { $0.status = .paused; $0.message = nil }
        rates[id] = nil
        samples[id] = nil
        // Do not fill the newly vacant slot until all previous tasks are suspended.
        withTasks(id) { [weak self] tasks in
            tasks.forEach { $0.suspend() }
            self?.pump()
        }
    }

    func resume(_ id: String) {
        guard entry(for: id)?.status == .paused else { return }
        policyPaused.remove(id)
        // Never resume tasks directly: they must reacquire a queue slot.
        change(id) { $0.status = .queued; $0.message = nil }
        pump()
    }

    func pauseAll() {
        // Pause queued entries as well, otherwise pausing active tasks immediately
        // launches replacements and the "Pause all" button fails its promise.
        for id in items.filter({ $0.isActive && $0.status != .paused }).map(\.id) {
            pause(id)
        }
    }

    func resumeAll() {
        let ids = items.filter { $0.status == .paused }.map(\.id)
        for id in ids {
            policyPaused.remove(id)
            change(id) { $0.status = .queued; $0.message = nil }
        }
        pump()
    }

    /// Apply the latest Settings/Downloads toggle immediately to running transfers.
    /// Existing downloads are suspended off Wi-Fi, not allowed to continue on cellular.
    func updateNetworkPolicy() {
        let restricted = UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) && !wifiAvailable
        if restricted {
            for item in items where item.isBusy {
                let id = item.id
                policyPaused.insert(id)
                change(id) { $0.status = .paused; $0.message = "Waiting for Wi-Fi" }
                rates[id] = nil
                samples[id] = nil
                withTasks(id) { tasks in tasks.forEach { $0.suspend() } }
            }
        } else {
            let restarting = policyPaused
            policyPaused.removeAll()
            for id in restarting where entry(for: id)?.status == .paused {
                change(id) { $0.status = .queued; $0.message = nil }
            }
            pump()
        }
    }

    func cancel(_ id: String) {
        guard let item = entry(for: id) else { return }
        change(id) { $0.status = .cancelled; $0.message = "Cancelled" }
        withTasks(id) { $0.forEach { $0.cancel() } }
        try? fm.removeItem(at: resumeURL(id))
        if item.format == .hls, let path = item.localPath { try? fm.removeItem(at: OfflinePath.resolve(path)) }
        attempts[id] = nil
        retryAfter[id] = nil
        policyPaused.remove(id)
        rates[id] = nil
        samples[id] = nil
        pump()
    }

    func remove(_ id: String) {
        if entry(for: id)?.isActive == true { cancel(id) }
        if let item = entry(for: id), let path = item.localPath {
            let url = OfflinePath.resolve(path)
            if item.format == .hls || url.path.hasPrefix(root.path) { try? fm.removeItem(at: url) }
        }
        try? fm.removeItem(at: resumeURL(id))
        items.removeAll { $0.id == id }
        persist()
    }

    /// Delete only completed offline files, leaving active/queued downloads intact.
    func removeCompleted() {
        let completedIDs = items.filter { $0.status == .ready }.map(\.id)
        for id in completedIDs { remove(id) }
    }

    func removeAll() {
        for item in items { remove(item.id) }
    }

    // MARK: - Queue

    private func pump() {
        if UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) && !wifiAvailable { return }
        let free = Self.maxConcurrent - items.filter(\.isBusy).count
        guard free > 0 else { return }
        let now = Date()
        let next = items.reversed()
            .filter { $0.status == .queued && (retryAfter[$0.id] ?? .distantPast) <= now }
            .prefix(free)
            .map(\.video)
        for video in next {
            change(video.id) { $0.status = .preparing; $0.message = nil }
            // A previously suspended URLSessionTask must be resumed IN its newly
            // acquired slot rather than creating a second task for the same title.
            withTasks(video.id) { [weak self] tasks in
                guard let self, self.entry(for: video.id)?.status == .preparing else { return }
                if !tasks.isEmpty {
                    self.change(video.id) { $0.status = .downloading }
                    tasks.forEach { $0.resume() }
                } else {
                    Task { @MainActor [weak self] in await self?.start(video) }
                }
            }
        }
    }

    @MainActor
    private func start(_ video: Video) async {
        let id = video.id
        if let free = freeBytes, free < 600_000_000 {
            fail(id, "Not enough free storage. Free up some space and retry.")
            return
        }
        do {
            let available = DownloadPolicy.supported(try await CinemanaAPI.shared.streams(id, preferComplete: true))
            // The user may have cancelled or paused while the source was being resolved.
            guard entry(for: id)?.status == .preparing else { return }
            if UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) && !wifiAvailable {
                policyPaused.insert(id)
                change(id) { $0.status = .paused; $0.message = "Waiting for Wi-Fi" }
                return
            }
            let configured = UserDefaults.standard.integer(forKey: "cinemana-max-download-quality")
            let ceiling = entry(for: id)?.requestedQuality ?? (configured > 0 ? configured : 1080)
            guard let stream = PlaybackPlanner.downloadStream(from: available, maximumQuality: ceiling),
                  let format = DownloadPolicy.format(for: stream.url) else {
                fail(id, ceiling == Int.max
                    ? "No downloadable MP4 or HLS source is available."
                    : "No downloadable resolution at or below \(ceiling)p is available. Choose a higher quality or Best available.")
                return
            }
            let allowsCellular = !UserDefaults.standard.bool(forKey: Self.wifiOnlyKey)
            change(id) { $0.status = .downloading; $0.format = format }
            switch format {
            case .file:
                let task: URLSessionDownloadTask
                if let data = try? Data(contentsOf: resumeURL(id)), !data.isEmpty {
                    task = fileSession.downloadTask(withResumeData: data)
                } else {
                    var request = URLRequest(url: stream.url)
                    request.allowsCellularAccess = allowsCellular
                    task = fileSession.downloadTask(with: request)
                }
                task.taskDescription = id
                task.resume()
            case .hls:
                if let partial = entry(for: id)?.localPath {
                    try? fm.removeItem(at: OfflinePath.resolve(partial))
                    change(id) { $0.localPath = nil }
                }
                // A master playlist may contain resolutions higher than its label.
                let resolved = try await HLSQuality.resolve(stream, maximumQuality: ceiling,
                                                            allowsCellular: allowsCellular)
                guard entry(for: id)?.status == .downloading else { return }
                let asset = AVURLAsset(url: resolved,
                                       options: [AVURLAssetAllowsCellularAccessKey: allowsCellular])
                guard let task = hlsSession.makeAssetDownloadTask(
                    asset: asset, assetTitle: video.title, assetArtworkData: nil, options: nil
                ) else {
                    fail(id, "This HLS stream cannot be downloaded.")
                    return
                }
                task.taskDescription = id
                task.resume()
            }
        } catch {
            if entry(for: id)?.status == .preparing { fail(id, error.localizedDescription) }
        }
    }

    private func fail(_ id: String, _ message: String) {
        change(id) { $0.status = .failed; $0.message = message }
        rates[id] = nil
        samples[id] = nil
        pump()
    }

    private func finish(_ id: String, path: URL, format: OfflineEntry.Format) {
        change(id) {
            $0.status = .ready
            $0.format = format
            $0.localPath = OfflinePath.store(path)
            $0.progress = 1
            $0.message = nil
        }
        try? fm.removeItem(at: resumeURL(id))
        attempts[id] = nil
        rates[id] = nil
        samples[id] = nil
        // Measuring a large HLS package can take a moment, so keep it off the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let size = Self.diskSize(path)
            DispatchQueue.main.async {
                self?.change(id) { $0.bytesReceived = size; $0.bytesExpected = size }
            }
        }
        pump()
    }

    private static func diskSize(_ url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    // MARK: - Launch recovery

    private func withTasks(_ id: String, _ body: @escaping ([URLSessionTask]) -> Void) {
        withAllTasks { tasks in body(tasks.filter { $0.taskDescription == id }) }
    }

    private func withAllTasks(_ body: @escaping ([URLSessionTask]) -> Void) {
        fileSession.getAllTasks { [weak self] fileTasks in
            guard let self else { return }
            self.hlsSession.getAllTasks { hlsTasks in
                DispatchQueue.main.async { body(fileTasks + hlsTasks) }
            }
        }
    }

    private func restoreTasks() {
        // A title that was still resolving its source when the app quit has no task yet.
        for item in items where item.status == .preparing { change(item.id) { $0.status = .queued } }
        updateNetworkPolicy()
        // Give the system a moment to deliver finished-in-background events before judging tasks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.reconcile() }
        pump()
    }

    private func reconcile() {
        withAllTasks { [weak self] tasks in
            guard let self else { return }
            let alive = Set(tasks.compactMap(\.taskDescription))
            for item in self.items where item.status == .downloading && !alive.contains(item.id) {
                self.change(item.id) { $0.status = .queued; $0.message = "Resuming…" }
            }
            self.pump()
        }
    }

    // MARK: - Progress sampling

    private func sample(_ id: String, bytes: Int64) {
        let now = Date().timeIntervalSinceReferenceDate
        guard let last = samples[id] else {
            samples[id] = (now, bytes, 0)
            return
        }
        let elapsed = now - last.time
        guard elapsed >= 1 else { return }
        let instant = Double(bytes - last.bytes) / elapsed
        let smooth = last.rate == 0 ? instant : last.rate * 0.7 + instant * 0.3
        samples[id] = (now, bytes, smooth)
        rates[id] = max(0, smooth)
    }

    // MARK: - File downloads

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        if totalBytesExpectedToWrite > 0, let free = freeBytes,
           totalBytesExpectedToWrite - totalBytesWritten > free - 200_000_000 {
            fail(id, "Not enough free storage to finish this download.")
            downloadTask.cancel()
            return
        }
        sample(id, bytes: totalBytesWritten)
        change(id, save: false) {
            $0.bytesReceived = totalBytesWritten
            $0.bytesExpected = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 {
                $0.progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription,
              let status = entry(for: id)?.status, status == .downloading || status == .paused else { return }
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode,
           !(200...299).contains(code) {
            fail(id, "Download rejected: HTTP \(code)")
            return
        }
        if let mime = downloadTask.response?.mimeType?.lowercased(),
           mime.contains("html") || mime.contains("json") || mime.contains("text/plain") {
            fail(id, "Server returned a document, not a video.")
            return
        }
        let ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? ""
        let destination = root.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "mp4" : ext)
        do {
            try fm.moveItem(at: location, to: destination)
            finish(id, path: destination, format: .file)
        } catch { fail(id, error.localizedDescription) }
    }

    // MARK: - HLS downloads

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        hlsDestinations[id] = location
        change(id) { $0.localPath = OfflinePath.store(location) }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite && expected > 0 else { return }
        let loaded = totalTimeRangesLoaded.reduce(0) { $0 + max(0, $1.timeRangeValue.duration.seconds) }
        change(id, save: false) { $0.progress = min(0.99, max(0, loaded / expected)) }
    }

    // MARK: - Completion and retry

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let current = entry(for: id) else { return }
        // Cancelled, paused-then-removed, already finished: nothing left to do.
        guard current.isBusy || current.status == .paused else { return }
        if let error {
            // Paused/suspended downloads should not silently restart after a
            // cancellation or a background callback while Wi-Fi is restricted.
            if current.status == .paused { return }
            handleFailure(id, error: error as NSError)
            return
        }
        if current.format == .hls {
            if let path = current.localPath.map({ OfflinePath.resolve($0) }) ?? hlsDestinations[id],
               fm.fileExists(atPath: path.path) {
                hlsDestinations[id] = nil
                finish(id, path: path, format: .hls)
            } else { fail(id, "HLS package was not saved.") }
        } else {
            fail(id, "Download finished without a playable file.")
        }
    }

    private func handleFailure(_ id: String, error: NSError) {
        if let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: resumeURL(id), options: .atomic)
        } else {
            // Stale resume data would only make the next attempt fail again.
            try? fm.removeItem(at: resumeURL(id))
        }
        let transient: Set<Int> = [
            NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff
        ]
        let tries = attempts[id, default: 0]
        if error.domain == NSURLErrorDomain, transient.contains(error.code), tries < 4 {
            attempts[id] = tries + 1
            let delay = Double(4 << tries)  // 4, 8, 16, 32 seconds
            retryAfter[id] = Date().addingTimeInterval(delay)
            change(id) { $0.status = .queued; $0.message = "Connection problem. Retrying (\(tries + 1)/4)…" }
            rates[id] = nil
            samples[id] = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) { [weak self] in self?.pump() }
            pump()
        } else {
            fail(id, error.localizedDescription)
        }
    }

    // MARK: - Background session plumbing

    func registerCompletion(_ identifier: String, handler: @escaping () -> Void) {
        completionHandlers[identifier] = handler
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        let handler = completionHandlers.removeValue(forKey: identifier)
        handler?()
    }
}
