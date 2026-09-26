import Foundation

public struct MusicBrainzClient: Sendable {
    private let session: URLSession
    private let userAgent: String

    public init(
        session: URLSession = .shared,
        contact: String = "https://github.com/booklet-app"
    ) {
        self.session = session
        self.userAgent = "Booklet/0.1 (\(contact))"
    }

    public func searchReleases(for album: AlbumIdentity, countryCode: String) async throws -> [MusicBrainzRelease] {
        let data = try await request(Self.searchURL(for: album, countryCode: countryCode))
        return try JSONDecoder().decode(SearchResponse.self, from: data).releases.map(\.model)
    }

    static func searchURL(for album: AlbumIdentity, countryCode: String) -> URL {
        let artist = album.artists.first ?? ""
        let query = [
            "release:\"\(TextNormalization.escapeLucene(album.title))\"",
            "artist:\"\(TextNormalization.escapeLucene(artist))\"",
            "status:official",
            "country:\(countryCode.uppercased())",
        ].joined(separator: " AND ")

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        return components.url!
    }

    public func lookupRelease(id: String) async throws -> MusicBrainzRelease? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "inc", value: "artist-credits+release-groups"),
        ]

        do {
            let data = try await request(components.url!)
            return try JSONDecoder().decode(ReleaseDTO.self, from: data).model
        } catch APIError.notFound {
            return nil
        }
    }

    public func songDetails(for track: LocalTrack) async throws -> SongDetails? {
        guard !track.title.isEmpty, !track.artist.isEmpty else { return nil }
        var search = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        search.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(TextNormalization.escapeLucene(track.title))\" AND artist:\"\(TextNormalization.escapeLucene(track.artist))\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        let results = try JSONDecoder().decode(RecordingSearchResponse.self, from: await request(search.url!))
        guard let recording = Self.bestRecording(in: results.recordings, for: track) else { return nil }

        var lookup = URLComponents(string: "https://musicbrainz.org/ws/2/recording/\(recording.id)")!
        lookup.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "inc", value: "artist-rels+place-rels+area-rels+work-rels+work-level-rels"),
        ]
        let details = try JSONDecoder().decode(RecordingDetailsDTO.self, from: await request(lookup.url!))
        return details.model
    }

    static func bestRecording(in recordings: [RecordingSearchDTO], for track: LocalTrack) -> RecordingSearchDTO? {
        let title = TextNormalization.normalize(track.title)
        let artist = TextNormalization.normalize(track.artist)
        let albumTitles = Set([
            TextNormalization.normalize(track.album),
            TextNormalization.normalize(TextNormalization.originalEditionTitle(from: track.album) ?? track.album),
        ])
        return recordings
            .filter {
                let albumMatches = $0.releases?.contains { albumTitles.contains(TextNormalization.normalize($0.title)) } == true
                let durationMatches = $0.length.map { track.durationMilliseconds > 0 && abs($0 - track.durationMilliseconds) < 3_000 } == true
                return TextNormalization.normalize($0.title) == title &&
                    TextNormalization.normalize($0.artistCreditName) == artist &&
                    ($0.score ?? 0) >= 80 &&
                    (albumMatches || durationMatches)
            }
            .max { left, right in
                matchScore(left, albumTitles: albumTitles, duration: track.durationMilliseconds) <
                    matchScore(right, albumTitles: albumTitles, duration: track.durationMilliseconds)
            }
    }

    private static func matchScore(_ recording: RecordingSearchDTO, albumTitles: Set<String>, duration: Int) -> Int {
        var score = recording.score ?? 0
        if recording.releases?.contains(where: { albumTitles.contains(TextNormalization.normalize($0.title)) }) == true {
            score += 25
        }
        if let length = recording.length, duration > 0 {
            let difference = abs(length - duration)
            if difference < 3_000 { score += 15 }
            else if difference > 20_000 { score -= 30 }
        }
        return score
    }

    private func request(_ url: URL) async throws -> Data {
        try await MusicBrainzRequestGate.shared.wait()
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 404 { throw APIError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return data
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case notFound
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The archive returned an invalid response."
        case .notFound: "The requested archive entry was not found."
        case .http(let status): "The archive request failed with status \(status)."
        }
    }
}

private struct SearchResponse: Decodable {
    let releases: [ReleaseDTO]
}

