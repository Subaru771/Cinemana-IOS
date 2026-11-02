import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import UIKit

// MARK: - External subtitles

/// Loads provider subtitle files and exposes the cue for the current playback time.
@MainActor
final class SubtitleController: ObservableObject {
    static let preferenceKey = "cinemana-sub-pref"

    @Published private(set) var available: [Subtitle] = []
    @Published private(set) var selected: Subtitle?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    /// Seconds. Positive values make subtitles appear later.
    @Published var offset: Double = 0

    private var cues: [SubtitleCue] = []
    private var videoID: String?

    func load(for id: String) async {
        videoID = id
        available = []
        selected = nil
        failure = nil
        cues = []
        offset = 0
        let found = await CinemanaAPI.shared.subtitles(id)
        guard videoID == id else { return }
        available = found
        let preferred = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
        if !preferred.isEmpty, let match = found.first(where: { $0.name == preferred }) {
            await select(match, remember: false)
        }
    }

    func select(_ subtitle: Subtitle?, remember: Bool = true) async {
        if remember { UserDefaults.standard.set(subtitle?.name ?? "", forKey: Self.preferenceKey) }
        failure = nil
        guard let subtitle else {
            selected = nil
            cues = []
            return
        }
        let id = videoID
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: subtitle.url)
            guard videoID == id else { return }
            let parsed = SubtitleParser.parse(SubtitleParser.decodeText(data))
            if parsed.isEmpty {
                selected = nil
                cues = []
                failure = "This subtitle file could not be read."
            } else {
                cues = parsed
                selected = subtitle
            }
        } catch {
            guard videoID == id else { return }
            selected = nil
            cues = []
            failure = "Could not download this subtitle."
        }
    }

    func adjustOffset(by delta: Double) {
        offset = max(-30, min(30, ((offset + delta) * 10).rounded() / 10))
    }

    func cue(at time: Double) -> SubtitleCue? {
        SubtitleParser.cue(at: time, in: cues)
    }

    func reset() {
        videoID = nil
        available = []
        selected = nil
        cues = []
        offset = 0
    }
}

// MARK: - Picture in Picture

final class PictureInPictureController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var possible = false
    @Published private(set) var active = false
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?

    func attach(_ layer: AVPlayerLayer) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported(),
              let created = AVPictureInPictureController(playerLayer: layer) else { return }
        created.delegate = self
        created.canStartPictureInPictureAutomaticallyFromInline = true
        controller = created
        observation = created.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] item, _ in
            let value = item.isPictureInPicturePossible
            DispatchQueue.main.async { self?.possible = value }
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        else { controller.startPictureInPicture() }
    }

    func stop() {
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = false }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - Lock screen / headphone controls

final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    private var registrations: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: URL?

    /// `player` is a provider because quality changes replace the underlying AVPlayer.
    func activate(player: @escaping () -> AVPlayer?, next: @escaping () -> Bool) {
        deactivateCommands()
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.playCommand) { _ in player()?.play(); return .success }
        add(center.pauseCommand) { _ in player()?.pause(); return .success }
        add(center.togglePlayPauseCommand) { _ in
            guard let item = player() else { return .noActionableNowPlayingItem }
            if item.rate > 0 { item.pause() } else { item.play() }
            return .success
        }
        add(center.skipForwardCommand) { _ in Self.jump(player(), by: 30); return .success }
        add(center.skipBackwardCommand) { _ in Self.jump(player(), by: -10); return .success }
        add(center.changePlaybackPositionCommand) { event in
            guard let item = player(),
                  let change = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            item.seek(to: CMTime(seconds: change.positionTime, preferredTimescale: 600))
            return .success
        }
        add(center.nextTrackCommand) { _ in next() ? .success : .noSuchContent }
    }

    func update(video: Video, position: Double, duration: Double, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, position.isFinite ? position : 0),
            MPNowPlayingInfoPropertyPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(video.poster ?? video.backdrop)
    }

    func deactivate() {
        deactivateCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        artworkURL = nil
    }

    private func add(_ command: MPRemoteCommand,
                     _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        command.isEnabled = true
        // Handlers touch main-actor state (the player), so always run them on the main thread.
        let token = command.addTarget { event in
            if Thread.isMainThread { return handler(event) }
            return DispatchQueue.main.sync { handler(event) }
        }
        registrations.append((command, token))
    }

    private func deactivateCommands() {
        for (command, token) in registrations { command.removeTarget(token) }
        registrations = []
    }

    private static func jump(_ player: AVPlayer?, by seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let made = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard let self, self.artworkURL == url else { return }
                self.artwork = made
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = made
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}

// MARK: - Orientation, volume

enum PlayerOrientation {
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)) { _ in }
    }
}

/// Hidden MPVolumeView so a swipe gesture can change the system volume without the system HUD.
struct VolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        SystemVolume.host = view
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

enum SystemVolume {
    static weak var host: MPVolumeView?

    static var current: Float { AVAudioSession.sharedInstance().outputVolume }

    static func set(_ level: Float) {
        let value = min(1, max(0, level))
        let slider = host?.subviews.compactMap { $0 as? UISlider }.first
        DispatchQueue.main.async { slider?.value = value }
    }
}
