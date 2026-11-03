import SwiftUI

/// Red film-strip C brand mark, retaining the visual identity of CinemanaTV.
/// Vector artwork remains crisp on navigation bars, splash screens and iPad.
struct CinemanaGlyph: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let dx = (size.width - side) / 2
            let dy = (size.height - side) / 2
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: dx + x * side, y: dy + y * side)
            }
            var ribbon = Path()
            ribbon.move(to: point(0.83, 0.16))
            ribbon.addCurve(to: point(0.34, 0.10),
                            control1: point(0.66, 0.07), control2: point(0.46, 0.02))
            ribbon.addCurve(to: point(0.10, 0.40),
                            control1: point(0.18, 0.14), control2: point(0.10, 0.27))
            ribbon.addLine(to: point(0.10, 0.60))
            ribbon.addCurve(to: point(0.36, 0.90),
                            control1: point(0.10, 0.77), control2: point(0.20, 0.86))
            ribbon.addCurve(to: point(0.83, 0.82),
                            control1: point(0.51, 0.97), control2: point(0.70, 0.90))
            ribbon.addLine(to: point(0.80, 0.66))
            ribbon.addCurve(to: point(0.44, 0.72),
                            control1: point(0.63, 0.78), control2: point(0.53, 0.79))
            ribbon.addCurve(to: point(0.33, 0.58),
                            control1: point(0.37, 0.69), control2: point(0.32, 0.62))
            ribbon.addLine(to: point(0.33, 0.43))
            ribbon.addCurve(to: point(0.43, 0.28),
                            control1: point(0.33, 0.36), control2: point(0.37, 0.30))
            ribbon.addCurve(to: point(0.80, 0.32),
                            control1: point(0.53, 0.22), control2: point(0.65, 0.27))
            ribbon.closeSubpath()

            context.fill(ribbon, with: .linearGradient(
                Gradient(colors: [Color(red: 1.00, green: 0.47, blue: 0.48),
                                  Color(red: 0.99, green: 0.09, blue: 0.17),
                                  Color(red: 0.64, green: 0.00, blue: 0.05)]),
                startPoint: point(0.18, 0.08), endPoint: point(0.90, 0.88)))
            context.stroke(ribbon, with: .color(.white.opacity(0.23)),
                           lineWidth: side * 0.011)

            // Film perforations on the upper and lower curved ribbon.
            for (x, y, rotation) in [
                (0.21, 0.30, -26.0), (0.28, 0.20, -17.0),
                (0.39, 0.16, -8.0), (0.52, 0.15, 2.0),
                (0.20, 0.70, 23.0), (0.30, 0.82, 13.0),
                (0.43, 0.85, 5.0), (0.56, 0.85, -5.0)
            ] {
                var slot = Path(roundedRect: CGRect(x: -side * 0.020,
                                                    y: -side * 0.029,
                                                    width: side * 0.040,
                                                    height: side * 0.058),
                                cornerRadius: side * 0.009)
                let transform = CGAffineTransform(rotationAngle: CGFloat(rotation * .pi / 180))
                    .concatenating(CGAffineTransform(translationX: point(x, y).x,
                                                    y: point(x, y).y))
                slot = slot.applying(transform)
                context.fill(slot, with: .color(Color(red: 0.10, green: 0.005, blue: 0.015)))
            }

            var triangle = Path()
            triangle.move(to: point(0.47, 0.36))
            triangle.addQuadCurve(to: point(0.47, 0.64), control: point(0.45, 0.51))
            triangle.addQuadCurve(to: point(0.72, 0.52), control: point(0.82, 0.50))
            triangle.addQuadCurve(to: point(0.47, 0.36), control: point(0.55, 0.37))
            context.fill(triangle, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.58, blue: 0.58),
                                  Color(red: 1.0, green: 0.08, blue: 0.12)]),
                startPoint: point(0.47, 0.32), endPoint: point(0.72, 0.68)))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Cinemana filmstrip logo")
    }
}

/// First in-app frame: brand identity while the catalog initializes.
/// It is an overlay, so network loading can run in parallel.
struct CinemanaSplashView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // When the approved splash artwork is present in Assets.xcassets,
                // render it directly; otherwise retain the vector fallback.
                if UIImage(named: "CinemanaSplash") != nil {
                    Color.black
                    Image("CinemanaSplash")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                LinearGradient(colors: [.black, Color(red: 0.12, green: 0, blue: 0.015),
                                        Color(red: 0.25, green: 0, blue: 0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .stroke(Color.red.opacity(0.38), lineWidth: 18)
                    .frame(width: geometry.size.width * 1.6, height: geometry.size.height * 0.65)
                    .rotationEffect(.degrees(-26))
                    .offset(x: -geometry.size.width * 0.42,
                            y: -geometry.size.height * 0.40)
                    .blur(radius: 9)
                Ellipse()
                    .stroke(Color.red.opacity(0.25), lineWidth: 16)
                    .frame(width: geometry.size.width * 1.6, height: geometry.size.height * 0.75)
                    .rotationEffect(.degrees(-23))
                    .offset(x: geometry.size.width * 0.46,
                            y: geometry.size.height * 0.56)
                    .blur(radius: 11)
                VStack(spacing: 13) {
                    CinemanaGlyph().frame(width: min(180, geometry.size.width * 0.50),
                                           height: min(180, geometry.size.width * 0.50))
                    Text("Cinemana")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("iOS")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 21).padding(.vertical, 7)
                        .background(Color.red.opacity(0.5), in: Capsule())
                    ProgressView()
                        .tint(.red)
                        .padding(.top, 22)
                }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
        }
        .background(.black)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting Cinemana iOS")
    }
}
