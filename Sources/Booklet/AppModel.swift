import AppKit
import BookletCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum CountrySource {
        case location
        case macRegion
        case chosen
    }

    enum ListenerState: Equatable {
        case checking
        case spotifyNotRunning
        case nothingPlaying
        case ready
        case permissionDenied
        case failed(String)
    }

    @Published var listenerState: ListenerState = .checking
    @Published var track: LocalTrack?
    @Published var resolution: ResolveResult?
    @Published var isResolving = false
    @Published var archiveError: String?
    @Published var albumSummary: AlbumSummary?
    @Published var isLoadingSummary = false
    @Published var songDetails: SongDetails?
    @Published var isLoadingSongDetails = false
    @Published var trackStory: TrackStory?
    @Published var isLoadingTrackStory = false
    @Published var newsArticles: [NewsArticle] = []
    @Published var isLoadingNews = false
    @Published var newsUnavailable = false
    @Published var isRefreshingManually = false
    @Published var lastUpdated = Date()
    @Published var palette = AlbumPalette.standard
    @Published var controlError: String?
    @Published var releaseCountryCode: String
    @Published var countryOverride: String?
    @Published var countrySource: CountrySource
    @Published var countryReady: Bool

    private let spotifyReader = SpotifyReader()
    private let resolver = BookletResolver()
    private let wikipedia = WikipediaClient()
    private let musicBrainz = MusicBrainzClient()
    private let newsClient = GoogleNewsClient()
    private var pollingTimer: Timer?
    private var resolvedAlbumKey: String?
    private var lastMarkedAlbumKey: String?
    private var lastMarkedAt: Date?
    private var lastPrunedAt: Date?
    private var paletteCache: [String: AlbumPalette] = [:]
    private var paletteAlbumKey: String?
    private var paletteTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var songTask: Task<Void, Never>?
    private var trackStoryTask: Task<Void, Never>?
    private var newsTask: Task<Void, Never>?
    private var summaryAlbumKey: String?
    private var songKey: String?
    private var trackStoryKey: String?
    private var newsAlbumKey: String?
    private var summaryCache: [String: AlbumSummary] = [:]
    private var searchedSummaries: Set<String> = []
    private var songCache: [String: SongDetails] = [:]
    private var searchedSongs: Set<String> = []
    private var storyCache: [String: TrackStory] = [:]
    private var searchedStories: Set<String> = []
    private var newsCache: [String: (date: Date, articles: [NewsArticle])] = [:]
    private var refreshInFlight = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    @Published private var pendingControls = 0
    private var countryLocator: CountryLocator?
    private var countryTimeoutTask: Task<Void, Never>?

    init() {
        let override = UserDefaults.standard.string(forKey: "releaseCountryOverride")
        countryOverride = override
        releaseCountryCode = override ?? Locale.autoupdatingCurrent.region?.identifier ?? "US"
        countrySource = override == nil ? .macRegion : .chosen
        countryReady = override != nil
    }

    var releaseCountryName: String {
        Locale.current.localizedString(forRegionCode: releaseCountryCode) ?? releaseCountryCode
    }

    var controlsAreBusy: Bool { pendingControls >= 3 }

    func start() {
        guard pollingTimer == nil else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        AppDiagnostics.record("app start build=\(build)")
        let locator = CountryLocator()
        locator.onCountry = { [weak self] code in
            guard let self, self.countryOverride == nil else { return }
            if let code {
                self.countrySource = .location
                self.setCountry(code)
            }
            self.finishCountryLookup()
        }
        countryLocator = locator
        if countryOverride == nil { startCountryLookup() }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            AppDiagnostics.record("spotify poll tick")
            guard let self else {
                AppDiagnostics.record("spotify poll model_unavailable")
                return
            }
            Task { @MainActor in await self.refresh() }
        }
        Task { @MainActor in
            await AlbumCacheStore.shared.pruneExpired()
            lastPrunedAt = Date()
            await refresh()
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshInFlight, (force || pendingControls == 0) else {
            AppDiagnostics.record("spotify read skipped reason=\(refreshInFlight ? "read_in_flight" : "control_in_flight")")
            return
        }
        refreshInFlight = true
        let started = Date()
        AppDiagnostics.record("spotify read start")
        defer {
            AppDiagnostics.record("spotify read finish elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            refreshInFlight = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }

        if Date().timeIntervalSince(lastPrunedAt ?? Date()) >= 86_400 {
            lastPrunedAt = Date()
            Task { await AlbumCacheStore.shared.pruneExpired() }
        }

        do {
            switch try await spotifyReader.read() {
            case .notRunning:
                AppDiagnostics.record("spotify state not_running")
                listenerState = .spotifyNotRunning
                track = nil
                clearAlbum()
            case .noTrack:
                AppDiagnostics.record("spotify state no_track")
                listenerState = .nothingPlaying
                track = nil
                clearAlbum()
            case .track(let currentTrack):
                AppDiagnostics.record("spotify state track playback=\(currentTrack.playbackState.rawValue)")
                listenerState = .ready
                track = currentTrack
                lastUpdated = Date()
                if currentTrack.playbackState == .playing {
                    let albumKey = currentTrack.albumIdentity.localKey
                    if lastMarkedAlbumKey != albumKey || Date().timeIntervalSince(lastMarkedAt ?? .distantPast) >= 86_400 {
                        lastMarkedAlbumKey = albumKey
                        lastMarkedAt = Date()
                        Task { await AlbumCacheStore.shared.markListened(albumKey: albumKey) }
                    }
                }
                updatePalette(for: currentTrack.albumIdentity)
                resolveIfNeeded(currentTrack.albumIdentity)
                loadSummaryIfNeeded(for: currentTrack.albumIdentity)
                loadSongDetailsIfNeeded(for: currentTrack)
            }
        } catch SpotifyReaderError.automationDenied {
            AppDiagnostics.record("spotify read error automation_denied")
            listenerState = .permissionDenied
            track = nil
            clearAlbum()
        } catch {
            AppDiagnostics.record("spotify read error type=\(String(describing: type(of: error)))")
            listenerState = .failed(error.localizedDescription)
            track = nil
            clearAlbum()
        }
    }

    func refreshNowPlaying() async {
        guard !isRefreshingManually else { return }
        isRefreshingManually = true
        let reloadStory = trackStoryKey != nil
        let reloadNews = newsAlbumKey != nil
        AppDiagnostics.record("manual refresh start")
        defer {
            isRefreshingManually = false
            AppDiagnostics.record("manual refresh finish")
        }

        while refreshInFlight {
            AppDiagnostics.record("manual refresh waiting_for_read")
            await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
        }

        if let track {
            let albumKey = track.albumIdentity.localKey
            resolutionTask?.cancel()
            summaryTask?.cancel()
            songTask?.cancel()
            trackStoryTask?.cancel()
            newsTask?.cancel()
            paletteTask?.cancel()
            await AlbumCacheStore.shared.removeResolution(albumKey: albumKey, countryCode: releaseCountryCode)
            summaryCache.removeValue(forKey: albumKey)
            searchedSummaries.remove(albumKey)
            songCache.removeValue(forKey: track.id)
            searchedSongs.remove(track.id)
            storyCache.removeValue(forKey: track.id)
            searchedStories.remove(track.id)
            newsCache.removeValue(forKey: albumKey)
            paletteCache.removeValue(forKey: albumKey)
            resolvedAlbumKey = nil
            summaryAlbumKey = nil
            songKey = nil
            trackStoryKey = nil
            newsAlbumKey = nil
            paletteAlbumKey = nil
            trackStory = nil
            newsArticles = []
            isLoadingTrackStory = false
            isLoadingNews = false
            newsUnavailable = false
        }

        await refresh(force: true)
        if let track {
            if reloadStory { loadTrackStoryIfNeeded(for: track) }
            if reloadNews { loadNewsIfNeeded(for: track.albumIdentity) }
        }
    }

    func control(_ command: SpotifyCommand) async {
        guard pendingControls < 3 else {
            AppDiagnostics.record("spotify control dropped queue_full")
            return
        }
        pendingControls += 1
        let started = Date()
        AppDiagnostics.record("spotify control start command=\(String(describing: command)) pending=\(pendingControls)")
        do {
            try await spotifyReader.control(command)
            controlError = nil
            AppDiagnostics.record("spotify control success command=\(String(describing: command)) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        } catch {
            controlError = error.localizedDescription
            AppDiagnostics.record("spotify control error command=\(String(describing: command)) type=\(String(describing: type(of: error))) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        }
        pendingControls -= 1
        if pendingControls == 0 { await refresh() }
    }

    func useCurrentLocation() {
        countryOverride = nil
        countrySource = .macRegion
        UserDefaults.standard.removeObject(forKey: "releaseCountryOverride")
        if let region = Locale.autoupdatingCurrent.region?.identifier {
            setCountry(region)
        }
        startCountryLookup()
    }

    func chooseCountry(_ code: String) {
        countryOverride = code
        countrySource = .chosen
        UserDefaults.standard.set(code, forKey: "releaseCountryOverride")
        setCountry(code)
        finishCountryLookup()
    }

    func openSpotify() {
        guard let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            NSWorkspace.shared.open(URL(string: "https://spotify.com/download")!)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: spotifyURL, configuration: configuration)
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func clearAlbum() {
        resolvedAlbumKey = nil
        resolution = nil
        archiveError = nil
        isResolving = false
        paletteAlbumKey = nil
        paletteTask?.cancel()
        resolutionTask?.cancel()
        summaryTask?.cancel()
        songTask?.cancel()
        trackStoryTask?.cancel()
        newsTask?.cancel()
        summaryAlbumKey = nil
        songKey = nil
        trackStoryKey = nil
        newsAlbumKey = nil
        albumSummary = nil
        songDetails = nil
        trackStory = nil
        newsArticles = []
        isLoadingSummary = false
        isLoadingSongDetails = false
        isLoadingTrackStory = false
        isLoadingNews = false
        newsUnavailable = false
        palette = .standard
        controlError = nil
    }

    private func setCountry(_ code: String) {
        let normalized = code.uppercased()
        guard normalized.count == 2, normalized != releaseCountryCode else { return }
        releaseCountryCode = normalized
        resolvedAlbumKey = nil
        resolutionTask?.cancel()
        resolution = nil
        archiveError = nil
        isResolving = false
        if let track { resolveIfNeeded(track.albumIdentity) }
    }

    private func startCountryLookup() {
        countryReady = false
        resolvedAlbumKey = nil
        resolutionTask?.cancel()
        resolution = nil
        archiveError = nil
        isResolving = false
        countryTimeoutTask?.cancel()
        countryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.finishCountryLookup()
        }
        countryLocator?.locate()
    }

    private func finishCountryLookup() {
        countryTimeoutTask?.cancel()
        countryReady = true
        if let track { resolveIfNeeded(track.albumIdentity) }
    }

    private func updatePalette(for album: AlbumIdentity) {
        guard paletteAlbumKey != album.localKey else { return }
        paletteAlbumKey = album.localKey
        paletteTask?.cancel()
        palette = paletteCache[album.localKey] ?? .standard
        guard paletteCache[album.localKey] == nil, let url = album.coverURL else { return }
        loadPalette(from: url, for: album.localKey)
    }

    private func loadSummaryIfNeeded(for album: AlbumIdentity) {
        let key = album.localKey
        guard summaryAlbumKey != key else { return }
        summaryTask?.cancel()
        summaryAlbumKey = key
        albumSummary = summaryCache[key]
        isLoadingSummary = false
        guard !searchedSummaries.contains(key) else { return }
        isLoadingSummary = true
        AppDiagnostics.record("album summary start")

        summaryTask = Task { [weak self] in
            guard let self else { return }
            let summary = try? await wikipedia.summary(for: album)
            guard !Task.isCancelled, summaryAlbumKey == key else { return }
            searchedSummaries.insert(key)
            if let summary { summaryCache[key] = summary }
            albumSummary = summary
            isLoadingSummary = false
            AppDiagnostics.record("album summary finish available=\(summary != nil)")
        }
    }

    private func loadSongDetailsIfNeeded(for track: LocalTrack) {
        let key = track.id
        guard songKey != key else { return }
        songTask?.cancel()
        songKey = key
        songDetails = songCache[key]
        isLoadingSongDetails = false
        guard !searchedSongs.contains(key) else { return }
        isLoadingSongDetails = true
        AppDiagnostics.record("song credits start")

        songTask = Task { [weak self] in
            guard let self else { return }
            let details = try? await musicBrainz.songDetails(for: track)
            guard !Task.isCancelled, songKey == key else { return }
            searchedSongs.insert(key)
            if let details { songCache[key] = details }
            songDetails = details
            isLoadingSongDetails = false
            AppDiagnostics.record("song credits finish available=\(details != nil)")
        }
    }

    func loadTrackStoryIfNeeded(for track: LocalTrack) {
        let key = track.id
        guard trackStoryKey != key else { return }
        trackStoryTask?.cancel()
        trackStoryKey = key
        trackStory = storyCache[key]
        isLoadingTrackStory = false
        guard !searchedStories.contains(key) else { return }
        isLoadingTrackStory = true
        AppDiagnostics.record("track story start")

        trackStoryTask = Task { [weak self] in
            guard let self else { return }
            let story = try? await wikipedia.story(for: track)
            guard !Task.isCancelled, trackStoryKey == key else { return }
            searchedStories.insert(key)
            if let story { storyCache[key] = story }
            trackStory = story
            isLoadingTrackStory = false
            AppDiagnostics.record("track story finish available=\(story != nil)")
        }
    }

    func loadNewsIfNeeded(for album: AlbumIdentity) {
        let key = album.localKey
        if newsAlbumKey == key {
            guard let cached = newsCache[key], Date().timeIntervalSince(cached.date) >= 1800,
                  !isLoadingNews else { return }
        }
        newsTask?.cancel()
        newsAlbumKey = key
        newsArticles = []
        newsUnavailable = false
        isLoadingNews = false
        if let cached = newsCache[key], Date().timeIntervalSince(cached.date) < 1800 {
            newsArticles = cached.articles
            return
        }
        isLoadingNews = true
        AppDiagnostics.record("news lookup start")

        newsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let articles = try await newsClient.articles(for: album)
                guard !Task.isCancelled, newsAlbumKey == key else { return }
                newsCache[key] = (Date(), articles)
                newsArticles = articles
                AppDiagnostics.record("news lookup finish count=\(articles.count)")
            } catch {
                guard !Task.isCancelled, newsAlbumKey == key else { return }
                newsUnavailable = true
                AppDiagnostics.record("news lookup error type=\(String(describing: type(of: error)))")
            }
            isLoadingNews = false
        }
    }

    private func resolveIfNeeded(_ album: AlbumIdentity) {
        guard countryReady else { return }
        let countryCode = releaseCountryCode
        let cacheKey = "\(countryCode)|\(album.localKey)"
        guard resolvedAlbumKey != cacheKey else { return }
        resolutionTask?.cancel()
        resolvedAlbumKey = cacheKey
        archiveError = nil

        isResolving = true
        resolution = nil
        AppDiagnostics.record("release lookup start")

        resolutionTask = Task { [weak self] in
            guard let self else { return }
            if let cached = await AlbumCacheStore.shared.loadResolution(albumKey: album.localKey, countryCode: countryCode) {
                guard !Task.isCancelled, resolvedAlbumKey == cacheKey else { return }
                resolution = cached
                isResolving = false
                if album.coverURL == nil,
                   let coverURL = cached.match?.pages.first(where: \.isFront)?.previewURL
                    ?? cached.match?.pages.first?.previewURL {
                    loadPalette(from: coverURL, for: album.localKey)
                }
                AppDiagnostics.record("release lookup cache_hit")
                return
            }
            guard !Task.isCancelled, resolvedAlbumKey == cacheKey else { return }
            do {
                let result = try await resolver.resolve(album, countryCode: countryCode)
                guard !Task.isCancelled, resolvedAlbumKey == cacheKey else { return }
                await AlbumCacheStore.shared.saveResolution(result, albumKey: album.localKey, countryCode: countryCode)
                resolution = result
                AppDiagnostics.record("release lookup finish result=\(result.match?.hasBooklet == true ? "booklet" : result.match == nil ? "none" : "artwork")")
                if album.coverURL == nil,
                   let coverURL = result.match?.pages.first(where: \.isFront)?.previewURL
                    ?? result.match?.pages.first?.previewURL {
                    loadPalette(from: coverURL, for: album.localKey)
                }
            } catch {
                guard !Task.isCancelled, resolvedAlbumKey == cacheKey else { return }
                resolvedAlbumKey = nil
                archiveError = error.localizedDescription
                AppDiagnostics.record("release lookup error type=\(String(describing: type(of: error)))")
            }
            isResolving = false
        }
    }

    private func loadPalette(from url: URL, for albumKey: String) {
        paletteTask?.cancel()
        paletteTask = Task { [weak self] in
            guard let data = await AlbumCacheStore.shared.imageData(albumKey: albumKey, url: url),
                  !Task.isCancelled,
                  let extracted = AlbumPalette.fromArtwork(data),
                  let self,
                  self.paletteAlbumKey == albumKey else { return }
            self.paletteCache[albumKey] = extracted
            self.palette = extracted
        }
    }
}
