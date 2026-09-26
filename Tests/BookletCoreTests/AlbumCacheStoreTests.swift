import CryptoKit
import Foundation
import Testing
@testable import BookletCore

@Test("Release matches persist by album and country")
func releaseCachePersists() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AlbumCacheStore(rootURL: root)
    let result = ResolveResult.found(ReleaseMatch(
        release: MusicBrainzRelease(
            id: "us-release", title: "Album", score: 100, status: "Official",
            date: "2000", country: "US", barcode: nil, trackCount: 10,
            artistCredit: "Artist", releaseGroupID: nil, hasCoverArt: true
        ),
        pages: [BookletPage(
            id: "front", imageURL: URL(string: "https://example.com/full.jpg")!,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")!,
            previewURL: URL(string: "https://example.com/preview.jpg")!,
            types: ["Front"], comment: "", isFront: true, isBack: false
        )],
        hasBooklet: false, confidence: 90, source: .musicBrainzSearch
    ))
    await store.saveResolution(result, albumKey: "album-one", countryCode: "US")
    let reopened = AlbumCacheStore(rootURL: root)
    #expect(await reopened.loadResolution(albumKey: "album-one", countryCode: "US") == result)
    #expect(await reopened.loadResolution(albumKey: "album-one", countryCode: "JP") == nil)
    #expect(await reopened.loadResolution(albumKey: "another-album", countryCode: "US") == nil)
    await reopened.removeResolution(albumKey: "album-one", countryCode: "US")
    #expect(await reopened.loadResolution(albumKey: "album-one", countryCode: "US") == nil)
}

@Test("Old cached misses do not hide newly available booklets")
func oldResolutionCacheIsIgnored() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let albumDigest = SHA256.hash(data: Data("oasis-album".utf8))
        .map { String(format: "%02x", $0) }.joined()
    let countryDigest = SHA256.hash(data: Data("US".utf8))
        .map { String(format: "%02x", $0) }.joined()
    let folder = root.appendingPathComponent(albumDigest)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONEncoder().encode(ResolveResult.notFound(.noRelease))
        .write(to: folder.appendingPathComponent("release-\(countryDigest).json"))

    let store = AlbumCacheStore(rootURL: root)
    #expect(await store.loadResolution(albumKey: "oasis-album", countryCode: "US") == nil)
}

@Test("Albums expire 60 days after the last listen, not cache access")
func cacheRetentionFollowsListening() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AlbumCacheStore(rootURL: root)
    let start = Date()
    await store.markListened(albumKey: "listened", at: start)
    await store.saveResolution(.notFound(.noArtwork), albumKey: "listened", countryCode: "US")
    await store.pruneExpired(asOf: start.addingTimeInterval(59 * 86_400))
    #expect(await store.loadResolution(albumKey: "listened", countryCode: "US") != nil)
    await store.markListened(albumKey: "listened", at: start.addingTimeInterval(59 * 86_400))
    await store.pruneExpired(asOf: start.addingTimeInterval(118 * 86_400))
    #expect(await store.loadResolution(albumKey: "listened", countryCode: "US") != nil)
    await store.pruneExpired(asOf: start.addingTimeInterval(120 * 86_400))
    #expect(await store.loadResolution(albumKey: "listened", countryCode: "US") == nil)
}

@Test("Artwork bytes are reused from disk after relaunch")
func artworkCachePersists() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CacheImageURLProtocol.self]
    let session = URLSession(configuration: configuration)
    CacheImageURLProtocol.counter.reset()
    let url = URL(string: "https://example.com/cover.jpg")!
    let store = AlbumCacheStore(rootURL: root, session: session)
    #expect(await store.imageData(albumKey: "album", url: url) == Data([1, 2, 3]))
    let reopened = AlbumCacheStore(rootURL: root, session: session)
    #expect(await reopened.imageData(albumKey: "album", url: url) == Data([1, 2, 3]))
    #expect(CacheImageURLProtocol.counter.value == 1)
    await reopened.markListened(albumKey: "album", at: Date().addingTimeInterval(-61 * 86_400))
    #expect(await reopened.imageData(albumKey: "album", url: url) == Data([1, 2, 3]))
    #expect(CacheImageURLProtocol.counter.value == 2)
}

private final class CacheRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }
}

private final class CacheImageURLProtocol: URLProtocol {
    static let counter = CacheRequestCounter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.counter.increment()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
