import Foundation

public struct NewsArticle: Equatable, Sendable, Identifiable {
    public let title: String
    public let url: URL
    public let source: String
    public let publishedAt: Date?

    public var id: URL { url }

    public init(title: String, url: URL, source: String, publishedAt: Date?) {
        self.title = title
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
    }
}

public struct GoogleNewsClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func articles(for album: AlbumIdentity) async throws -> [NewsArticle] {
        guard let artist = album.artists.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              artist.count >= 3 else { return [] }
        let country = Locale.autoupdatingCurrent.region?.identifier ?? "US"
        let language = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
        var request = URLRequest(url: Self.searchURL(artist: artist, country: country, language: language))
        request.timeoutInterval = 12
        request.setValue("application/rss+xml, application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw GoogleNewsError.unavailable
        }
        return try Self.decodeArticles(from: data)
    }

    static func searchURL(artist: String, country: String = "US", language: String = "en") -> URL {
        let safeArtist = artist.replacingOccurrences(of: "\"", with: " ")
        let region = country.uppercased()
        let locale = language.lowercased()
        var components = URLComponents(string: "https://news.google.com/rss/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\"\(safeArtist)\" when:30d"),
            URLQueryItem(name: "hl", value: "\(locale)-\(region)"),
            URLQueryItem(name: "gl", value: region),
            URLQueryItem(name: "ceid", value: "\(region):\(locale)"),
        ]
        return components.url!
    }

    static func decodeArticles(from data: Data) throws -> [NewsArticle] {
        let reader = GoogleNewsFeedReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { throw GoogleNewsError.unavailable }
        var seen = Set<URL>()
        return reader.articles
            .filter { seen.insert($0.url).inserted }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(12)
            .map { $0 }
    }
}

private enum GoogleNewsError: Error {
    case unavailable
}

private final class GoogleNewsFeedReader: NSObject, XMLParserDelegate {
    private struct FeedItem {
        var title = ""
        var link = ""
        var source = ""
        var pubDate = ""
    }

    private var currentItem: FeedItem?
    private var currentField: String?
    private var fieldText = ""
    private(set) var articles: [NewsArticle] = []

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" { currentItem = FeedItem() }
        guard currentItem != nil, ["title", "link", "source", "pubDate"].contains(elementName) else { return }
        currentField = elementName
        fieldText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentField != nil { fieldText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if currentField == elementName {
            let value = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "title": currentItem?.title = value
            case "link": currentItem?.link = value
            case "source": currentItem?.source = value
            case "pubDate": currentItem?.pubDate = value
            default: break
            }
            currentField = nil
        }
        guard elementName == "item", let item = currentItem else { return }
        currentItem = nil
        guard let url = URL(string: item.link), url.scheme == "https",
              url.host == "news.google.com", !item.title.isEmpty else { return }
        let suffix = " - \(item.source)"
        let title = item.source.isEmpty || !item.title.hasSuffix(suffix)
            ? item.title
            : String(item.title.dropLast(suffix.count))
        articles.append(NewsArticle(
            title: title,
            url: url,
            source: item.source.isEmpty ? "Google News" : item.source,
            publishedAt: dateFormatter.date(from: item.pubDate)
        ))
    }
}
