import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

private let hubRed = Color(red: 0.96, green: 0.09, blue: 0.18)
private let hubBackground = Color(red: 0.035, green: 0.035, blue: 0.055)

/// First-launch, bilingual invitation to the optional Cinema Hub Telegram channel.
/// Rendered natively so links and controls work on narrow iPhone screens and in RTL.
struct CinemaHubWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("cinemana-hub-promo-hidden") private var permanentlyHidden = false
    @State private var dontShowAgain = false

    private let channel = URL(string: "https://t.me/CinemanaHub")!

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    brand
                    VStack(spacing: 8) {
                        Text("Follow our Telegram Channel")
                            .font(.title3.weight(.bold))
                        Text("تابع قناتنا على تلغرام")
                            .font(.title3.weight(.bold))
                            .environment(\.layoutDirection, .rightToLeft)
                        Text("Get the latest updates, new releases and app news.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                        Text("للحصول على آخر التحديثات والإصدارات الجديدة وأخبار التطبيق.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 18) {
                        featureList
                        Spacer(minLength: 0)
                        qrCode
                    }
                    .padding(13)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        openURL(channel)
                        finish()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.fill")
                            VStack(spacing: 2) {
                                Text("Join on Telegram")
                                    .font(.headline)
                                Text("انضم على تلغرام")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(hubRed.gradient, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Join Cinema Hub on Telegram")

                    Button(action: finish) {
                        HStack(spacing: 11) {
                            Text("Not Now")
                            Text("•")
                            Text("ليس الآن")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: $dontShowAgain) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Don't show this next time")
                            Text("لا تُظهر هذه الرسالة مرة أخرى")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        .font(.subheadline)
                    }
                    .tint(hubRed)
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("cinemana-hub-opt-out")

                }
                .padding(.horizontal, 24)
                .padding(.vertical, max(25, geometry.safeAreaInsets.top + 12))
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background {
            ZStack {
                hubBackground
                RadialGradient(colors: [Color(red: 0.39, green: 0.025, blue: 0.07),
                                        hubBackground],
                               center: .topLeading, startRadius: 0, endRadius: 570)
                LinearGradient(colors: [.red.opacity(0.12), .clear, .red.opacity(0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .ignoresSafeArea()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(hubRed.opacity(0.72), lineWidth: 1)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        // Also honor the checkbox if the sheet is dismissed by swiping down.
        .onDisappear {
            if dontShowAgain { permanentlyHidden = true }
        }
    }

    private var brand: some View {
        VStack(spacing: 6) {
            CinemanaGlyph()
                .frame(width: 106, height: 106)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Cinema").foregroundStyle(.white)
                Text("Hub").foregroundStyle(hubRed)
            }
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            Capsule()
                .fill(hubRed)
                .frame(width: 98, height: 3)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 13) {
            feature("megaphone.fill", en: "Updates", ar: "التحديثات")
            feature("film", en: "New releases", ar: "الإصدارات الجديدة")
            feature("paperplane.fill", en: "App news", ar: "أخبار التطبيق")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ symbol: String, en: String, ar: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(hubRed)
                .frame(width: 23)
            VStack(alignment: .leading, spacing: 0) {
                Text(en).font(.subheadline.weight(.semibold))
                Text(ar)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var qrCode: some View {
        VStack(spacing: 6) {
            if let image = makeQRCode(channel.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: 135, height: 135)
                    .accessibilityLabel("QR code to join Cinema Hub on Telegram")
            }
            Text("t.me/CinemanaHub")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func makeQRCode(_ message: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func finish() {
        if dontShowAgain { permanentlyHidden = true }
        dismiss()
    }
}
