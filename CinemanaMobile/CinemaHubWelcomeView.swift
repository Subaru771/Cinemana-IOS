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
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                    .onTapGesture { finish() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)
                        Group {
                            if isPad && geometry.size.width >= 710 {
                                landscapeCard
                                    .frame(maxWidth: 1040)
                            } else {
                                card
                                    .frame(maxWidth: 405)
                            }
                        }
                        .padding(.horizontal, isPad ? 30 : 18)
                        Spacer(minLength: 16)
                    }
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
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

            HStack(spacing: 6) {
                feature("bell", arabic ? "تنبيهات التحديث" : "Updates")
                feature("star", arabic ? "ميزات جديدة" : "New Features")
                feature("megaphone", arabic ? "أخبار التطبيق" : "App News")
            }
            .padding(.top, 16)

            qrCode
                .padding(.top, 16)
                .padding(.bottom, 16)

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

    /// Dedicated landscape layout for iPad. Phone uses the compact portrait card.
    /// Both select their own English/Arabic copy from the app language setting.
    private var landscapeCard: some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(spacing: 12) {
                brand
                Text(verbatim: "Cinemana")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                qrCode
                    .padding(.top, 5)
                Text(verbatim: "t.me/CinemanaHub")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(arabic ? "انضم إلى قناتنا على تيليگرام" : "Join Our Telegram Channel")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.78)
                        .lineLimit(2)
                    Spacer()
                    Button(action: finish) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .accessibilityLabel(arabic ? "إغلاق" : "Close")
                }
                Text(arabic
                     ? "تابع آخر التحديثات والإصدارات الجديدة والأخبار المهمة لتطبيق سينمانا."
                     : "Get the latest updates, new releases, and important news about Cinemana.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    feature("bell", arabic ? "تنبيهات التحديث" : "Updates")
                    feature("star", arabic ? "ميزات جديدة" : "New Features")
                    feature("megaphone", arabic ? "أخبار التطبيق" : "App News")
                }
                .padding(.vertical, 9)

                Button {
                    openURL(channel)
                    finish()
                } label: {
                    Label(arabic ? "الانضمام إلى القناة" : "Join the Channel",
                          systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .background(hubRed, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cinemana-hub-join")

                Button(action: finish) {
                    Text(arabic ? "ليس الآن" : "Not Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button { dontShowAgain.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .foregroundStyle(dontShowAgain ? hubRed : .white)
                        Text(arabic ? "عدم إظهار هذه الرسالة مرة أخرى"
                                    : "Don't show this again")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cinemana-hub-opt-out")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [
                    Color(red: 0.30, green: 0.04, blue: 0.13),
                    hubDark,
                    Color(red: 0.12, green: 0.03, blue: 0.07)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(hubRed.opacity(0.42), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(hubRed)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 75)
        .padding(6)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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
