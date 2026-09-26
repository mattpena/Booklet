import BookletCore
import SwiftUI

struct NewsPanel: View {
    @Environment(\.albumPalette) private var palette
    let track: LocalTrack
    let articles: [NewsArticle]
    let isLoading: Bool
    let isUnavailable: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("GOOGLE NEWS · LAST 30 DAYS")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(palette.accent)
                Text("News")
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .foregroundStyle(BookletTheme.paper)
                    .padding(.top, 8)
                Text("Recent results for \(track.albumArtist.isEmpty ? track.artist : track.albumArtist)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BookletTheme.mutedPaper)
                    .padding(.top, 6)

                if isLoading {
                    ProgressView("Searching Google News…")
                        .tint(palette.accent)
                        .foregroundStyle(BookletTheme.mutedPaper)
                        .padding(.top, 28)
                } else if isUnavailable {
                    emptyState("Google News could not be loaded. Try refreshing or open the search in your browser.")
                } else if articles.isEmpty {
                    emptyState("No recent Google News results were found for this artist.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(articles) { article in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(articleMetadata(article))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(palette.accent)
                                Link(article.title, destination: article.url)
                                    .font(.system(size: 21, weight: .medium, design: .serif))
                                    .foregroundStyle(BookletTheme.paper)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                            .overlay(alignment: .bottom) { BookletTheme.hairline.frame(height: 1) }
                        }
                    }
                    .padding(.top, 15)
                }

                Link("View all results on Google News ↗", destination: googleNewsSearchURL)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 26)
                Text("Headlines and dates from Google News. Open a result to read it at the publisher. Feed use is for personal, non-commercial reading.")
                    .font(.system(size: 10))
                    .foregroundStyle(BookletTheme.mutedPaper)
                    .padding(.top, 14)
            }
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(30)
        }
        .scrollIndicators(.hidden)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 16, design: .serif))
            .foregroundStyle(BookletTheme.mutedPaper)
            .lineSpacing(6)
            .padding(.top, 28)
    }

    private func articleMetadata(_ article: NewsArticle) -> String {
        let source = article.source.uppercased()
        guard let date = article.publishedAt else { return source }
        return "\(source) · \(date.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())"
    }

    private var googleNewsSearchURL: URL {
        let artist = track.albumArtist.isEmpty ? track.artist : track.albumArtist
        var components = URLComponents(string: "https://news.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\"\(artist)\" when:30d")]
        return components.url!
    }
}
