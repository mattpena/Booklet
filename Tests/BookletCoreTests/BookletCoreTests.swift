import Foundation
import Testing
@testable import BookletCore

@Test("Album keys ignore punctuation, casing, and diacritics")
func albumKeyNormalization() {
    #expect(TextNormalization.normalize("Beyoncé & JAY-Z | EVERYTHING IS LOVE") == "beyonce and jay z everything is love")
}

@Test("Tracks sharing album artwork keep the same album key")
func albumKeyAcrossTracks() {
    let artwork = URL(string: "https://i.scdn.co/image/shared-cover")!
    let first = LocalTrack(
        title: "First", artist: "Lead Artist", album: "The Album", albumArtist: "",
        spotifyURL: "spotify:track:first", artworkURL: artwork, durationMilliseconds: 180_000,
        positionSeconds: 0, playbackState: .playing
    )
    let featured = LocalTrack(
        title: "Second", artist: "Lead Artist & Guest", album: "The Album", albumArtist: "",
        spotifyURL: "spotify:track:second", artworkURL: artwork, durationMilliseconds: 200_000,
        positionSeconds: 0, playbackState: .playing
    )
    #expect(first.albumIdentity.localKey == featured.albumIdentity.localKey)
}

@Test("Only recognized edition suffixes are removed")
func originalEditionTitle() {
    #expect(TextNormalization.originalEditionTitle(from: "Morning View (Deluxe Edition)") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View - Super Deluxe") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View [Expanded Edition]") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View (20th Anniversary Edition)") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View (Deluxe Edition) (2011 Remaster)") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View - Remastered 2021") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View - 2009 Remastered Version") == "Morning View")
    #expect(TextNormalization.originalEditionTitle(from: "Definitely Maybe (Deluxe Edition Remastered)") == "Definitely Maybe")
    #expect(TextNormalization.originalEditionTitle(from: "Definitely Maybe (20th Anniversary Deluxe Edition Remastered)") == "Definitely Maybe")
    #expect(TextNormalization.originalEditionTitle(from: "Morning View (Live)") == nil)
    #expect(TextNormalization.originalEditionTitle(from: "The Anniversary") == nil)
    #expect(TextNormalization.originalEditionTitle(from: "Deluxe") == nil)
}

@Test("A deluxe cover falls back to a same-country original booklet")
func deluxeFallsBackToOriginalBooklet() async throws {
    let session = deluxeStubSession()
    let resolver = BookletResolver(
        musicBrainz: MusicBrainzClient(session: session),
        coverArt: CoverArtClient(session: session)
    )
    let album = AlbumIdentity(localKey: "incubus morning view deluxe", title: "Morning View (Deluxe Edition)", artists: ["Incubus"])
    let result = try await resolver.resolve(album, countryCode: "US")
    let match = try #require(result.match)
    #expect(match.release.id == "original")
    #expect(match.source == .originalEditionFallback)
    #expect(match.hasBooklet)
    #expect(match.pages.map(\.id) == ["front", "booklet"])
}

@Test("Oasis deluxe remaster finds the US original booklet")
func oasisDeluxeFallsBackToUSBooklet() async throws {
    let session = oasisBookletStubSession()
    let resolver = BookletResolver(
        musicBrainz: MusicBrainzClient(session: session),
        coverArt: CoverArtClient(session: session)
    )
    let album = AlbumIdentity(
        localKey: "oasis definitely maybe deluxe", title: "Definitely Maybe (Deluxe Edition Remastered)",
        artists: ["Oasis"]
    )
    let match = try #require(try await resolver.resolve(album, countryCode: "US").match)
    #expect(match.release.id == "698d1229-0724-36c1-9ef0-0705ac4d98c4")
    #expect(match.release.country == "US")
    #expect(match.source == .originalEditionFallback)
    #expect(match.hasBooklet)
    #expect(match.pages.filter(\.isBooklet).count == 5)
}

@Test("An exact deluxe booklet takes precedence over the original")
func exactDeluxeBookletWins() async throws {
    let session = deluxeStubSession()
    let resolver = BookletResolver(
        musicBrainz: MusicBrainzClient(session: session),
        coverArt: CoverArtClient(session: session)
    )
    let album = AlbumIdentity(localKey: "incubus morning view super deluxe", title: "Morning View (Super Deluxe)", artists: ["Incubus"])
    let match = try #require(try await resolver.resolve(album, countryCode: "US").match)
    #expect(match.release.id == "deluxe-booklet")
    #expect(match.source == .musicBrainzSearch)
}

