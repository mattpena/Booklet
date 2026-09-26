# Booklet for Mac

Booklet is a native macOS companion that restores the physical-album experience while Spotify plays. It reads the current track directly from the Spotify app on the same Mac, matches the album to a physical MusicBrainz release, and opens the ordered Cover Art Archive scans in a swipeable, zoomable booklet reader.

No Spotify Developer account, API key, client ID, or Spotify login is required.

## What the MVP includes

- Direct local Spotify detection through the app's built-in AppleScript interface
- Track, artist, album, album artist, artwork, playback state, progress, and Spotify URI
- Automatic two-second updates and previous, play/pause, and next controls
- MusicBrainz physical-release matching by album and artist metadata
- Country-specific matching: one-time location detection defaults to your current country, with a searchable manual override
- Strict country boundaries for both MusicBrainz search and saved mappings; no foreign-edition fallback
- Candidate ranking that strongly prefers releases with actual `Booklet` scans
- Deluxe, anniversary, and remastered-edition fallback to original-title scans when the selected country's edition has no booklet, without substituting a foreign edition
- Ordered Cover Art Archive pages, thumbnail navigation, horizontal paging, window-level arrow-key navigation, and in-panel zoom controls with trackpad pinch and double-click reset
- An Album tab with a conservatively matched Wikipedia summary that prefers the original album story for deluxe, anniversary, and remastered editions, available alongside the booklet and shown by default when no booklet scan exists
- A Track tab that prefers the original song article for remastered tracks, including available recording, music-video, and live-performance sections beyond its short summary, with distinct paragraph spacing; unavailable tracks show a clear empty state instead of generated copy
- A News tab that renders recent Google News RSS headlines for the current artist inside Booklet, with publisher names, dates, and links to the full results
- A scrollable Now Playing sidebar with available MusicBrainz recording credits (writers, performers, recording location) and transport controls pinned to the bottom
- Booklet, Track, Album, and News tabs above the preview, with Booklet preferred when scans exist and source links in their respective views
- Manual refresh re-reads Spotify and re-fetches the current track's credits, stories, news, artwork palette, and country-specific booklet
- Album-aware colors drawn from the current cover artwork
- A custom high-resolution macOS Dock icon shaped like a booklet spine and two iridescent discs
- Native states for Spotify closed, nothing playing, Automation permission denied, no release match, and no booklet scan
- Clear source links and unavailable states when an album article or song credits cannot be confidently matched
- A local disk cache for country-specific release matches and artwork, with automatic removal 60 days after an album was last played; a repository boundary remains for future shared corrections
- Optional Sparkle update checks in the app menu, with automatic daily polling and in-app installation when a signed HTTPS update feed is configured

## Build and run

Requirements: macOS 14 or newer, Xcode 16 or newer, and the Spotify desktop app.

```bash
./scripts/build-app.sh
open outputs/Booklet.zip
```

Unzip `Booklet.zip`, move `Booklet.app` to Applications, and open it. The archive is the recommended build output because file providers can attach Finder metadata to app bundles stored inside Documents.

The first time Booklet reads Spotify, macOS asks whether it may automate Spotify. Choose **Allow**. If access was previously denied, open:

**System Settings → Privacy & Security → Automation → Booklet → Spotify**

Booklet also asks for location access once to choose your release country. It uses only the country code, not your coordinates, for MusicBrainz searches. If location access is unavailable or denied, it uses the Mac's region setting. Click the country pill in the top bar to choose a different country or retry location detection. Booklet does not show artwork from another country's edition when no local release exists.

For development without creating the app bundle:

```bash
swift run Booklet
```

The packaged `.app` is recommended when testing Automation permission because it supplies the required usage description and entitlement.

## Updates

