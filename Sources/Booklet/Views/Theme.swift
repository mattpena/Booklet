import AppKit
import SwiftUI

enum BookletTheme {
    static let ink = Color(red: 0.075, green: 0.063, blue: 0.052)
    static let raised = Color(red: 0.13, green: 0.11, blue: 0.095)
    static let paper = Color(red: 0.95, green: 0.91, blue: 0.84)
    static let mutedPaper = Color(red: 0.72, green: 0.67, blue: 0.59)
    static let rust = Color(red: 0.89, green: 0.37, blue: 0.19)
    static let moss = Color(red: 0.55, green: 0.64, blue: 0.45)
    static let spotify = Color(red: 0.12, green: 0.84, blue: 0.38)
    static let hairline = Color.white.opacity(0.12)
}

struct AlbumPalette {
    let accent: Color
    let backdrop: Color
    let glow: Color

    static let standard = AlbumPalette(
        accent: BookletTheme.rust,
        backdrop: BookletTheme.ink,
        glow: Color(red: 0.17, green: 0.14, blue: 0.12)
    )

    @MainActor
    static func fromArtwork(_ data: Data) -> AlbumPalette? {
        guard let image = NSImage(data: data),
              let sample = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 40,
                pixelsHigh: 40,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: sample) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var weights = Array(repeating: 0.0, count: 24)
        var redSums = Array(repeating: 0.0, count: 24)
        var greenSums = Array(repeating: 0.0, count: 24)
        var blueSums = Array(repeating: 0.0, count: 24)
        var neutralBrightness = 0.0
        var neutralSamples = 0

        for row in stride(from: 0, to: 40, by: 2) {
            for column in stride(from: 0, to: 40, by: 2) {
                guard let color = sample.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                neutralBrightness += Double(color.brightnessComponent)
                neutralSamples += 1
                guard color.saturationComponent > 0.18,
                      color.brightnessComponent > 0.12 else { continue }

                let bucket = min(23, Int(color.hueComponent * 24))
                let weight = Double(color.saturationComponent * (0.35 + color.brightnessComponent))
                weights[bucket] += weight
                redSums[bucket] += Double(color.redComponent) * weight
                greenSums[bucket] += Double(color.greenComponent) * weight
                blueSums[bucket] += Double(color.blueComponent) * weight
            }
        }

        guard neutralSamples > 0 else { return nil }

        let accent: NSColor
        if let bucket = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[bucket] > 0 {
            let dominant = NSColor(
                calibratedRed: redSums[bucket] / weights[bucket],
                green: greenSums[bucket] / weights[bucket],
                blue: blueSums[bucket] / weights[bucket],
                alpha: 1
            )
            accent = NSColor(
                calibratedHue: dominant.hueComponent,
                saturation: max(0.48, min(0.82, dominant.saturationComponent)),
                brightness: max(0.68, min(0.9, dominant.brightnessComponent)),
                alpha: 1
            )
        } else {
            accent = NSColor(calibratedWhite: max(0.65, min(0.88, neutralBrightness / Double(neutralSamples))), alpha: 1)
        }
        let backdrop = NSColor(
            calibratedRed: 0.055 + accent.redComponent * 0.12,
            green: 0.05 + accent.greenComponent * 0.12,
            blue: 0.05 + accent.blueComponent * 0.12,
            alpha: 1
        )
        let glow = NSColor(
            calibratedRed: 0.07 + accent.redComponent * 0.2,
            green: 0.065 + accent.greenComponent * 0.2,
            blue: 0.06 + accent.blueComponent * 0.2,
            alpha: 1
        )

        return AlbumPalette(accent: Color(nsColor: accent), backdrop: Color(nsColor: backdrop), glow: Color(nsColor: glow))
    }
}

private struct AlbumPaletteKey: EnvironmentKey {
    static let defaultValue = AlbumPalette.standard
}

extension EnvironmentValues {
    var albumPalette: AlbumPalette {
        get { self[AlbumPaletteKey.self] }
        set { self[AlbumPaletteKey.self] = newValue }
    }
}

struct PaperActionButton: View {
    let title: String
    let filled: Bool
    let action: @MainActor () -> Void

    init(_ title: String, filled: Bool = false, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    var body: some View {
        NativeActionButton(title, action: action) {
            Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? BookletTheme.ink : BookletTheme.paper)
            .padding(.horizontal, 18)
            .frame(minHeight: 42)
            .background(filled ? BookletTheme.paper : Color.white.opacity(0.055))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(filled ? Color.clear : BookletTheme.hairline))
        }
    }
}