private struct ReleaseDTO: Decodable {
    let id: String
    let title: String
    let score: Int?
    let status: String?
    let date: String?
    let country: String?
    let releaseEvents: [ReleaseEventDTO]?
    let barcode: String?
    let trackCount: Int?
    let artistCredit: [ArtistCreditDTO]?
    let releaseGroup: ReleaseGroupDTO?
    let coverArtArchive: CoverArtArchiveDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, score, status, date, country, barcode
        case releaseEvents = "release-events"
        case trackCount = "track-count"
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
        case coverArtArchive = "cover-art-archive"
    }

    var model: MusicBrainzRelease {
        MusicBrainzRelease(
            id: id,
            title: title,
            score: score ?? 0,
            status: status,
            date: date,
            country: country,
            releaseCountries: releaseEvents?.flatMap { $0.area?.countryCodes ?? [] } ?? [],
            barcode: barcode,
            trackCount: trackCount,
            artistCredit: (artistCredit ?? []).map { "\($0.name ?? $0.artist?.name ?? "")\($0.joinPhrase ?? "")" }.joined(),
            releaseGroupID: releaseGroup?.id,
            hasCoverArt: coverArtArchive?.artwork ?? false
        )
    }
}

private struct ReleaseEventDTO: Decodable {
    let area: ReleaseAreaDTO?
}

private struct ReleaseAreaDTO: Decodable {
    let countryCodes: [String]?

    enum CodingKeys: String, CodingKey {
        case countryCodes = "iso-3166-1-codes"
    }
}

struct ArtistCreditDTO: Decodable {
    let name: String?
    let artist: ArtistDTO?
    let joinPhrase: String?

    enum CodingKeys: String, CodingKey {
        case name, artist
        case joinPhrase = "joinphrase"
    }
}

struct ArtistDTO: Decodable { let name: String? }
private struct ReleaseGroupDTO: Decodable { let id: String? }
private struct CoverArtArchiveDTO: Decodable { let artwork: Bool? }

private actor MusicBrainzRequestGate {
    static let shared = MusicBrainzRequestGate()
    private var nextAllowed: ContinuousClock.Instant?

    func wait() async throws {
        let now = ContinuousClock.now
        let slot = max(now, nextAllowed ?? now)
        nextAllowed = slot.advanced(by: .seconds(1))
        if slot > now { try await Task.sleep(until: slot, clock: .continuous) }
    }
}

private struct RecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzClient.RecordingSearchDTO]
}

extension MusicBrainzClient {
    struct RecordingSearchDTO: Decodable {
        let id: String
        let title: String
        let score: Int?
        let length: Int?
        let artistCredit: [ArtistCreditDTO]?
        let releases: [RecordingReleaseDTO]?

        enum CodingKeys: String, CodingKey {
            case id, title, score, length, releases
            case artistCredit = "artist-credit"
        }

        var artistCreditName: String {
            (artistCredit ?? []).map { "\($0.name ?? $0.artist?.name ?? "")\($0.joinPhrase ?? "")" }.joined()
        }
    }
}

struct RecordingReleaseDTO: Decodable {
    let title: String
}

private struct RecordingDetailsDTO: Decodable {
    let id: String
    let relations: [RelationDTO]?

    var model: SongDetails {
        let recordingRelations = relations ?? []
        let workRelations = recordingRelations.filter { $0.work != nil }
            .flatMap { $0.work?.relations ?? [] }
        let writerTypes: Set<String> = ["writer", "composer", "lyricist"]
        let performerTypes: Set<String> = ["vocal", "instrument", "performer", "main performer", "guest performer"]
        let writers = Self.names(in: workRelations + recordingRelations, types: writerTypes)
        let performers = Self.names(in: recordingRelations, types: performerTypes)
        let places = Self.locations(in: recordingRelations)
        return SongDetails(
            writers: writers,
            performers: performers,
            recordedAt: places,
            sourceURL: URL(string: "https://musicbrainz.org/recording/\(id)")!
        )
    }

    private static func names(in relations: [RelationDTO], types: Set<String>) -> [String] {
        Array(Set(relations.compactMap { relation in
            guard types.contains(relation.type.lowercased()) else { return nil }
            return relation.artist?.name
        })).sorted()
    }

    private static func locations(in relations: [RelationDTO]) -> [String] {
        Array(Set(relations.compactMap { relation in
            switch relation.type.lowercased() {
            case "recorded at": return relation.place?.name
            case "recorded in": return relation.area?.name
            default: return nil
            }
        })).sorted()
    }
}

private struct RelationDTO: Decodable {
    let type: String
    let artist: RelatedNameDTO?
    let place: RelatedNameDTO?
    let area: RelatedNameDTO?
    let work: RelatedWorkDTO?
}

private struct RelatedNameDTO: Decodable {
    let name: String
}

private struct RelatedWorkDTO: Decodable {
    let relations: [RelationDTO]?
}
