import SwiftUI
import ImageIO
import UIKit

/// Downsample decoded posters off the main thread; preserve a modest memory cache.
final class PosterImageCache: @unchecked Sendable {
    static let shared = PosterImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 400
    }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    private func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = image(for: url) { return hit }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              !Task.isCancelled else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) {
            PosterImageCache.downsample(data, maxPixel: maxPixel)
        }.value
        guard let decoded else { return nil }
        store(decoded, for: url)
        return decoded
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
