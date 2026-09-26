import BookletCore
import SwiftUI

struct AlbumSummaryPanel: View {
    @Environment(\.albumPalette) private var palette
    let track: LocalTrack
    let summary: AlbumSummary?
    let isLoading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALBUM CONTEXT")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(palette.accent)
                    Text(track.album)
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .foregroundStyle(BookletTheme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(track.albumArtist.isEmpty ? track.artist : track.albumArtist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BookletTheme.mutedPaper)
                }

                HStack(alignment: .top, spacing: 28) {
                    artwork
                        .frame(width: 170, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("ABOUT THIS ALBUM")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(palette.accent)

                        if let summary {
                            Text(summary.text)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(BookletTheme.paper)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                            Link("Read the full article ↗", destination: summary.articleURL)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                            Text("From “\(summary.title)” by Wikipedia contributors · CC BY-SA 4.0")
                                .font(.system(size: 10))
                                .foregroundStyle(BookletTheme.mutedPaper)
                            Link("License", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                                .font(.system(size: 10))
                                .foregroundStyle(BookletTheme.mutedPaper)
                        } else if isLoading {
                            ProgressView("Finding the album story…")
                                .tint(palette.accent)
                                .foregroundStyle(BookletTheme.mutedPaper)
                        } else {
                            Text("No matching album article was found. The music and artwork are still here, even when a written history isn't.")
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(BookletTheme.mutedPaper)
                                .lineSpacing(5)
                            Link("Search Wikipedia ↗", destination: wikipediaSearchURL)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Album background is independent of the selected physical-release country. Packaging scans remain country-specific.")
                    .font(.system(size: 10))
                    .foregroundStyle(BookletTheme.mutedPaper.opacity(0.8))
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = track.artworkURL {
            CachedArtworkImage(albumKey: track.albumIdentity.localKey, url: url, maxPixelSize: 700) {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            palette.accent.opacity(0.18)
            Image(systemName: "opticaldisc")
                .font(.system(size: 58, weight: .ultraLight))
                .foregroundStyle(palette.accent)
        }
    }

    private var wikipediaSearchURL: URL {
        var components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        let title = TextNormalization.originalEditionTitle(from: track.album) ?? track.album
        components.queryItems = [URLQueryItem(name: "search", value: "\(title) \(track.albumArtist.isEmpty ? track.artist : track.albumArtist) album")]
        return components.url!
    }
}
