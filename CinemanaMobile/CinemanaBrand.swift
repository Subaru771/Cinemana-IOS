import SwiftUI
import UIKit

/// Prefer the user's full-resolution original artwork. Older GitHub builds
/// bundled a 256px placeholder; that is never enlarged for the startup UI.
private enum CinemanaLogoSource {
    static let sharpArtworkAvailable: Bool = {
        guard let asset = UIImage(named: "CinemanaArtwork"), let image = asset.cgImage else {
            return false
        }
        return image.width >= 1024 && image.height >= 1024
    }()
}

struct CinemanaGlyph: View {
    var body: some View {
        Group {
            if CinemanaLogoSource.sharpArtworkAvailable {
                Image("CinemanaArtwork")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                CinemanaVectorFallbackGlyph()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Cinemana iOS")
    }
}

private struct CinemanaVectorFallbackGlyph: View {
    private let ruby = Color(red: 0.98, green: 0.08, blue: 0.16)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Text("C")
                    .font(.system(size: side * 0.90, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.57, blue: 0.61),
                                                             ruby, Color(red: 0.63, green: 0.005, blue: 0.06)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: ruby.opacity(0.43), radius: side * 0.04)
                Image(systemName: "play.fill")
                    .font(.system(size: side * 0.29, weight: .black))
                    .foregroundStyle(.white)
                    .offset(x: side * 0.10, y: -side * 0.015)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

@MainActor
final class CinemanaStartupState: ObservableObject {
    @Published private(set) var catalogReady = false
    func finishInitialCatalogLoad() { catalogReady = true }
}

/// The approved full-screen, red and black Cinemana iOS splash screen.
struct CinemanaSplashView: View {
    var body: some View {
        GeometryReader { geometry in
            Image("CinemanaSplash")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .accessibilityHidden(true)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cinemana iOS is opening")
    }
}
