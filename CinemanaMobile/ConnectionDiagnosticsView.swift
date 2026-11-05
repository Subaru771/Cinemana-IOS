import SwiftUI
import Foundation
import UIKit

/// Non-invasive diagnostic: checks the published catalog endpoint only.
/// It does not route around ISP policies, test arbitrary third-party hosts,
/// or send user/device information to any new service.
struct ConnectionDiagnosticsView: View {
    @State private var checking = false
    @State private var result = "Tap Check connection to test."
    @State private var succeeded: Bool?

    private let catalogURL = URL(string:
        "https://cinemana.shabakaty.com/api/android/video/videoKind/1/categoryNb/0/langNb/0/sortParam/views_desc/itemsPerPage/20/searchTextValue/-/pageNumber/0"
    )!

    var body: some View {
        Form {
            Section {
                Label(succeeded == nil ? "Not checked" : (succeeded == true ? "Connected" : "Can't connect"),
                      systemImage: succeeded == nil ? "questionmark.circle" : (succeeded == true ? "checkmark.circle" : "exclamationmark.triangle"))
                    .foregroundStyle(succeeded == false ? Color.orange : Color.primary)
                Text(result).font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task { await run() }
                } label: {
                    if checking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking…")
                        }
                    } else {
                        Label("Check connection", systemImage: "network")
                    }
                }
                .disabled(checking)
            }
        }
        .navigationTitle("Network diagnostics")
    }

    @MainActor
    private func run() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  (try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])) != nil else {
                succeeded = false
                result = "Cinemana isn't responding on this network. Try another network or try again later."
                return
            }
            succeeded = true
            result = "Everything looks good."
        } catch let error as URLError {
            succeeded = false
            switch error.code {
            case .notConnectedToInternet: result = "You're offline."
            case .timedOut: result = "The connection timed out. Try again."
            default: result = "Can't reach Cinemana right now."
            }
        } catch {
            succeeded = false
            result = "Can't reach Cinemana right now."
        }
    }
}
