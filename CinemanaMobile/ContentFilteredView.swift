import SwiftUI

struct ContentFilteredView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "eye.slash.fill").font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Hidden by content filter").font(.title2.weight(.bold))
            Text("Turn off Hide Mature Content in Settings to view this title.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
