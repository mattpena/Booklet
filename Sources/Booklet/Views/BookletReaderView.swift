import BookletCore
import SwiftUI

struct BookletReaderView: View {
    @Environment(\.albumPalette) private var palette
    let track: LocalTrack
    let match: ReleaseMatch
    let countryCode: String
    let coverOnly: Bool

    @State private var selectedPageID: String?

    private var selectedIndex: Int {
        guard let selectedPageID,
              let index = match.pages.firstIndex(where: { $0.id == selectedPageID }) else { return 0 }
        return index
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if match.source == .originalEditionFallback { originalEditionNotice }
            if coverOnly { coverOnlyNotice }
            pageStrip
            thumbnailStrip
            metadata
        }
        .onAppear { selectedPageID = match.pages.first?.id }
        .background { ArrowKeyNavigation(onMove: step) }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track.album)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(BookletTheme.paper)
                    .lineLimit(1)
                Text(track.albumArtist.isEmpty ? track.artist : track.albumArtist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BookletTheme.mutedPaper)
                HStack(spacing: 6) {
                    Text(countryCode)
                    Text("·")
                    Text(match.release.date?.prefix(4) ?? "DATE UNKNOWN")
                    Text("·")
                    Text(match.source == .localMap ? "CURATED MATCH" : match.source == .originalEditionFallback ? "STANDARD ALBUM MATCH" : "MUSICBRAINZ MATCH")
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(BookletTheme.mutedPaper.opacity(0.75))
            }

            Spacer()

            NativeActionButton("Previous page", isEnabled: selectedIndex > 0) {
                step(-1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }

            Text("\(selectedIndex + 1, format: .number.precision(.integerLength(2))) / \(match.pages.count, format: .number.precision(.integerLength(2)))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BookletTheme.paper)
                .frame(minWidth: 65)

            NativeActionButton("Next page", isEnabled: selectedIndex < match.pages.count - 1) {
                step(1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
        }
        .foregroundStyle(BookletTheme.paper)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 15)
    }

    private var coverOnlyNotice: some View {
        HStack(spacing: 8) {
            Rectangle().fill(palette.accent).frame(width: 2, height: 25)
            Text("No booklet scan for this \(countryCode) edition — showing available packaging art.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BookletTheme.mutedPaper)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var originalEditionNotice: some View {
        HStack(spacing: 8) {
            Rectangle().fill(palette.accent).frame(width: 2, height: 25)
            Text("Deluxe booklet unavailable — showing \(countryCode) scans for the standard album: \(match.release.title).")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BookletTheme.mutedPaper)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var pageStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(match.pages) { page in
                    ZoomableArtworkPanel(page: page, albumKey: track.albumIdentity.localKey, isActive: selectedPageID == page.id)
                    .containerRelativeFrame(.horizontal) { width, _ in width - 48 }
                    .padding(.horizontal, 24)
                    .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selectedPageID)
        .frame(maxHeight: .infinity)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(match.pages) { page in
                    NativeActionButton("Show \(page.displayName)") {
                        withAnimation(.snappy) { selectedPageID = page.id }
                    } label: {
                        CachedArtworkImage(albumKey: track.albumIdentity.localKey, url: page.thumbnailURL, maxPixelSize: 160) {
                            Color.white.opacity(0.05)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selectedPageID == page.id ? palette.accent : Color.clear, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 27)
        }
        .scrollIndicators(.hidden)
        .frame(height: 67)
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Link("MUSICBRAINZ ↗", destination: URL(string: "https://musicbrainz.org/release/\(match.release.id)")!)
            Link("COVER ART ARCHIVE ↗", destination: URL(string: "https://musicbrainz.org/release/\(match.release.id)/cover-art")!)
            Spacer(minLength: 8)
            Text("\(match.pages.count) ARCHIVE ASSET\(match.pages.count == 1 ? "" : "S")")
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .tracking(1.1)
        .foregroundStyle(BookletTheme.mutedPaper.opacity(0.75))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func step(_ delta: Int) {
        let destination = min(max(selectedIndex + delta, 0), match.pages.count - 1)
        withAnimation(.snappy) { selectedPageID = match.pages[destination].id }
    }
}
