import SwiftUI

struct ContentFilteredView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "eye.slash.fill").font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Hidden by content filter").font(.title2.weight(.bold))
            Text("This title is classified as mature by the provider. You can change Hide Mature Content in Settings or Player Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("The filter hides classified titles, not individual scenes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
