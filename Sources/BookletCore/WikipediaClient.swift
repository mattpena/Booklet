import Foundation

public struct AlbumSummary: Equatable, Sendable {
    public let title: String
    public let text: String
    public let articleURL: URL
    public let sections: [ArticleSection]

    public init(title: String, text: String, articleURL: URL, sections: [ArticleSection] = []) {
        self.title = title
        self.text = text
        self.articleURL = articleURL
        self.sections = sections
    }
}

public struct TrackStory: Equatable, Sendable {
    public let title: String
    public let text: String
    public let articleURL: URL
    public let sections: [ArticleSection]

    public init(title: String, text: String, articleURL: URL, sections: [ArticleSection] = []) {
        self.title = title
        self.text = text
        self.articleURL = articleURL
        self.sections = sections
    }
}

public struct ArticleSection: Equatable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

public struct WikipediaClient: Sendable {
    private let session: URLSession
    private let userAgent: String

    public init(session: URLSession = .shared, contact: String = "https://github.com/booklet-app") {
        self.session = session
        self.userAgent = "Booklet/0.1 (\(contact))"
    }

    public func summary(for album: AlbumIdentity) async throws -> AlbumSummary? {
        let artist = album.artists.first ?? ""
        guard !album.title.isEmpty, !artist.isEmpty else { return nil }

        let originalTitle = TextNormalization.originalEditionTitle(from: album.title)
        let titles = originalTitle.map { [$0, album.title] } ?? [album.title]
        for title in titles {
            var search = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/page")!
            search.queryItems = [
                URLQueryItem(name: "q", value: "\(title) \(artist) album"),
                URLQueryItem(name: "limit", value: "8"),
            ]
            let results = try JSONDecoder().decode(SearchResponse.self, from: await request(search.url!))
            guard let page = Self.bestPage(in: results.pages, title: title, artist: artist),
                  let article = try await article(for: page) else { continue }
            let extract = try? await fullExtract(for: page)
            let introduction = extract.flatMap(Self.introduction)
            let text = introduction.flatMap { $0.count > article.text.count ? $0 : nil } ?? article.text
            let sections = extract.map(Self.sections) ?? []
            return AlbumSummary(title: article.title, text: text, articleURL: article.url, sections: sections)
        }
        return nil
    }

    public func story(for track: LocalTrack) async throws -> TrackStory? {
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !track.title.isEmpty, !artist.isEmpty else { return nil }

        let originalTitle = TextNormalization.originalEditionTitle(from: track.title)
        let titles = originalTitle.map { [$0, track.title] } ?? [track.title]
        for title in titles {
            var search = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/page")!
            search.queryItems = [
                URLQueryItem(name: "q", value: "\(title) \(artist) song"),
                URLQueryItem(name: "limit", value: "8"),
            ]
            let results = try JSONDecoder().decode(SearchResponse.self, from: await request(search.url!))
            guard let page = Self.bestSongPage(in: results.pages, title: title, artist: artist),
                  let article = try await article(for: page) else { continue }
            let extract = try? await fullExtract(for: page)
            let introduction = extract.flatMap(Self.introduction)
            let text = introduction.flatMap { $0.count > article.text.count ? $0 : nil } ?? article.text
            let sections = extract.map(Self.sections) ?? []
            return TrackStory(title: article.title, text: text, articleURL: article.url, sections: sections)
        }
        return nil
    }

