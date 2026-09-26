import BookletCore
import SwiftUI

struct NowPlayingSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.albumPalette) private var palette
    let track: LocalTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.playbackState == .playing ? "NOW PLAYING" : "PAUSED")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(track.playbackState == .playing ? palette.accent : BookletTheme.mutedPaper)
                        .padding(.bottom, 15)

                    cover
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: .black.opacity(0.5), radius: 22, y: 14)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(track.title)
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(BookletTheme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(track.artist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BookletTheme.mutedPaper)
                        Text(track.album)
                            .font(.system(size: 12))
                            .foregroundStyle(BookletTheme.mutedPaper.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 22)

                    songCredits
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 16) {
                progress
                controls
                if model.controlsAreBusy {
                    Text("Waiting for Spotify…")
                        .font(.system(size: 10))
                        .foregroundStyle(BookletTheme.mutedPaper)
                }
                if let error = model.controlError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var songCredits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SONG CREDITS")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(palette.accent)

            if let details = model.songDetails, details.hasCredits {
                if !details.writers.isEmpty { creditRow("WRITTEN BY", names: details.writers) }
                if !details.performers.isEmpty { creditRow("PERFORMERS", names: details.performers) }
                if !details.recordedAt.isEmpty { creditRow("RECORDED AT", names: details.recordedAt) }
                Link("CREDITS: MUSICBRAINZ ↗", destination: details.sourceURL)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 3)
            } else if model.isLoadingSongDetails {
                Text("Looking up recording credits…")
                    .font(.system(size: 11))
                    .foregroundStyle(BookletTheme.mutedPaper)
            } else {
                Text("Writer, performer, and recording credits aren't catalogued for this track yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(BookletTheme.mutedPaper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func creditRow(_ label: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(BookletTheme.mutedPaper.opacity(0.75))
            Text(names.prefix(6).joined(separator: " · "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BookletTheme.paper)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let url = track.artworkURL {
            CachedArtworkImage(albumKey: track.albumIdentity.localKey, url: url, maxPixelSize: 700) {
                coverPlaceholder
            }
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [palette.accent.opacity(0.8), BookletTheme.raised], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text("B")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(BookletTheme.paper.opacity(0.75))
        }
    }

    private var progress: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(BookletTheme.paper.opacity(0.75))
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 3)

            HStack {
                Text(time(track.positionSeconds))
                Spacer()
                Text(time(Double(track.durationMilliseconds) / 1000))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(BookletTheme.mutedPaper.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            controlButton("backward.end.fill", label: "Previous track", command: .previous)
            controlButton(
                track.playbackState == .playing ? "pause.fill" : "play.fill",
                label: track.playbackState == .playing ? "Pause" : "Play",
                command: .togglePlayback,
                prominent: true
            )
            controlButton("forward.end.fill", label: "Next track", command: .next)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(
        _ symbol: String,
        label: String,
        command: SpotifyCommand,
        prominent: Bool = false
    ) -> some View {
        TransportActionButton(symbol: symbol, label: label, isEnabled: !model.controlsAreBusy, prominent: prominent) {
            AppDiagnostics.record("ui control tap command=\(String(describing: command))")
            Task { @MainActor in await model.control(command) }
        }
        .frame(width: prominent ? 52 : 42, height: prominent ? 52 : 42)
        .background(prominent ? palette.accent : Color.white.opacity(0.07), in: Circle())
    }

    private var progressFraction: Double {
        guard track.durationMilliseconds > 0 else { return 0 }
        return min(1, max(0, track.positionSeconds / (Double(track.durationMilliseconds) / 1000)))
    }

    private func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
