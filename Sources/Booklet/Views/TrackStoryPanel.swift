import BookletCore
import SwiftUI

struct TrackStoryPanel: View {
    @Environment(\.albumPalette) private var palette
    let track: LocalTrack
    let story: TrackStory?
    let isLoading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("THE STORY BEHIND THE TRACK")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(palette.accent)
                Text(track.title)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .foregroundStyle(BookletTheme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Text("\(track.artist) · from \(track.album)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BookletTheme.mutedPaper)
                    .padding(.top, 6)

                Group {
                    if let story {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(paragraphs(in: story.text).enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.system(size: 16, design: .serif))
                                    .foregroundStyle(BookletTheme.paper)
                                    .lineSpacing(8)
                                    .textSelection(.enabled)
                            }
                        }
                        ForEach(Array(story.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 22, weight: .medium, design: .serif))
                                    .foregroundStyle(BookletTheme.paper)
                                ForEach(Array(paragraphs(in: section.text).enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph)
                                        .font(.system(size: 15, design: .serif))
                                        .foregroundStyle(BookletTheme.paper)
                                        .lineSpacing(7)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 26)
                        }
                        if story.sections.isEmpty {
                            Text("No additional sections are available for this song in the matched article.")
                                .font(.system(size: 12))
                                .foregroundStyle(BookletTheme.mutedPaper)
                                .padding(.top, 20)
                        }
                        Link("Read the full article ↗", destination: story.articleURL)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(.top, 28)
                        Text("From “\(story.title)” by Wikipedia contributors · CC BY-SA 4.0")
                            .font(.system(size: 10))
                            .foregroundStyle(BookletTheme.mutedPaper)
                        Link("License", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                            .font(.system(size: 10))
                            .foregroundStyle(BookletTheme.mutedPaper)
                    } else if isLoading {
                        ProgressView("Finding a verified track story…")
                            .tint(palette.accent)
                            .foregroundStyle(BookletTheme.mutedPaper)
                    } else {
                        Text("No confidently matched article was found for this track. Its available credits remain in the sidebar.")
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(BookletTheme.mutedPaper)
                            .lineSpacing(6)
                        Link("Search Wikipedia ↗", destination: wikipediaSearchURL)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .padding(.top, 26)
            }
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(30)
        }
        .scrollIndicators(.hidden)
    }

    private var wikipediaSearchURL: URL {
        var components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        let title = TextNormalization.originalEditionTitle(from: track.title) ?? track.title
        components.queryItems = [URLQueryItem(name: "search", value: "\(title) \(track.artist) song")]
        return components.url!
    }

    private func paragraphs(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
