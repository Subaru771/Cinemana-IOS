import SwiftUI

/// Offline library: storage summary, live queue with pause/resume, and finished downloads.
struct DownloadsView: View {
    @ObservedObject private var center = DownloadCenter.shared
    @AppStorage("cinemana-wifi-only") private var wifiOnly = false
    @State private var watch: Video?
    @State private var confirmDeleteAll = false

    private var queue: [OfflineEntry] { center.items.filter { $0.status != .ready } }
    private var finished: [OfflineEntry] { center.items.filter { $0.status == .ready } }

    var body: some View {
        NavigationStack {
            Group {
                if center.items.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Downloads")
            .onChange(of: wifiOnly) { _ in center.updateNetworkPolicy() }
            .background(Color.black)
            .toolbar { toolbarMenu }
            .fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0) }
            .confirmationDialog("Delete every download?", isPresented: $confirmDeleteAll) {
                Button("Delete all downloads", role: .destructive) { center.removeAll() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 54))
                .foregroundStyle(.mint)
            Text("Your downloads").font(.title2.bold())
            Text("Choose Download from a movie or episode. Supported videos will appear here for offline playback.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Availability depends on the video provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section { storageSummary }
            if !queue.isEmpty {
                Section("In progress") {
                    ForEach(queue) { entry in
                        row(entry)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { center.remove(entry.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            if !finished.isEmpty {
                Section("Ready to watch") {
                    ForEach(finished) { entry in
                        row(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { play(entry) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { center.remove(entry.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(ByteFormat.string(center.usedBytes)) used", systemImage: "internaldrive")
                Spacer()
                if let free = center.freeBytes {
                    Text("\(ByteFormat.string(free)) free").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            if wifiOnly {
                Label("Wi-Fi only", systemImage: "wifi")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { center.pauseAll() } label: { Label("Pause all", systemImage: "pause.fill") }
                Button { center.resumeAll() } label: { Label("Resume all", systemImage: "play.fill") }
                Toggle(isOn: $wifiOnly) { Label("Wi-Fi only", systemImage: "wifi") }
                Divider()
                Button(role: .destructive) { confirmDeleteAll = true } label: {
                    Label("Delete all", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(center.items.isEmpty)
        }
    }

    private func play(_ entry: OfflineEntry) {
        if center.localURL(for: entry.id) != nil { watch = entry.video }
    }

    private func row(_ entry: OfflineEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AsyncImage(url: entry.video.poster) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 60, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if entry.status == .ready && center.localURL(for: entry.id) != nil {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if entry.video.episode > 0 {
                    Text("Season \(entry.video.season) · Episode \(entry.video.episode)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(statusDescription(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.status == .downloading || entry.status == .paused {
                    ProgressView(value: entry.progress).tint(entry.status == .paused ? Color.gray : Color.mint)
                }
                if let message = entry.message, entry.status == .failed {
                    Text(message).font(.caption2).foregroundStyle(.orange).lineLimit(3)
                }
                actions(entry)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actions(_ entry: OfflineEntry) -> some View {
        HStack(spacing: 16) {
            switch entry.status {
            case .downloading:
                Button { center.pause(entry.id) } label: { Label("Pause", systemImage: "pause.fill") }
                Button("Cancel") { center.cancel(entry.id) }
            case .paused:
                Button { center.resume(entry.id) } label: { Label("Resume", systemImage: "play.fill") }
                Button("Cancel") { center.cancel(entry.id) }
            case .queued, .preparing:
                Button("Cancel") { center.cancel(entry.id) }
            case .failed, .cancelled:
                Button { center.enqueue(entry.video) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                Button("Remove", role: .destructive) { center.remove(entry.id) }
            case .ready:
                Button { play(entry) } label: { Label("Play", systemImage: "play.fill") }
                    .disabled(center.localURL(for: entry.id) == nil)
            }
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }

    private func statusDescription(_ entry: OfflineEntry) -> String {
        switch entry.status {
        case .queued: return entry.message ?? "Waiting in queue"
        case .preparing: return "Preparing download…"
        case .downloading:
            var parts = [String]()
            if entry.bytesExpected > 0 {
                parts.append("\(ByteFormat.string(entry.bytesReceived)) of \(ByteFormat.string(entry.bytesExpected))")
            } else {
                parts.append("\(Int(entry.progress * 100))%")
            }
            if entry.format == .hls {
                parts.append("HLS · time estimate unavailable")
            } else if let rate = center.rates[entry.id], rate > 0 {
                parts.append("\(ByteFormat.string(Int64(rate)))/s")
                if entry.bytesExpected > entry.bytesReceived {
                    let remaining = Double(entry.bytesExpected - entry.bytesReceived) / rate
                    parts.append("\(ByteFormat.duration(remaining)) left")
                }
            }
            return parts.joined(separator: " · ")
        case .paused: return "Paused · \(Int(entry.progress * 100))%"
        case .ready:
            guard center.localURL(for: entry.id) != nil else { return "File unavailable" }
            let size = max(entry.bytesExpected, entry.bytesReceived)
            return size > 0 ? "Ready offline · \(ByteFormat.string(size))" : "Ready to watch offline"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        }
    }
}