@Test("Deluxe fallback never uses another country's release")
func deluxeFallbackRespectsCountry() async throws {
    let session = deluxeStubSession()
    let resolver = BookletResolver(
        musicBrainz: MusicBrainzClient(session: session),
        coverArt: CoverArtClient(session: session)
    )
    let album = AlbumIdentity(localKey: "incubus morning view deluxe", title: "Morning View (Deluxe Edition)", artists: ["Incubus"])
    let result = try await resolver.resolve(album, countryCode: "GB")
    #expect(result.match == nil)
}

@Test("Exact title and artist matches outrank loose releases")
func metadataRanking() {
    let album = AlbumIdentity(
        localKey: "the prodigy the fat of the land",
        title: "The Fat of the Land",
        artists: ["The Prodigy"]
    )
    let exact = MusicBrainzRelease(
        id: "exact",
        title: "The Fat of the Land",
        score: 100,
        status: "Official",
        date: "1997",
        country: "GB",
        barcode: nil,
        trackCount: 10,
        artistCredit: "The Prodigy",
        releaseGroupID: nil,
        hasCoverArt: true
    )
    let loose = MusicBrainzRelease(
        id: "loose",
        title: "Fat Land Remixes",
        score: 88,
        status: "Official",
        date: "1997",
        country: "GB",
        barcode: nil,
        trackCount: 10,
        artistCredit: "Various Artists",
        releaseGroupID: nil,
        hasCoverArt: true
    )

    let resolver = BookletResolver()
    #expect(resolver.metadataScore(album: album, release: exact) > resolver.metadataScore(album: album, release: loose))
}

@Test("Cover Art Archive order and booklet types are preserved")
func coverArtOrder() throws {
    let json = """
    {
      "images": [
        {
          "id": 1,
          "image": "http://example.com/front.jpg",
          "thumbnails": {"250": "http://example.com/front-250.jpg"},
          "types": ["Front"],
          "approved": true,
          "front": true,
          "back": false
        },
        {
          "id": "2",
          "image": "https://example.com/booklet.jpg",
          "types": ["Booklet"],
          "approved": true,
          "front": false,
          "back": false
        }
      ]
    }
    """

    let pages = try CoverArtClient.decodePages(from: Data(json.utf8))
    #expect(pages.map(\.id) == ["1", "2"])
    #expect(pages[1].isBooklet)
    #expect(pages[0].imageURL.scheme == "https")
}

@Test("MusicBrainz search is limited to the chosen country")
func countrySearchQuery() {
    let album = AlbumIdentity(localKey: "album", title: "Album", artists: ["Artist"])
    let url = MusicBrainzClient.searchURL(for: album, countryCode: "us")
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "query" })?.value
    #expect(query?.contains("country:US") == true)
}

@Test("Multi-country releases match any listed release event")
func multiCountryRelease() async throws {
    let client = MusicBrainzClient(session: stubSession())
    let release = try #require(await client.lookupRelease(id: "mapped"))
    #expect(release.country == "JP")
    #expect(release.isReleased(in: "US"))
    #expect(release.isReleased(in: "JP"))
    #expect(!release.isReleased(in: "GB"))
}

@Test("A saved mapping cannot bypass the country filter")
func mappingRespectsCountry() async throws {
    let session = stubSession()
    let resolver = BookletResolver(
        musicBrainz: MusicBrainzClient(session: session),
        coverArt: CoverArtClient(session: session),
        mappings: LocalMappingRepository(mappings: ["album": "mapped"])
    )
    let album = AlbumIdentity(localKey: "album", title: "Album", artists: ["Artist"])
    #expect(try await resolver.resolve(album, countryCode: "GB") == .notFound(.noRelease))
}

@Test("Wikipedia album summaries reject similarly titled artists")
func wikipediaAlbumSummary() async throws {
    let album = AlbumIdentity(localKey: "artist moonlight", title: "Moonlight (Deluxe Edition)", artists: ["Artist"])
    let summary = try #require(await WikipediaClient(session: contextStubSession()).summary(for: album))
    #expect(summary.title == "Moonlight (Artist album)")
    #expect(summary.text == "Moonlight is an album by Artist.")
    #expect(summary.articleURL.absoluteString == "https://en.wikipedia.org/wiki/Moonlight_(Artist_album)")
}

@Test("Anniversary album stories use the original album article")
func wikipediaAnniversaryAlbumSummary() async throws {
    let album = AlbumIdentity(localKey: "artist moonlight anniversary", title: "Moonlight (20th Anniversary Edition)", artists: ["Artist"])
    let summary = try #require(await WikipediaClient(session: anniversaryStubSession()).summary(for: album))
    #expect(summary.title == "Moonlight (Artist album)")
}