    private func fullExtract(for page: SearchPage) async throws -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsectionformat", value: "wiki"),
            URLQueryItem(name: "titles", value: page.key.replacingOccurrences(of: "_", with: " ")),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        let response = try JSONDecoder().decode(FullExtractResponse.self, from: await request(components.url!))
        return response.query?.pages.first?.extract
    }

    private func article(for page: SearchPage) async throws -> (title: String, text: String, url: URL)? {
        let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(page.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page.key)")!
        let result = try JSONDecoder().decode(SummaryResponse.self, from: await request(summaryURL))
        guard result.type != "disambiguation",
              let extract = result.extract?.trimmingCharacters(in: .whitespacesAndNewlines),
              !extract.isEmpty,
              let articleURL = result.contentURLs?.desktop?.page else { return nil }
        return (result.title, extract, articleURL)
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw WikipediaError.unavailable
        }
        return data
    }

    static func bestPage(in pages: [SearchPage], title: String, artist: String) -> SearchPage? {
        let expectedTitle = TextNormalization.normalize(title)
        let expectedArtist = TextNormalization.normalize(artist)
        return pages.first { page in
            let normalizedTitle = TextNormalization.normalize(page.title)
            let titleMatches = normalizedTitle == expectedTitle ||
                (normalizedTitle.hasPrefix("\(expectedTitle) ") && normalizedTitle.hasSuffix(" album"))
            let description = TextNormalization.normalize(page.description ?? "")
            let context = TextNormalization.normalize("\(page.description ?? "") \(page.excerpt ?? "")")
            return titleMatches && description.contains("album") && context.contains(expectedArtist)
        }
    }

    static func bestSongPage(in pages: [SearchPage], title: String, artist: String) -> SearchPage? {
        let expectedTitle = TextNormalization.normalize(title)
        let expectedArtist = TextNormalization.normalize(artist)
        return pages.first { page in
            let normalizedTitle = TextNormalization.normalize(page.title)
            let description = TextNormalization.normalize(page.description ?? "")
            let titleMatches = normalizedTitle == expectedTitle ||
                normalizedTitle == "\(expectedTitle) song" ||
                (normalizedTitle.hasPrefix("\(expectedTitle) ") &&
                 normalizedTitle.contains(expectedArtist) && normalizedTitle.hasSuffix(" song"))
            return titleMatches && (description.contains("song") || description.contains("single")) &&
                description.contains(expectedArtist)
        }
    }

    static func sections(from extract: String) -> [ArticleSection] {
        let ignoredTitles: Set<String> = [
            "references", "notes", "external links", "see also", "further reading",
            "track listing", "track listings", "charts", "chart performance",
            "weekly charts", "year end charts", "certifications", "release history",
        ]
        var sections: [ArticleSection] = []
        var currentTitle: String?
        var currentLines: [String] = []
        var ignoredDepth: Int?

        func appendCurrentSection() {
            guard let currentTitle else { return }
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count >= 60 else { return }
            let paragraphs = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let selected = Array(paragraphs.prefix(3)).joined(separator: "\n")
            guard !selected.isEmpty else { return }
            sections.append(ArticleSection(title: currentTitle, text: selected))
        }

        for line in extract.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let depth = trimmed.prefix(while: { $0 == "=" }).count
            if depth >= 2, trimmed.reversed().prefix(while: { $0 == "=" }).count == depth {
                appendCurrentSection()
                currentLines = []
                let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                let normalized = TextNormalization.normalize(title)
                if let ignoredDepth, depth > ignoredDepth {
                    currentTitle = nil
                } else if ignoredTitles.contains(normalized) || normalized.hasPrefix("chart ") || normalized.hasPrefix("certification ") {
                    ignoredDepth = depth
                    currentTitle = nil
                } else {
                    ignoredDepth = nil
                    currentTitle = title.isEmpty ? nil : title
                }
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }
        appendCurrentSection()
        return Array(sections.prefix(6))
    }

    static func introduction(from extract: String) -> String? {
        let lines = extract.components(separatedBy: .newlines)
            .prefix { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("==") }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 20 ? text : nil
    }
}

private enum WikipediaError: Error {
    case unavailable
}

private struct SearchResponse: Decodable {
    let pages: [WikipediaClient.SearchPage]
}

extension WikipediaClient {
    struct SearchPage: Decodable {
        let key: String
        let title: String
        let description: String?
        let excerpt: String?
    }
}

private struct SummaryResponse: Decodable {
    let title: String
    let extract: String?
    let type: String?
    let contentURLs: ContentURLs?

    enum CodingKeys: String, CodingKey {
        case title, extract, type
        case contentURLs = "content_urls"
    }
}

private struct FullExtractResponse: Decodable {
    let query: FullExtractQuery?
}

private struct FullExtractQuery: Decodable {
    let pages: [FullExtractPage]
}

private struct FullExtractPage: Decodable {
    let extract: String?
}

private struct ContentURLs: Decodable {
    let desktop: DesktopURL?
}

private struct DesktopURL: Decodable {
    let page: URL
}
