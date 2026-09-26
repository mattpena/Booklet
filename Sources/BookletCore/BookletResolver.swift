import Foundation

public protocol MappingRepository: Sendable {
    func releaseID(forLocalAlbumKey key: String) async -> String?
}

public struct LocalMappingRepository: MappingRepository {
    private let mappings: [String: String]

    public init(mappings: [String: String] = [:]) {
        self.mappings = mappings
    }

    public func releaseID(forLocalAlbumKey key: String) async -> String? {
        mappings[key]
    }
}

public struct BookletResolver: Sendable {
    private let musicBrainz: MusicBrainzClient
    private let coverArt: CoverArtClient
    private let mappings: any MappingRepository

    public init(
        musicBrainz: MusicBrainzClient = MusicBrainzClient(),
        coverArt: CoverArtClient = CoverArtClient(),
        mappings: any MappingRepository = LocalMappingRepository()
    ) {
        self.musicBrainz = musicBrainz
        self.coverArt = coverArt
        self.mappings = mappings
    }

    public func resolve(_ album: AlbumIdentity, countryCode: String) async throws -> ResolveResult {
        if let mappedID = await mappings.releaseID(forLocalAlbumKey: album.localKey),
           let release = try await musicBrainz.lookupRelease(id: mappedID),
           release.isReleased(in: countryCode) {
            let pages = try await coverArt.artwork(for: mappedID)
            if !pages.isEmpty {
                let match = makeMatch(album: album, release: release, pages: pages, source: .localMap)
                return match.hasBooklet ? .found(match) : .coverOnly(match)
            }
        }

        let exact = try await searchMatches(for: album, countryCode: countryCode, source: .musicBrainzSearch)
        if case .found = exact { return exact }

        guard let originalTitle = TextNormalization.originalEditionTitle(from: album.title) else { return exact }
        let originalAlbum = AlbumIdentity(
            localKey: album.localKey,
            title: originalTitle,
            artists: album.artists,
            releaseDate: album.releaseDate,
            totalTracks: album.totalTracks,
            coverURL: album.coverURL
        )

        let fallback: ResolveResult
        do {
            fallback = try await searchMatches(
                for: originalAlbum,
                countryCode: countryCode,
                source: .originalEditionFallback,
                requireExactTitle: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return exact
        }
        if case .found = fallback { return fallback }
        if case .coverOnly = fallback, exact.match == nil { return fallback }
        return exact
    }

    private func searchMatches(
        for album: AlbumIdentity,
        countryCode: String,
        source: ReleaseMatch.Source,
        requireExactTitle: Bool = false
    ) async throws -> ResolveResult {
        let releases = try await musicBrainz.searchReleases(for: album, countryCode: countryCode)
        guard !releases.isEmpty else { return .notFound(.noRelease) }

        let candidates = releases
            .filter { release in
                guard release.isReleased(in: countryCode) else { return false }
                if requireExactTitle {
                    return TextNormalization.normalize(release.title) == TextNormalization.normalize(album.title)
                }
                return release.hasCoverArt || release.score >= 85
            }
            .sorted { metadataScore(album: album, release: $0) > metadataScore(album: album, release: $1) }
            .prefix(6)

        let matches = await withTaskGroup(of: ReleaseMatch?.self, returning: [ReleaseMatch].self) { group in
            for release in candidates {
                group.addTask {
                    guard let pages = try? await coverArt.artwork(for: release.id), !pages.isEmpty else { return nil }
                    return makeMatch(album: album, release: release, pages: pages, source: source)
                }
            }

            var resolved: [ReleaseMatch] = []
            for await match in group {
                if let match { resolved.append(match) }
            }
            return resolved
        }

        guard let best = matches.max(by: { $0.confidence < $1.confidence }) else {
            return .notFound(.noArtwork)
        }
        return best.hasBooklet ? .found(best) : .coverOnly(best)
    }

    public func metadataScore(album: AlbumIdentity, release: MusicBrainzRelease) -> Int {
        var score = release.score
        if TextNormalization.normalize(album.title) == TextNormalization.normalize(release.title) { score += 12 }

        let albumArtists = TextNormalization.normalize(album.artists.joined(separator: " "))
        let releaseArtists = TextNormalization.normalize(release.artistCredit)
        if !albumArtists.isEmpty,
           !releaseArtists.isEmpty,
           (albumArtists.contains(releaseArtists) || releaseArtists.contains(albumArtists)) {
            score += 10
        }

        if let albumYear = TextNormalization.year(from: album.releaseDate),
           let releaseYear = TextNormalization.year(from: release.date) {
            score += max(0, 8 - abs(albumYear - releaseYear) * 2)
        }
        if let totalTracks = album.totalTracks, totalTracks == release.trackCount { score += 6 }
        return score
    }

    private func makeMatch(
        album: AlbumIdentity,
        release: MusicBrainzRelease,
        pages: [BookletPage],
        source: ReleaseMatch.Source
    ) -> ReleaseMatch {
        let bookletCount = pages.filter(\.isBooklet).count
        return ReleaseMatch(
            release: release,
            pages: pages,
            hasBooklet: bookletCount > 0,
            confidence: metadataScore(album: album, release: release) + bookletCount * 30 + min(pages.count, 12) * 2,
            source: source
        )
    }
}
