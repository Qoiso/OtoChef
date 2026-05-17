import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OtoChef")
                .font(.largeTitle)
            Text("Japanese audio, Chinese subtitles, still-image video.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
