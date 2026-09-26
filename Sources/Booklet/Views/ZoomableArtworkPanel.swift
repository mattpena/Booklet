import AppKit
import BookletCore
import SwiftUI

struct ZoomableArtworkPanel: View {
    @Environment(\.albumPalette) private var palette
    let page: BookletPage
    let albumKey: String
    let isActive: Bool

    @State private var image: NSImage?
    @State private var loadFailed = false
    @State private var zoom: CGFloat = 1
    @State private var loadedOriginal = false

    var body: some View {
        VStack(spacing: 8) {
            artwork
            caption
        }
        .task(id: isActive) {
            image = nil
            zoom = 1
            loadFailed = false
            loadedOriginal = false
            guard isActive else { return }

            AppDiagnostics.record("artwork preview start")
            if let preview = await CachedArtworkImage<Color>.load(albumKey: albumKey, url: page.previewURL, maxPixelSize: 1600) {
                guard !Task.isCancelled else { return }
                if !loadedOriginal { image = preview }
            }
            guard !Task.isCancelled else { return }
            loadFailed = image == nil
            AppDiagnostics.record("artwork preview finish success=\(image != nil)")
        }
        .task(id: isActive && zoom >= 1.5) {
            guard isActive, zoom >= 1.5, page.imageURL != page.previewURL else { return }
            AppDiagnostics.record("artwork detail start")
            if let original = await CachedArtworkImage<Color>.load(albumKey: albumKey, url: page.imageURL, maxPixelSize: 3000),
               !Task.isCancelled {
                loadedOriginal = true
                image = original
                AppDiagnostics.record("artwork detail finish success=true")
            } else if !Task.isCancelled {
                AppDiagnostics.record("artwork detail finish success=false")
            }
        }
    }

    private var artwork: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    let artworkSize = fittedSize(for: image, in: geometry.size)
                    MagnifyingArtworkView(image: image, viewport: artworkSize, zoom: $zoom)
                        .frame(width: artworkSize.width, height: artworkSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                } else if loadFailed {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32))
                        Text("Artwork could not be loaded")
                    }
                    .foregroundStyle(BookletTheme.mutedPaper)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(palette.accent)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var caption: some View {
        HStack(spacing: 12) {
            Text(page.displayName.uppercased())
            Spacer(minLength: 8)
            Text("ARROW KEYS: TURN PAGE · PINCH: ZOOM")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isActive, image != nil {
                zoomControls
            }
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .tracking(1)
        .foregroundStyle(BookletTheme.mutedPaper.opacity(0.8))
        .padding(.horizontal, 2)
        .frame(height: 36)
    }

    private func fittedSize(for image: NSImage, in available: CGSize) -> CGSize {
        let scale = min(
            available.width / max(image.size.width, 1),
            available.height / max(image.size.height, 1)
        )
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            zoomButton("minus.magnifyingglass", label: "Zoom out", disabled: zoom <= 1.01) {
                zoom = max(1, zoom / 1.5)
            }
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(BookletTheme.paper)
                .frame(minWidth: 42)
            zoomButton("plus.magnifyingglass", label: "Zoom in", disabled: zoom >= 4.99) {
                zoom = min(5, zoom * 1.5)
            }
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 5)
            zoomButton("arrow.down.right.and.arrow.up.left", label: "Fit artwork", disabled: zoom <= 1.01) {
                zoom = 1
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(BookletTheme.raised.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16)))
    }

    private func zoomButton(
        _ symbol: String,
        label: String,
        disabled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        NativeActionButton(label, isEnabled: !disabled, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 26)
        }
        .foregroundStyle(disabled ? BookletTheme.mutedPaper.opacity(0.4) : BookletTheme.paper)
    }
}

private struct MagnifyingArtworkView: NSViewRepresentable {
    let image: NSImage
    let viewport: CGSize
    @Binding var zoom: CGFloat

    func makeNSView(context: Context) -> ArtworkScrollView {
        let scrollView = ArtworkScrollView()
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 5
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: viewport))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = image
        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: ArtworkScrollView, context: Context) {
        if let imageView = scrollView.documentView as? NSImageView {
            if imageView.image !== image { imageView.image = image }
            if imageView.frame.size != viewport {
                imageView.setFrameSize(viewport)
            }
        }

        scrollView.onZoomChange = { zoom = $0 }
        if abs(scrollView.magnification - zoom) > 0.01 {
            scrollView.setMagnification(zoom, centeredAt: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        }
    }
}

private final class ArtworkScrollView: NSScrollView {
    var onZoomChange: ((CGFloat) -> Void)?

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onZoomChange?(magnification)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            setMagnification(1, centeredAt: CGPoint(x: bounds.midX, y: bounds.midY))
            onZoomChange?(1)
        } else {
            super.mouseDown(with: event)
        }
    }
}