@Test("Oasis deluxe remaster finds the original album article")
func wikipediaOasisDeluxeAlbumSummary() async throws {
    let album = AlbumIdentity(
        localKey: "oasis definitely maybe deluxe", title: "Definitely Maybe (Deluxe Edition Remastered)",
        artists: ["Oasis"]
    )
    let summary = try #require(await WikipediaClient(session: oasisAlbumStubSession()).summary(for: album))
    #expect(summary.title == "Definitely Maybe")
    #expect(summary.articleURL.absoluteString == "https://en.wikipedia.org/wiki/Definitely_Maybe")
}

@Test("Wikipedia track stories require the matching song and artist")
func wikipediaTrackStory() async throws {
    let track = LocalTrack(
        title: "Midnight Static", artist: "The Meridian", album: "Afterglow", albumArtist: "The Meridian",
        spotifyURL: "spotify:track:story", artworkURL: nil, durationMilliseconds: 200_000,
        positionSeconds: 0, playbackState: .playing
    )
    let story = try #require(await WikipediaClient(session: storyStubSession()).story(for: track))
    #expect(story.title == "Midnight Static (The Meridian song)")
    #expect(story.text.contains("single sleeve"))
    #expect(story.sections.map(\.title) == ["Recording", "Music video"])
    #expect(story.sections[0].text.contains("North Room Studios"))
}

@Test("Remastered tracks use the original song article")
func wikipediaRemasteredTrackStory() async throws {
    let track = LocalTrack(
        title: "Midnight Static - 2011 Remaster", artist: "The Meridian", album: "Afterglow", albumArtist: "The Meridian",
        spotifyURL: "spotify:track:remaster", artworkURL: nil, durationMilliseconds: 200_000,
        positionSeconds: 0, playbackState: .playing
    )
    let story = try #require(await WikipediaClient(session: storyStubSession()).story(for: track))
    #expect(story.title == "Midnight Static (The Meridian song)")
}

@Test("Track detail parsing omits reference and chart sections")
func trackDetailSections() {
    let extract = """
    A short introduction.

    == Recording ==
    The band recorded the track at North Room Studios during the album sessions.

    == Charts ==
    === Weekly charts ===
    This table is not a story and should not appear in the Track tab.

    == Live performances ==
    The group first performed the finished arrangement at a local club show.

    == References ==
    Citation list that should not appear in the Track tab.
    """
    let sections = WikipediaClient.sections(from: extract)
    #expect(sections.map(\.title) == ["Recording", "Live performances"])
}

@Test("Track sections retain paragraph boundaries")
func trackParagraphs() {
    let extract = """
    Intro paragraph one.
    Intro paragraph two has more detail.

    == Recording ==
    The group recorded the song in the first studio.
    A second paragraph explains how they finished the arrangement.
    """
    #expect(WikipediaClient.introduction(from: extract) == "Intro paragraph one.\nIntro paragraph two has more detail.")
    #expect(WikipediaClient.sections(from: extract).first?.text.contains("studio.\nA second paragraph") == true)
}

@Test("Unrelated Wikipedia song results are rejected")
func unrelatedSongRejected() {
    let pages = [
        WikipediaClient.SearchPage(
            key: "Midnight_Static_(Other_song)", title: "Midnight Static (Other song)",
            description: "song by Other", excerpt: "The Meridian later covered the song"
        ),
    ]
    #expect(WikipediaClient.bestSongPage(in: pages, title: "Midnight Static", artist: "The Meridian") == nil)
}

@Test("Google News search quotes the artist and uses the selected locale")
func googleNewsSearch() throws {
    let url = GoogleNewsClient.searchURL(artist: "Rage Against the Machine", country: "US", language: "en")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first(where: { $0.name == "q" })?.value == "\"Rage Against the Machine\" when:30d")
    #expect(items.first(where: { $0.name == "gl" })?.value == "US")
    #expect(items.first(where: { $0.name == "ceid" })?.value == "US:en")
}

