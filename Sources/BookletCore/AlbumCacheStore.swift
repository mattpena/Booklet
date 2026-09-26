import CryptoKit
import Foundation

public actor AlbumCacheStore {
    public static let shared = AlbumCacheStore()
    public static let retentionInterval: TimeInterval = 60 * 24 * 60 * 60

    private let rootURL: URL
    private let session: URLSession
    private let fileManager = FileManager.default
    private var pendingImages: [String: Task<Data?, Never>] = [:]

    public init(rootURL: URL? = nil, session: URLSession = .shared) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Booklet/AlbumCache", isDirectory: true)
        self.session = session
    }

    public func markListened(albumKey: String, at date: Date = Date()) {
        let folder = albumFolder(albumKey)
        removeIfExpired(folder, asOf: date)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(String(date.timeIntervalSince1970).utf8)
                .write(to: folder.appendingPathComponent("last-listened"), options: .atomic)
        } catch {
            return
        }
    }

    public func pruneExpired(asOf date: Date = Date()) {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            removeIfExpired(folder, asOf: date)
        }
    }

    public func loadResolution(albumKey: String, countryCode: String) -> ResolveResult? {
        let folder = albumFolder(albumKey)
        guard !removeIfExpired(folder, asOf: Date()),
              let data = try? Data(contentsOf: resolutionURL(folder, countryCode: countryCode)) else { return nil }
        return try? JSONDecoder().decode(ResolveResult.self, from: data)
    }

    public func saveResolution(_ result: ResolveResult, albumKey: String, countryCode: String) {
        let folder = albumFolder(albumKey)
        removeIfExpired(folder, asOf: Date())
        guard let data = try? JSONEncoder().encode(result) else { return }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: resolutionURL(folder, countryCode: countryCode), options: .atomic)
        } catch {
            return
        }
    }

    public func removeResolution(albumKey: String, countryCode: String) {
        try? fileManager.removeItem(at: resolutionURL(albumFolder(albumKey), countryCode: countryCode))
    }

    public func imageData(albumKey: String, url: URL) async -> Data? {
        let folder = albumFolder(albumKey)
        removeIfExpired(folder, asOf: Date())
        let imageURL = folder.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(digest(url.absoluteString))
        if let data = try? Data(contentsOf: imageURL) { return data }

        let requestKey = imageURL.path
        if let pending = pendingImages[requestKey] { return await pending.value }
        let session = self.session
        let task = Task<Data?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        pendingImages[requestKey] = task
        let data = await task.value
        pendingImages[requestKey] = nil
        guard let data, !removeIfExpired(folder, asOf: Date()) else { return data }
        do {
            try fileManager.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: imageURL, options: .atomic)
        } catch {
            return data
        }
        return data
    }

    private func albumFolder(_ albumKey: String) -> URL {
        rootURL.appendingPathComponent(digest(albumKey), isDirectory: true)
    }

    private func resolutionURL(_ folder: URL, countryCode: String) -> URL {
        folder.appendingPathComponent("release-v2-\(digest(countryCode.uppercased())).json")
    }

    @discardableResult
    private func removeIfExpired(_ folder: URL, asOf date: Date) -> Bool {
        guard fileManager.fileExists(atPath: folder.path) else { return false }
        let marker = folder.appendingPathComponent("last-listened")
        let lastListened = (try? String(contentsOf: marker, encoding: .utf8))
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
        let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate)
        guard let referenceDate = lastListened ?? created,
              date.timeIntervalSince(referenceDate) > Self.retentionInterval else { return false }
        try? fileManager.removeItem(at: folder)
        return true
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
