import AppKit
import BookletCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCountryPicker = false
    @State private var selectedTab: ArchiveTab = .booklet
    @State private var selectedByUser = false

    private let sidebarWidth: CGFloat = 310

    private static let headerIcon: NSImage? = {
        if let iconURL = Bundle.main.url(forResource: "Booklet", withExtension: "icns") {
            return NSImage(contentsOf: iconURL)
        }
        let developmentIcon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/BookletIcon.png")
        return NSImage(contentsOf: developmentIcon)
    }()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [model.palette.glow, model.palette.backdrop, BookletTheme.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                mainContent
            }
        }
        .environment(\.albumPalette, model.palette)
        .preferredColorScheme(.dark)
        .onAppear { selectDefaultTab() }
        .onChange(of: model.track?.albumIdentity.localKey) { _, _ in
            selectedByUser = false
            selectedTab = .booklet
        }
        .onChange(of: model.track?.id) { _, _ in loadSelectedContext() }
        .onChange(of: selectedTab) { _, _ in loadSelectedContext() }
        .onChange(of: model.releaseCountryCode) { _, _ in
            selectedByUser = false
            selectedTab = .booklet
        }
        .onChange(of: model.resolution) { _, resolution in
            guard !selectedByUser, let resolution else { return }
            selectedTab = resolution.match?.hasBooklet == true ? .booklet : .album
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let icon = Self.headerIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "opticaldisc.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(model.palette.accent)
                    }
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                Text("BOOKLET")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(3.2)
                    .foregroundStyle(BookletTheme.paper)
            }
            .frame(width: sidebarWidth - 22, alignment: .leading)

            if model.track != nil {
                HStack(spacing: 4) {
                    tabButton(.booklet, title: "BOOKLET", symbol: "book.closed")
                    tabButton(.track, title: "TRACK", symbol: "music.note")
                    tabButton(.album, title: "ALBUM", symbol: "text.book.closed")
                    tabButton(.news, title: "NEWS", symbol: "newspaper")
                }
                .padding(.leading, 24)
            }

            Spacer(minLength: 12)

            NativeActionButton("Choose release country") {
                AppDiagnostics.record("ui country menu tap")
                showingCountryPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                    Text(model.countryReady ? "\(model.releaseCountryCode) RELEASES" : "FINDING COUNTRY")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(model.palette.accent)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(model.palette.accent.opacity(0.12), in: Capsule())
            }
            .popover(isPresented: $showingCountryPicker) {
                CountryPickerView()
                    .environmentObject(model)
            }
            .help("Choose which country's album editions to show")
            .padding(.trailing, 12)

            NativeActionButton("Refresh track and album details", isEnabled: !model.isRefreshingManually) {
                AppDiagnostics.record("ui refresh tap")
                Task { @MainActor in await model.refreshNowPlaying() }
            } label: {
                Group {
                    if model.isRefreshingManually {
                        ProgressView().controlSize(.small).tint(model.palette.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .foregroundStyle(BookletTheme.paper)
            .background(Color.white.opacity(0.06), in: Circle())
            .help("Refresh track, credits, stories, news, and booklet")
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
    }

    private func tabButton(_ tab: ArchiveTab, title: String, symbol: String) -> some View {
        NativeActionButton(title) {
            AppDiagnostics.record("ui tab tap tab=\(tab)")
            selectedTab = tab
            selectedByUser = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .tracking(1.2)
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(selectedTab == tab ? model.palette.accent : BookletTheme.mutedPaper)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(selectedTab == tab ? model.palette.accent.opacity(0.14) : Color.clear, in: Capsule())
        }
    }

    private func selectDefaultTab() {
        if let resolution = model.resolution, resolution.match?.hasBooklet != true {
            selectedTab = .album
        } else {
            selectedTab = .booklet
        }
    }

    private func loadSelectedContext() {
        guard let track = model.track else { return }
        switch selectedTab {
        case .track: model.loadTrackStoryIfNeeded(for: track)
        case .news: model.loadNewsIfNeeded(for: track.albumIdentity)
        case .booklet, .album: break
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let track = model.track {
            HStack(spacing: 0) {
                NowPlayingSidebar(track: track)
                    .frame(width: sidebarWidth)
                ArchivePanel(
                    selectedTab: selectedTab,
                    track: track,
                    countryCode: model.releaseCountryCode,
                    countryReady: model.countryReady,
                    resolution: model.resolution,
                    isResolving: model.isResolving,
                    error: model.archiveError,
                    summary: model.albumSummary,
                    isLoadingSummary: model.isLoadingSummary,
                    trackStory: model.trackStory,
                    isLoadingTrackStory: model.isLoadingTrackStory,
                    newsArticles: model.newsArticles,
                    isLoadingNews: model.isLoadingNews,
                    newsUnavailable: model.newsUnavailable
                )
            }
        } else {
            ListeningStateView(state: model.listenerState)
        }
    }

}

private struct ListeningStateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.albumPalette) private var palette
    let state: AppModel.ListenerState

    var body: some View {
        VStack(spacing: 22) {
            record
            VStack(spacing: 9) {
                Text(kicker)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(palette.accent)
                Text(title)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .foregroundStyle(BookletTheme.paper)
                Text(message)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookletTheme.mutedPaper)
                    .frame(maxWidth: 470)
                    .lineSpacing(4)
            }

            HStack(spacing: 10) {
                if state == .spotifyNotRunning || state == .nothingPlaying {
                    PaperActionButton("Open Spotify", filled: true) { model.openSpotify() }
                }
                if state == .permissionDenied {
                    PaperActionButton("Open Automation Settings", filled: true) { model.openAutomationSettings() }
                }
                PaperActionButton("Check Again") {
                    Task { @MainActor in await model.refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.75))
            ForEach([0.72, 0.52, 0.34], id: \.self) { size in
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).scaleEffect(size)
            }
            Circle().fill(palette.accent).frame(width: 44, height: 44)
            Circle().fill(BookletTheme.ink).frame(width: 10, height: 10)
        }
        .frame(width: 185, height: 185)
        .shadow(color: .black.opacity(0.55), radius: 26, y: 16)
    }

    private var kicker: String {
        state == .permissionDenied ? "ONE-TIME PERMISSION" : "THE ALBUM, RESTORED"
    }

    private var title: String {
        switch state {
        case .checking: "Tuning in…"
        case .spotifyNotRunning: "Open Spotify to begin."
        case .nothingPlaying: "Play an album in Spotify."
        case .permissionDenied: "Let Booklet read Spotify."
        case .failed: "Spotify could not be read."
        case .ready: "Your album is ready."
        }
    }

    private var message: String {
        switch state {
        case .checking:
            "Booklet is checking the Spotify app on this Mac."
        case .spotifyNotRunning:
            "No account connection is needed. Booklet reads the song playing in the local Spotify app."
        case .nothingPlaying:
            "The matching physical release will open here when music starts."
        case .permissionDenied:
            "macOS protects app-to-app access. Enable Booklet under Privacy & Security → Automation, then check again."
        case .failed(let detail): detail
        case .ready: ""
        }
    }
}
