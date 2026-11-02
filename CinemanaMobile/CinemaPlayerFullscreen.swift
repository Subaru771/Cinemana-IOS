import SwiftUI
import AVFoundation
import AVKit
import UIKit
import Combine

private let cinemaAccent = Color(red: 0.55, green: 0.96, blue: 0.69)

/// Brand mark drawn in SwiftUI so it remains sharp on every screen size.
struct CinemanaLogo: View {
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 11)
                    .fill(cinemaAccent)
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 13 : 20, weight: .heavy))
                    .foregroundStyle(.black)
                    .offset(x: 1)
            }
            .frame(width: compact ? 27 : 39, height: compact ? 27 : 39)
            Text("CINEMANA")
                .font(.system(size: compact ? 14 : 23, weight: .black, design: .rounded))
                .tracking(compact ? 1.4 : 2.0)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cinemana")
    }
}

/// Only AVPlayerLayer renders pixels. No Apple video-player interface is presented.
final class CinemanaRenderView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var renderLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct CinemanaVideoCanvas: UIViewRepresentable {
    let player: AVPlayer?
    var fillScreen: Bool

    func makeUIView(context: Context) -> CinemanaRenderView {
        let view = CinemanaRenderView()
        view.backgroundColor = .black
        view.renderLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: CinemanaRenderView, context: Context) {
        if uiView.renderLayer.player !== player {
            uiView.renderLayer.player = player
        }
        uiView.renderLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
    }
}

