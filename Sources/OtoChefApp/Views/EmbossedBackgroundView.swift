import AppKit
import SwiftUI

struct EmbossedBackgroundView: View {
    private static let imageName = "EmbossedDetailBackground"
    private static let backgroundImage: NSImage? = {
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("\(imageName).png")
        return NSImage(contentsOf: fallbackURL)
    }()

    var body: some View {
        GeometryReader { proxy in
            if let backgroundImage = Self.backgroundImage {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
