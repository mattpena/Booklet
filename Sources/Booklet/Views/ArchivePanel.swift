import BookletCore
import SwiftUI

enum ArchiveTab { case booklet, track, album, news }

struct ArchivePanel: View {
    let selectedTab: ArchiveTab
    let track: LocalTrack
    let countryCode: String
    let countryReady: Bool
    let resolution: ResolveResult?
    let isResolving: Bool
    let error: String?
    let summary: AlbumSummary?
    let isLoadingSummary: Bool
    let trackStory: TrackStory?
    let isLoadingTrackStory: Bool
    let newsArticles: [NewsArticle]
    let isLoadingNews: Bool
    let newsUnavailable: Bool

    var body: some View {
        Group {
            switch selectedTab {
            case .album:
                AlbumSummaryPanel(track: track, summary: summary, isLoading: isLoadingSummary)
            case .track:
                TrackStoryPanel(track: track, story: trackStory, isLoading: isLoadingTrackStory)
            case .news:
                NewsPanel(track: track, articles: newsArticles, isLoading: isLoadingNews, isUnavailable: newsUnavailable)
            case .booklet:
                bookletContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bookletContent: some View {
        Group {
            if !countryReady {
                ArchiveLoadingView(album: track.album, message: "Finding your release country…")
            } else if isResolving {
                ArchiveLoadingView(album: track.album)
            } else if let error {
                ArchiveMessageView(
                    kicker: "ARCHIVE UNAVAILABLE",
                    title: "The booklet could not be opened.",
                    message: error
                )
            } else if let resolution {
                switch resolution {
                case .found(let match):
                    BookletReaderView(track: track, match: match, countryCode: countryCode, coverOnly: false)
                        .id(match.release.id)
                case .coverOnly(let match):
                    BookletReaderView(track: track, match: match, countryCode: countryCode, coverOnly: true)
                        .id(match.release.id)
                case .notFound(let reason):
                    ArchiveMessageView(
                        kicker: "ARCHIVE NOTE",
                        title: reason == .noRelease
                            ? "No \(countryCode) release found."
                            : "No scans for this \(countryCode) release.",
                        message: reason == .noRelease
                            ? "Booklet won't substitute an edition from another country."
                            : "A local edition exists, but its physical package has not been scanned yet."
                    )
                }
            } else {
                ArchiveLoadingView(album: track.album)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArchiveLoadingView: View {
    @Environment(\.albumPalette) private var palette
    let album: String
    var message = "Matching the release and looking for original scans."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(palette.accent)
            Text("OPENING THE PACKAGE")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(palette.accent)
            Text(album)
                .font(.system(size: 29, weight: .medium, design: .serif))
                .foregroundStyle(BookletTheme.paper)
            Text(message)
                .foregroundStyle(BookletTheme.mutedPaper)
        }
    }
}

private struct ArchiveMessageView: View {
    @Environment(\.albumPalette) private var palette
    let kicker: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 50, weight: .thin))
                .foregroundStyle(palette.accent)
            Text(kicker)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(BookletTheme.paper)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(BookletTheme.mutedPaper)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .lineSpacing(4)
        }
        .padding(40)
    }
}