struct CinemanaAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.55, green: 0.96, blue: 0.69, alpha: 1)
        picker.prioritizesVideoDevices = true
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// The full-screen cover presents this view immediately, even while the stream URL is loading.
struct CinemaPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var downloads = DownloadCenter.shared
    @StateObject private var session = PlaybackSession()
    @State private var showsControls = true
    @State private var isScrubbing = false
    @State private var seekPreview = 0.0
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var playing = false
    @State private var waiting = false
    @State private var speed: Float = 1
    @State private var cropVideo = false
    @State private var locked = false
    @State private var hideTask: Task<Void, Never>?
    @State private var captions: [AVMediaSelectionOption] = []
    @State private var audioTracks: [AVMediaSelectionOption] = []
    @State private var captionGroup: AVMediaSelectionGroup?
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var selectedCaption: AVMediaSelectionOption?
    @State private var selectedAudio: AVMediaSelectionOption?

    let video: Video

    private var timeLimit: Double { max(1, duration) }
    private var isDownloaded: Bool { downloads.localURL(for: video.id) != nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                CinemanaVideoCanvas(player: session.player, fillScreen: cropVideo)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }

                if session.loading && session.player == nil {
                    loadingState
                } else if let problem = session.error, session.player == nil {
                    errorState(problem)
                }

                if waiting && session.player != nil && !session.loading {
                    ProgressView().tint(cinemaAccent).scaleEffect(1.4)
                        .allowsHitTesting(false)
                }

                if showsControls {
                    if locked {
                        VStack {
                            HStack {
                                Button {
                                    locked = false
                                    showControls()
                                } label: {
                                    Label("Unlock", systemImage: "lock.open.fill")
                                        .font(.subheadline.weight(.bold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(cinemaAccent)
                                Spacer()
                            }.padding(24)
                            Spacer()
                        }
                    } else {
                        controlOverlay
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .preferredColorScheme(.dark)
        .task(id: video.id) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { /* Playback may still work with the previous audio session. */ }
            await session.load(video: video, library: library)
            if session.player != nil { showControls() }
        }
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
            updateProgress()
        }
        .onChange(of: session.selected?.id) { _ in
            Task { await loadTracks() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { session.save(library: library) }
        }
        .onDisappear {
            hideTask?.cancel()
            session.close(library: library)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem {
                session.failed(item: item, library: library,
                    reason: (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, session.player?.currentItem === item {
                playing = false
                showControls()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 19) {
            CinemanaLogo()
            ProgressView().tint(cinemaAccent).scaleEffect(1.4)
            Text("Preparing playback…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button("Close") { closePlayer() }.tint(cinemaAccent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "play.slash.fill").font(.system(size: 42))
                .foregroundStyle(cinemaAccent)
            Text("Couldn't play this video").font(.title3.weight(.bold))
            Text(message).font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button("Try again") { Task { await session.load(video: video, library: library) } }
                .buttonStyle(.borderedProminent).tint(cinemaAccent)
            Button("Close player") { closePlayer() }.tint(.white)
        }
        .padding(26)
        .frame(maxWidth: 450)
    }

    private var controlOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                overlayButton("chevron.down", label: "Close") { closePlayer() }
                CinemanaLogo(compact: true)
                Spacer(minLength: 6)
                if session.player != nil {
                    Text(isDownloaded ? "OFFLINE" : (session.selected?.label ?? "AUTO"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(cinemaAccent)
                        .lineLimit(1)
                }
                CinemanaAirPlayButton().frame(width: 36, height: 36)
                optionsMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)

            Spacer(minLength: 10)

            if session.player != nil {
                HStack(spacing: 36) {
                    overlayButton("gobackward.10", label: "Back 10 seconds", size: 29) {
                        seek(to: currentTime - 10)
                    }
                    Button {
                        if playing { session.player?.pause() }
                        else {
                            session.player?.play()
                            session.player?.rate = speed
                        }
                        playing.toggle()
                        showControls()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 76, height: 76)
                            .background(cinemaAccent, in: Circle())
                    }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    overlayButton("goforward.30", label: "Forward 30 seconds", size: 29) {
                        seek(to: currentTime + 30)
                    }
                }
                .tint(.white)
            }

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 12) {
                if let notice = session.notice {
                    Label(notice, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.yellow)
                        .lineLimit(2)
                }
                Text(video.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                if session.player != nil {
                    Slider(value: $seekPreview, in: 0...timeLimit,
                           onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing { hideTask?.cancel() }
                        else { seek(to: seekPreview) }
                    })
                    .tint(cinemaAccent)
                    .accessibilityLabel("Video timeline")
                    HStack {
                        Text(formatTime(isScrubbing ? seekPreview : currentTime))
                        Spacer()
                        Text(duration > 0 ? "-\(formatTime(max(0, duration - (isScrubbing ? seekPreview : currentTime))))" : "LIVE")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.82))
                }
                HStack(spacing: 16) {
                    Button { locked = true; showControls() } label: {
                        Label("Lock", systemImage: "lock")
                    }
                    Button {
                        cropVideo.toggle()
                        showControls()
                    } label: {
                        Label(cropVideo ? "Fit" : "Fill", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Spacer()
                    if let entry = downloads.entry(for: video.id), entry.isActive {
                        ProgressView(value: entry.progress).frame(width: 42)
                    } else if !isDownloaded {
                        Button {
                            Task { await downloads.begin(video) }
                            showControls()
                        } label: {
                            Label("Download", systemImage: "arrow.down.to.line")
                        }
                    } else {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .tint(.white)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [.black.opacity(0.72), .clear, .black.opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var optionsMenu: some View {
        Menu {
            Menu("Playback speed") {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button("\(value.formatted())×") {
                        speed = Float(value)
                        if playing { session.player?.rate = speed }
                        showControls()
                    }
                }
            }
            if !isDownloaded && !session.streams.isEmpty {
                Menu("Video quality") {
                    ForEach(session.streams) { stream in
                        Button {
                            let position = currentTime
                            session.select(stream, video: video, library: library)
                            // Session retains the last playing position during the switch.
                            currentTime = position
                            showControls()
                        } label: {
                            if stream.id == session.selected?.id {
                                Label(stream.label, systemImage: "checkmark")
                            } else {
                                Text(stream.label)
                            }
                        }
                    }
                }
            }
            Menu("Subtitles") {
                Button("Off") { chooseCaption(nil) }
                if captions.isEmpty { Text("No embedded subtitles") }
                ForEach(Array(captions.enumerated()), id: \.offset) { _, option in
                    Button(option.displayName) { chooseCaption(option) }
                }
            }
            Menu("Audio track") {
                if audioTracks.isEmpty { Text("Default audio") }
                ForEach(Array(audioTracks.enumerated()), id: \.offset) { _, option in
                    Button(option.displayName) { chooseAudio(option) }
                }
            }
            Button(cropVideo ? "Fit original aspect ratio" : "Fill screen (crop edges)") {
                cropVideo.toggle()
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
        }
        .accessibilityLabel("Player settings")
    }

    private func overlayButton(_ symbol: String, label: String, size: CGFloat = 21,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func updateProgress() {
        guard let player = session.player else { return }
        let time = player.currentTime().seconds
        if time.isFinite && time >= 0 {
            currentTime = time
            if !isScrubbing { seekPreview = time }
        }
        let length = player.currentItem?.duration.seconds ?? 0
        duration = length.isFinite && length > 0 ? length : 0
        let nowPlaying = player.rate > 0
        if nowPlaying != playing {
            playing = nowPlaying
            if nowPlaying { scheduleAutoHide() }
            else { hideTask?.cancel(); showsControls = true }
        }
        waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    private func seek(to value: Double) {
        guard value.isFinite else { return }
        let bounded = max(0, duration > 0 ? min(value, duration) : value)
        session.player?.seek(to: CMTime(seconds: bounded, preferredTimescale: 600),
                             toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                             toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
        currentTime = bounded
        seekPreview = bounded
        showControls()
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.16)) { showsControls.toggle() }
        if showsControls { scheduleAutoHide() }
        else { hideTask?.cancel() }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.16)) { showsControls = true }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard playing && !isScrubbing else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { showsControls = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let x = Int(seconds)
        if x >= 3600 { return String(format: "%d:%02d:%02d", x/3600, (x%3600)/60, x%60) }
        return String(format: "%d:%02d", x/60, x%60)
    }

    private func closePlayer() {
        hideTask?.cancel()
        session.close(library: library)
        dismiss()
    }

    private func loadTracks() async {
        captions = []
        audioTracks = []
        guard let item = session.player?.currentItem else { return }
        // The AVAsset async APIs avoid blocking the rendering/UI thread.
        let asset = item.asset
        let caption = try? await asset.loadMediaSelectionGroup(for: .legible)
        let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
        guard session.player?.currentItem === item else { return }
        captionGroup = caption
        audioGroup = audible
        captions = caption?.options ?? []
        audioTracks = audible?.options ?? []
    }

    private func chooseCaption(_ option: AVMediaSelectionOption?) {
        if let group = captionGroup {
            session.player?.currentItem?.select(option, in: group)
        }
        selectedCaption = option
        showControls()
    }

    private func chooseAudio(_ option: AVMediaSelectionOption) {
        if let group = audioGroup {
            session.player?.currentItem?.select(option, in: group)
        }
        selectedAudio = option
        showControls()
    }
}
