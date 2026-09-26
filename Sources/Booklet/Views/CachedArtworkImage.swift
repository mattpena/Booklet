import AppKit
import BookletCore
import ImageIO
import SwiftUI

struct CachedArtworkImage<Placeholder: View>: View {
    let albumKey: String
    let url: URL
    let maxPixelSize: Int
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            image = await Self.load(albumKey: albumKey, url: url, maxPixelSize: maxPixelSize)
        }
    }

    static func load(albumKey: String, url: URL, maxPixelSize: Int) async -> NSImage? {
        guard !Task.isCancelled,
              let data = await AlbumCacheStore.shared.imageData(albumKey: albumKey, url: url),
              !Task.isCancelled else { return nil }
        let thumbnail = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard !Task.isCancelled, let thumbnail else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
