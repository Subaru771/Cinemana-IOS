import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

private let hubRed = Color(red: 0.98, green: 0.10, blue: 0.21)
private let hubDark = Color(red: 0.075, green: 0.065, blue: 0.082)

/// Compact Cinemana Hub launch card, in the app's selected language.
/// The QR code is generated from the real channel URL, not a decorative image.
struct CinemaHubWelcomeView: View {
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @AppStorage("cinemana-hub-promo-hidden") private var permanentlyHidden = false
    @State private var dontShowAgain = false

    private let channel = URL(string: "https://t.me/CinemanaHub")!
    private var arabic: Bool { CinemanaLocale.isArabic }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                    .onTapGesture { finish() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)
                        card
                            .frame(maxWidth: 405)
                            .padding(.horizontal, 18)
                        Spacer(minLength: 16)
                    }
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("cinemana-hub-welcome-card")
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: finish) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .accessibilityLabel(arabic ? "إغلاق" : "Close")
            }
            .padding(.bottom, 2)

            brand
                .padding(.bottom, 10)

            Text(arabic ? "سينمانا هب" : "Cinemana Hub")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.76)
                .lineLimit(1)

            Text(arabic ? "التحديثات والإعلانات على تلغرام." :
                            "Updates and announcements on Telegram.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
                .padding(.top, 7)

            qrCode
                .padding(.top, 23)
                .padding(.bottom, 23)

            Button {
                openURL(channel)
                finish()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                    Text(arabic ? "انضم على تلغرام" : "Join on Telegram")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 51)
                .background(
                    LinearGradient(colors: [hubRed, Color(red: 0.78, green: 0.04, blue: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cinemana-hub-join")

            Button(action: finish) {
                Text(arabic ? "ليس الآن" : "Not Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            Button { dontShowAgain.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(dontShowAgain ? hubRed : .white.opacity(0.9))
                    Text(arabic ? "لا تُظهر هذه الرسالة مرة أخرى" :
                                  "Don't show this next time")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.91))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 19)
            .accessibilityIdentifier("cinemana-hub-opt-out")
            .accessibilityValue(dontShowAgain ? "1" : "0")

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
                .padding(.top, 17)
                .padding(.bottom, 11)

            Text(arabic ? "قناة اختيارية. يعمل سينمانا من دون تلغرام." :
                          "Optional channel. Cinemana works without Telegram.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.60))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 25)
        .padding(.top, 15)
        .padding(.bottom, 21)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(colors: [Color(red: 0.15, green: 0.09, blue: 0.12),
                                            hubDark, Color(red: 0.055, green: 0.055, blue: 0.071)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(RadialGradient(colors: [hubRed.opacity(0.20), .clear],
                                             center: .topLeading,
                                             startRadius: 10, endRadius: 365))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.55), radius: 25, y: 14)
    }

    private var brand: some View {
        ZStack {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 73, weight: .medium))
                .foregroundStyle(hubRed.opacity(0.40))
                .rotationEffect(.degrees(-14))
                .offset(x: -18, y: -7)

            Image(systemName: "paperplane.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-15))
                .frame(width: 79, height: 79)
                .background(
                    LinearGradient(colors: [Color(red: 0.27, green: 0.77, blue: 1),
                                            Color(red: 0.0, green: 0.40, blue: 0.80)],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.26), lineWidth: 1))
                .shadow(color: Color.blue.opacity(0.30), radius: 13)
        }
        .frame(height: 95)
        .accessibilityHidden(true)
    }

    private var qrCode: some View {
        Group {
            if let image = makeQRCode(channel.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .frame(width: 157, height: 157)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(hubRed.opacity(0.45), lineWidth: 2)
                    }
                    .accessibilityLabel(arabic ? "رمز الانضمام لقناة سينمانا هب" :
                                               "QR code to join Cinemana Hub on Telegram")
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .frame(width: 157, height: 157)
                    .accessibilityHidden(true)
            }
        }
    }

    private func makeQRCode(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func finish() {
        if dontShowAgain { permanentlyHidden = true }
        onClose()
    }
}