Booklet uses [Sparkle](https://sparkle-project.org/documentation/) for update checks and installation. Releases are hosted at [GitHub Releases](https://github.com/mattpena/Booklet/releases), and the signed appcast lives at `https://mattpena.github.io/Booklet/updates/appcast.xml`. A release build checks daily and offers **Booklet → Check for Updates…**. It asks before installing by default. Local builds without a feed remain usable, but do not check for updates.

The Sparkle EdDSA private key is stored in this Mac's Keychain under account `booklet`; never commit or upload it. Back it up securely with Sparkle's `generate_keys --account booklet -x <private-key-file>`, then keep the exported file outside this repository. Losing the key can strand ad-hoc-signed installations on their current version.

To publish an update:

1. Increase `CFBundleVersion` in `Resources/Info.plist` (and `CFBundleShortVersionString` when appropriate).
2. Commit and push the app changes to `main`.
3. Run `BOOKLET_SIGNING_IDENTITY='Developer ID Application: …' BOOKLET_NOTARY_PROFILE='…' ./scripts/publish-update.sh`. The script builds, notarizes and staples the app, signs its ZIP and appcast, creates a GitHub Release, and pushes the updated feed. It requires a clean, pushed `main` branch.

There is **no Developer ID certificate configured yet**. The release script therefore refuses to publish by default. For an explicitly accepted personal preview only, `BOOKLET_ALLOW_ADHOC_RELEASE=1 ./scripts/publish-update.sh` publishes an unnotarized pre-release; macOS may warn or require manual approval. Do not treat that path as a public distribution channel.

Build 30 predates the updater, so its replacement must be installed manually once. Subsequent releases can be found in-app after a signed feed and an updater-enabled build are published. Test a full update from an older installed version before relying on the channel.

## Diagnostics

Booklet writes a rotating diagnostic log to `~/Library/Logs/Booklet/Booklet.log` (and keeps the prior segment as `Booklet.previous.log`). It records Spotify reads and control commands, lookup and artwork operations, and Mac sleep/wake events with timestamps. It does not record song titles, artist names, album names, Spotify URLs, or artwork URLs.

If the app appears unresponsive, note the time and inspect the last events without restarting it first:

```bash
tail -n 200 ~/Library/Logs/Booklet/Booklet.log
```

## How it works

1. Confirm that `com.spotify.client` is running locally.
2. Ask Spotify for its read-only `current track` object through Apple Events.
3. Build a stable album key from the album title and cover image when available, falling back to album artist and title.
4. Check the local correction repository for a known MusicBrainz release mapping.
5. Otherwise search MusicBrainz for official releases matching the album, artist, and chosen release country.
6. Inspect artwork for the strongest candidates and rank booklet scans above covers-only releases. For a recognized deluxe title without a booklet, retry the original album title in the same country.
7. Preserve the Cover Art Archive image order and present every approved packaging scan.
8. Independently look up a Wikipedia album article and MusicBrainz recording relationships. When opened, Track searches for a confidently matched Wikipedia song article and News reads a Google News search feed. These do not change the country-filtered booklet match; missing or ambiguous information is left blank rather than guessed.

The playback buttons send play/pause, previous, and next commands to the Spotify app running on this Mac.

Booklet stores release matches and downloaded artwork in `~/Library/Application Support/Booklet/AlbumCache`. Listening to an album renews its 60-day retention window; browsing cached pages or pausing playback does not. Expired albums are removed on launch and during daily cleanup. Manual refresh invalidates the current country's release match and fetches it again.

The Track and Album tabs use Wikipedia's public API and credit their sources. Song credits come from MusicBrainz recording and work relationships, so their availability varies by track. News reads Google News's public RSS search feed directly, showing headlines, publisher names, and dates in the app without an API key or backend. Opening a headline goes through Google News to the publisher. The feed states that it is for personal, non-commercial feed-reader use only; this integration should not be used for a commercial or publicly distributed product without a different licensed news source. Booklet does not copy full article text or editorially verify headlines.

## Project layout

```text
Sources/Booklet/                    SwiftUI app, state, and reader views
Sources/BookletCore/SpotifyReader   Local Spotify AppleScript integration
Sources/BookletCore/MusicBrainz     Release search and lookup
Sources/BookletCore/CoverArt        Ordered artwork retrieval
Sources/BookletCore/BookletResolver Candidate scoring and selection
Resources/                          App metadata and permissions
scripts/build-app.sh                Release build and .app packaging
Tests/BookletCoreTests/             Matching and archive decoding tests
```

## Validation

```bash
swift test
swift build
```

MusicBrainz requires a meaningful API User-Agent and offers separate terms for commercial use. Cover Art Archive images are community contributed and may have their own licensing considerations.