@Test("Google News feed parses and orders real RSS item fields")
func googleNewsFeed() throws {
    let data = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item><title>Older headline - First Source</title><link>https://news.google.com/rss/articles/older</link><pubDate>Tue, 22 Sep 2026 12:00:00 GMT</pubDate><source>First Source</source></item>
      <item><title>New music &amp; tour - Music Desk</title><link>https://news.google.com/rss/articles/newer</link><pubDate>Fri, 25 Sep 2026 12:00:00 GMT</pubDate><source>Music Desk</source></item>
      <item><title>Duplicate</title><link>https://news.google.com/rss/articles/newer</link><source>Music Desk</source></item>
      <item><title>Unsafe URL</title><link>https://example.com/article</link><source>Other</source></item>
    </channel></rss>
    """.utf8)
    let articles = try GoogleNewsClient.decodeArticles(from: data)
    #expect(articles.map(\.title) == ["New music & tour", "Older headline"])
    #expect(articles[0].source == "Music Desk")
    #expect(articles[0].publishedAt != nil)
}

@Test("Recording relations provide writers, performers, and recording place")
func recordingCredits() async throws {
    let track = LocalTrack(
        title: "A Song", artist: "Artist", album: "Album", albumArtist: "Artist",
        spotifyURL: "spotify:track:test", artworkURL: nil, durationMilliseconds: 200_000,
        positionSeconds: 0, playbackState: .playing
    )
    let details = try #require(await MusicBrainzClient(session: contextStubSession()).songDetails(for: track))
    #expect(details.writers == ["Songwriter"])
    #expect(details.performers == ["Singer"])
    #expect(details.recordedAt == ["Studio One"])
}

@Test("Recording credits are omitted when neither album nor duration matches")
func recordingMatchRequiresEvidence() throws {
    let track = LocalTrack(
        title: "A Song", artist: "Artist", album: "Album", albumArtist: "Artist",
        spotifyURL: "spotify:track:test", artworkURL: nil, durationMilliseconds: 200_000,
        positionSeconds: 0, playbackState: .playing
    )
    let candidate = try JSONDecoder().decode(MusicBrainzClient.RecordingSearchDTO.self, from: Data("""
    {"id":"different-take","title":"A Song","score":100,"length":240000,"artist-credit":[{"name":"Artist"}],"releases":[{"title":"Live Album"}]}
    """.utf8))
    #expect(MusicBrainzClient.bestRecording(in: [candidate], for: track) == nil)
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReleaseStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func contextStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ContextStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func storyStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StoryStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func anniversaryStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AnniversaryStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func oasisAlbumStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OasisAlbumStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class OasisAlbumStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value
        let json: String
        if path.hasSuffix("/search/page") {
            json = query == "Definitely Maybe Oasis album"
                ? """
                  {"pages":[{"key":"Definitely_Maybe","title":"Definitely Maybe","description":"1994 studio album by Oasis","excerpt":"Definitely Maybe is the debut studio album by Oasis"}]}
                  """
                : "{\"pages\":[]}"
        } else {
            json = """
            {"title":"Definitely Maybe","extract":"Definitely Maybe is the debut studio album by Oasis.","type":"standard","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Definitely_Maybe"}}}
            """
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AnniversaryStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value
        let json: String
        if path.hasSuffix("/search/page") {
            json = query == "Moonlight Artist album"
                ? """
                  {"pages":[{"key":"Moonlight_(Artist_album)","title":"Moonlight (Artist album)","description":"album by Artist","excerpt":"Artist released Moonlight"}]}
                  """
                : "{\"pages\":[]}"
        } else {
            json = """
            {"title":"Moonlight (Artist album)","extract":"Moonlight is an album by Artist.","type":"standard","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Moonlight_(Artist_album)"}}}
            """
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class StoryStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data: Data
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value
        if request.url?.path.hasSuffix("/search/page") == true, query == "Midnight Static The Meridian song" {
            let json = """
            {"pages":[
              {"key":"Midnight_Static_(Other_song)","title":"Midnight Static (Other song)","description":"song by Other","excerpt":"Other released it"},
              {"key":"Midnight_Static_(The_Meridian_song)","title":"Midnight Static (The Meridian song)","description":"song by The Meridian","excerpt":"The Meridian recorded it"}
            ]}
            """
            data = Data(json.utf8)
        } else if request.url?.path.hasSuffix("/search/page") == true {
            data = Data("{\"pages\":[]}".utf8)
        } else if request.url?.path.hasSuffix("/api.php") == true {
            let extract = """
            Midnight Static is a song by The Meridian.
            The single sleeve uses artwork from the band's original tour poster.

            == Recording ==
            The band recorded Midnight Static at North Room Studios during the Afterglow sessions.

            == Music video ==
            The video places the band in a dark room as projections move across the walls.
            """
            data = try! JSONSerialization.data(withJSONObject: ["query": ["pages": [["extract": extract]]]])
        } else {
            let json = """
            {"title":"Midnight Static (The Meridian song)","extract":"Midnight Static is a song by The Meridian.","type":"standard","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Midnight_Static_(The_Meridian_song)"}}}
            """
            data = Data(json.utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ContextStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let json: String
        if path.hasSuffix("/search/page") {
            json = """
            {"pages":[
              {"key":"Moonlight_(Other_album)","title":"Moonlight (Other album)","description":"album by Other","excerpt":"Other made this album"},
              {"key":"Moonlight_(Artist_album)","title":"Moonlight (Artist album)","description":"album by Artist","excerpt":"Artist released Moonlight"}
            ]}
            """
        } else if path.contains("/page/summary/") {
            json = """
            {"title":"Moonlight (Artist album)","extract":"Moonlight is an album by Artist.","type":"standard","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Moonlight_(Artist_album)"}}}
            """
        } else if path.contains("/recording"), URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "query" }) == true {
            json = """
            {"recordings":[
              {"id":"wrong","title":"Another Song","score":100,"artist-credit":[{"name":"Artist"}]},
              {"id":"correct","title":"A Song","score":95,"length":200000,"artist-credit":[{"name":"Artist"}],"releases":[{"title":"Album"}]}
            ]}
            """
        } else {
            json = """
            {"id":"correct","relations":[
              {"type":"vocal","artist":{"name":"Singer"}},
              {"type":"recorded at","place":{"name":"Studio One"}},
              {"type":"recording of","work":{"relations":[{"type":"composer","artist":{"name":"Songwriter"}}]}}
            ]}
            """
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func deluxeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeluxeStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func oasisBookletStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OasisBookletStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class OasisBookletStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let json: String
        if url.host == "musicbrainz.org" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value ?? ""
            if query.contains("Deluxe Edition Remastered") {
                json = "{\"releases\":[]}"
            } else {
                json = """
                {"releases":[
                  {"id":"bdf9eda5-7aae-4c36-93f5-b47ff1cbf5ab","title":"Definitely Maybe","score":100,"country":"US","artist-credit":[{"name":"Oasis"}]},
                  {"id":"698d1229-0724-36c1-9ef0-0705ac4d98c4","title":"Definitely Maybe","score":100,"country":"US","artist-credit":[{"name":"Oasis"}]},
                  {"id":"572ac148-c10c-47a3-82af-0395e32ddf87","title":"Definitely Maybe","score":100,"country":"JP","artist-credit":[{"name":"Oasis"}]}
                ]}
                """
            }
        } else if url.lastPathComponent == "698d1229-0724-36c1-9ef0-0705ac4d98c4" {
            let images = ["Front"] + Array(repeating: "Booklet", count: 5) + ["Back"]
            let imageJSON = images.enumerated().map { index, type in
                "{\"id\":\"\(index)\",\"image\":\"https://example.com/\(index).jpg\",\"types\":[\"\(type)\"]}"
            }.joined(separator: ",")
            json = "{\"images\":[\(imageJSON)]}"
        } else {
            json = """
            {"images":[{"id":"front","image":"https://example.com/front.jpg","types":["Front"]}]}
            """
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class DeluxeStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let json: String
        if url.host == "musicbrainz.org" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value ?? ""
            if query.contains("Super Deluxe") {
                json = """
                {"releases":[{"id":"deluxe-booklet","title":"Morning View (Super Deluxe)","score":100,"country":"US","artist-credit":[{"name":"Incubus"}]}]}
                """
            } else if query.contains("Deluxe Edition") {
                json = """
                {"releases":[{"id":"deluxe","title":"Morning View (Deluxe Edition)","score":100,"country":"US","artist-credit":[{"name":"Incubus"}]}]}
                """
            } else {
                json = """
                {"releases":[
                  {"id":"original","title":"Morning View","score":95,"country":"US","artist-credit":[{"name":"Incubus"}]},
                  {"id":"foreign","title":"Morning View","score":100,"country":"JP","artist-credit":[{"name":"Incubus"}]},
                  {"id":"different","title":"Morning View Live","score":100,"country":"US","artist-credit":[{"name":"Incubus"}]}
                ]}
                """
            }
        } else if url.lastPathComponent == "deluxe" {
            json = """
            {"images":[{"id":"front","image":"https://example.com/front.jpg","types":["Front"],"front":true}]}
            """
        } else {
            json = """
            {"images":[
              {"id":"front","image":"https://example.com/front.jpg","types":["Front"],"front":true},
              {"id":"booklet","image":"https://example.com/booklet.jpg","types":["Booklet"]}
            ]}
            """
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ReleaseStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let json: String
        if request.url?.lastPathComponent == "mapped" {
            json = """
            {
              "id": "mapped", "title": "Album", "country": "JP",
              "release-events": [
                {"area": {"iso-3166-1-codes": ["JP"]}},
                {"area": {"iso-3166-1-codes": ["US"]}}
              ]
            }
            """
        } else {
            json = "{\"releases\":[]}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
