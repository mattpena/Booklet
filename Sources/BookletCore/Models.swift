import Foundation

public enum SpotifyPlaybackState: String, Sendable {
    case playing
    case paused
    case stopped
}

public struct LocalTrack: Equatable, Sendable, Identifiable {
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let spotifyURL: String
    public let artworkURL: URL?
    public let durationMilliseconds: Int
    public let positionSeconds: Double
    public let playbackState: SpotifyPlaybackState

    public init(
        title: String,
        artist: String,
        album: String,
        albumArtist: String,
        spotifyURL: String,
        artworkURL: URL?,
        durationMilliseconds: Int,
        positionSeconds: Double,
        playbackState: SpotifyPlaybackState
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.spotifyURL = spotifyURL
        self.artworkURL = artworkURL
        self.durationMilliseconds = durationMilliseconds
        self.positionSeconds = positionSeconds
        self.playbackState = playbackState
    }

    public var id: String {
        spotifyURL.isEmpty ? "\(artist)|\(album)|\(title)" : spotifyURL
    }

    public var albumIdentity: AlbumIdentity {
        let creditedArtist = albumArtist.isEmpty ? artist : albumArtist
        let localKey: String
        if let artworkURL, artworkURL.pathComponents.count > 1 {
            localKey = TextNormalization.normalize("\(album)|\(artworkURL.lastPathComponent)")
        } else {
            localKey = TextNormalization.normalize("\(creditedArtist)|\(album)")
        }
        return AlbumIdentity(
            localKey: localKey,
            title: album,
            artists: [creditedArtist],
            coverURL: artworkURL
        )
    }
}

public enum SpotifyReadResult: Equatable, Sendable {
    case notRunning
    case noTrack
    case track(LocalTrack)
}

public struct AlbumIdentity: Equatable, Sendable {
    public let localKey: String
    public let title: String
    public let artists: [String]
    public let releaseDate: String?
    public let totalTracks: Int?
    public let coverURL: URL?

    public init(
        localKey: String,
        title: String,
        artists: [String],
        releaseDate: String? = nil,
        totalTracks: Int? = nil,
        coverURL: URL? = nil
    ) {
        self.localKey = localKey
        self.title = title
        self.artists = artists
        self.releaseDate = releaseDate
        self.totalTracks = totalTracks
        self.coverURL = coverURL
    }
}

public struct SongDetails: Equatable, Sendable {
    public let writers: [String]
    public let performers: [String]
    public let recordedAt: [String]
    public let sourceURL: URL

    public init(writers: [String], performers: [String], recordedAt: [String], sourceURL: URL) {
        self.writers = writers
        self.performers = performers
        self.recordedAt = recordedAt
        self.sourceURL = sourceURL
    }

    public var hasCredits: Bool {
        !writers.isEmpty || !performers.isEmpty || !recordedAt.isEmpty
    }
}

public struct MusicBrainzRelease: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let score: Int
    public let status: String?
    public let date: String?
    public let country: String?
    public let releaseCountries: [String]
    public let barcode: String?
    public let trackCount: Int?
    public let artistCredit: String
    public let releaseGroupID: String?
    public let hasCoverArt: Bool

    public init(
        id: String,
        title: String,
        score: Int,
        status: String?,
        date: String?,
        country: String?,
        releaseCountries: [String] = [],
        barcode: String?,
        trackCount: Int?,
        artistCredit: String,
        releaseGroupID: String?,
        hasCoverArt: Bool
    ) {
        self.id = id
        self.title = title
        self.score = score
        self.status = status
        self.date = date
        self.country = country
        self.releaseCountries = releaseCountries
        self.barcode = barcode
        self.trackCount = trackCount
        self.artistCredit = artistCredit
        self.releaseGroupID = releaseGroupID
        self.hasCoverArt = hasCoverArt
    }

    public func isReleased(in countryCode: String) -> Bool {
        if !releaseCountries.isEmpty {
            return releaseCountries.contains { $0.caseInsensitiveCompare(countryCode) == .orderedSame }
        }
        return country?.caseInsensitiveCompare(countryCode) == .orderedSame
    }
}

public struct BookletPage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let imageURL: URL
    public let thumbnailURL: URL
    public let previewURL: URL
    public let types: [String]
    public let comment: String
    public let isFront: Bool
    public let isBack: Bool

    public init(
        id: String,
        imageURL: URL,
        thumbnailURL: URL,
        previewURL: URL,
        types: [String],
        comment: String,
        isFront: Bool,
        isBack: Bool
    ) {
        self.id = id
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.previewURL = previewURL
        self.types = types
        self.comment = comment
        self.isFront = isFront
        self.isBack = isBack
    }

    public var displayName: String {
        types.isEmpty ? "Artwork" : types.joined(separator: " · ")
    }

    public var isBooklet: Bool {
        types.contains { $0.caseInsensitiveCompare("Booklet") == .orderedSame }
    }
}

public struct ReleaseMatch: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case localMap
        case musicBrainzSearch
        case originalEditionFallback
    }

    public let release: MusicBrainzRelease
    public let pages: [BookletPage]
    public let hasBooklet: Bool
    public let confidence: Int
    public let source: Source
}

public enum ResolveResult: Codable, Equatable, Sendable {
    public enum NotFoundReason: Codable, Equatable, Sendable {
        case noRelease
        case noArtwork
    }

    case found(ReleaseMatch)
    case coverOnly(ReleaseMatch)
    case notFound(NotFoundReason)

    public var match: ReleaseMatch? {
        switch self {
        case .found(let match), .coverOnly(let match): match
        case .notFound: nil
        }
    }
}
