import SwiftUI

/// Offline library: storage summary, live queue with pause/resume, and finished downloads.
struct DownloadsView: View {
    @ObservedObject private var center = DownloadCenter.shared
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @State private var watch: Video?
    @State private var confirmDeleteAll = false
    @State private var confirmClearFinished = false

    private var visibleItems: [OfflineEntry] {
        center.items.filter { MatureContentFilter.allows($0.video, hideMature: hideMatureContent) }
    }
    private var queue: [OfflineEntry] { visibleItems.filter { $0.status != .ready } }
    private var finished: [OfflineEntry] { visibleItems.filter { $0.status == .ready } }

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Downloads")
            .background(Color.black)
            .toolbar { toolbarMenu }
            .fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0) }
            .confirmationDialog("Remove completed offline videos?", isPresented: $confirmClearFinished) {
                Button("Remove completed videos", role: .destructive) { center.removeCompleted() }
                Button("Cancel", role: .cancel) { }
            }
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
            Text(LocalizedStringKey(hideMatureContent && !center.items.isEmpty ? "Downloads hidden by content filter" : "No downloads")).font(.title2.bold())
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
                Label(CinemanaLocale.isArabic ? "مستخدم: \(ByteFormat.string(center.usedBytes))" : "\(ByteFormat.string(center.usedBytes)) used", systemImage: "internaldrive")
                Spacer()
                if let free = center.freeBytes {
                    Text(CinemanaLocale.isArabic ? "المتاح: \(ByteFormat.string(free))" : "\(ByteFormat.string(free)) free").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            if let free = center.freeBytes, free > 0 {
                ProgressView(value: Double(max(0, center.usedBytes)),
                             total: Double(free) + Double(max(0, center.usedBytes)))
                    .tint(.mint)
                if free < 1_073_741_824 {
                    Label("Low storage",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
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
                Divider()
                Button(role: .destructive) { confirmClearFinished = true } label: {
                    Label("Remove completed", systemImage: "checkmark.circle")
                }
                .disabled(finished.isEmpty)
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
            RemotePoster(url: entry.video.poster, maxPixel: 240)
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
                Text(entry.video.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if entry.video.episode > 0 {
                    Text(CinemanaLocale.episode(entry.video.season, entry.video.episode))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(statusDescription(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.status == .downloading || entry.status == .paused {
                    ProgressView(value: entry.progress).tint(entry.status == .paused ? Color.gray : Color.mint)
                }
                if let message = entry.message, entry.status == .failed {
                    Text(CinemanaLocale.error(message)).font(.caption2).foregroundStyle(.orange).lineLimit(3)
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
                DownloadQualityMenu(video: entry.video, compact: true, title: "Retry download")
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
        let ar = CinemanaLocale.isArabic
        switch entry.status {
        case .queued: return ar ? "بانتظار الدور" : (entry.message ?? "Waiting in queue")
        case .preparing: return CinemanaLocale.text("Preparing download…")
        case .downloading:
            var parts = [String]()
            if entry.bytesExpected > 0 {
                let received = ByteFormat.string(entry.bytesReceived)
                let expected = ByteFormat.string(entry.bytesExpected)
                parts.append(ar ? "\(received) من \(expected)" : "\(received) of \(expected)")
            } else {
                parts.append("\(Int(entry.progress * 100))%")
            }
            if entry.format == .hls {
                parts.append(CinemanaLocale.text("HLS · time estimate unavailable"))
            } else if let rate = center.rates[entry.id], rate > 0 {
                parts.append("\(ByteFormat.string(Int64(rate)))/\(ar ? "ث" : "s")")
                if entry.bytesExpected > entry.bytesReceived {
                    let remaining = Double(entry.bytesExpected - entry.bytesReceived) / rate
                    parts.append(ar ? "المتبقي \(ByteFormat.duration(remaining))" : "\(ByteFormat.duration(remaining)) left")
                }
            }
            return parts.joined(separator: " · ")
        case .paused: return "\(CinemanaLocale.text("Paused")) · \(Int(entry.progress * 100))%"
        case .ready:
            guard center.localURL(for: entry.id) != nil else { return CinemanaLocale.text("File unavailable") }
            let size = max(entry.bytesExpected, entry.bytesReceived)
            if size <= 0 { return CinemanaLocale.text("Ready to watch offline") }
            return "\(CinemanaLocale.text("Ready offline")) · \(ByteFormat.string(size))"
        case .failed: return CinemanaLocale.text("Download failed")
        case .cancelled: return CinemanaLocale.text("Cancelled")
        }
    }
}
