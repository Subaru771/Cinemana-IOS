import SwiftUI

/// Original red filmstrip artwork, generated as an image asset during the iOS build.
struct CinemanaGlyph: View {
    var body: some View {
        Image("CinemanaArtwork")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel("Cinemana iOS")
    }
}

/// Lets the opening animation end when the Home catalog has actually been
/// restored or fetched, rather than waiting an arbitrary number of seconds.
@MainActor
final class CinemanaStartupState: ObservableObject {
    @Published private(set) var catalogReady = false

    func finishInitialCatalogLoad() {
        catalogReady = true
    }
}

/// Lightweight cinematic opening, rendered locally without waiting for network
/// images or creating a second AVPlayer. SwiftUI respects Reduce Motion.
struct CinemanaSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var lightSweep = false

    private let scarlet = Color(red: 1.0, green: 0.15, blue: 0.23)
    private let midnight = Color(red: 0.025, green: 0.008, blue: 0.014)

    var body: some View {
        GeometryReader { geometry in
            let logoSize = min(238, max(150, min(geometry.size.width * 0.61,
                                                geometry.size.height * 0.30)))

            ZStack {
                midnight

                RadialGradient(colors: [scarlet.opacity(0.23), .clear],
                               center: .init(x: 0.52, y: 0.42),
                               startRadius: 10, endRadius: geometry.size.width * 0.78)

                cinematicStreaks(in: geometry.size)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(scarlet.opacity(0.23))
                                .frame(width: logoSize * 0.83, height: logoSize * 0.83)
                                .blur(radius: 50)

                            CinemanaGlyph()
                                .frame(width: logoSize, height: logoSize)
                                .shadow(color: scarlet.opacity(0.27), radius: 28, y: 8)
                        }
                        .scaleEffect(revealed ? 1 : 0.87)
                        .opacity(revealed ? 1 : 0)

                        Text("CINEMANA")
                            .font(.system(size: min(34, geometry.size.width * 0.082),
                                          weight: .black, design: .rounded))
                            .tracking(3.6)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.top, 23)

                        HStack(spacing: 12) {
                            Capsule().fill(scarlet.opacity(0.8)).frame(width: 27, height: 1)
                            Text("iOS")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(4)
                                .foregroundStyle(Color.white.opacity(0.85))
                            Capsule().fill(scarlet.opacity(0.8)).frame(width: 27, height: 1)
                        }
                        .padding(.top, 12)

                        Text("YOUR CINEMA. YOUR SCREEN.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(.white.opacity(0.48))
                            .padding(.top, 23)
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 13)

                    Spacer(minLength: 26)

                    VStack(spacing: 14) {
                        GeometryReader { track in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.11))
                                Capsule()
                                    .fill(LinearGradient(colors: [scarlet.opacity(0.25),
                                                                  scarlet, Color(red: 1, green: 0.55, blue: 0.57)],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: track.size.width * 0.31)
                                    .offset(x: lightSweep ? track.size.width * 0.69 : 0)
                            }
                            .clipShape(Capsule())
                        }
                        .frame(width: min(175, geometry.size.width * 0.47), height: 3)
                        .accessibilityHidden(true)

                        Text("PREPARING YOUR EXPERIENCE")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(1.9)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 16))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(midnight)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cinemana iOS is opening")
        .task {
            if reduceMotion {
                revealed = true
                lightSweep = true
            } else {
                withAnimation(.easeOut(duration: 0.58)) { revealed = true }
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    lightSweep = true
                }
            }
        }
    }

    @ViewBuilder
    private func cinematicStreaks(in size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [.clear, scarlet.opacity(0.36), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: size.width * 1.4, height: 76)
                .rotationEffect(.degrees(-24))
                .offset(x: -size.width * 0.25, y: -size.height * 0.37)
                .blur(radius: 18)

            LinearGradient(colors: [.clear, scarlet.opacity(0.14), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: size.width * 1.4, height: 57)
                .rotationEffect(.degrees(-23))
                .offset(x: size.width * 0.30, y: size.height * 0.38)
                .blur(radius: 20)

            RoundedRectangle(cornerRadius: 2)
                .fill(scarlet.opacity(0.28))
                .frame(width: size.width * 1.4, height: 1)
                .rotationEffect(.degrees(-25))
                .offset(x: -size.width * 0.26, y: -size.height * 0.39)
                .blur(radius: 1)
        }
    }
}
