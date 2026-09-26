import AppKit
import Foundation

public enum SpotifyReaderError: LocalizedError, Equatable {
    case automationDenied
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Booklet needs permission to read the current track from Spotify. Allow it in System Settings → Privacy & Security → Automation."
        case .scriptFailed(let message):
            "Spotify could not be read: \(message)"
        }
    }
}

public enum SpotifyCommand: Sendable {
    case previous
    case togglePlayback
    case next

    var appleScriptCommand: String {
        switch self {
        case .previous: "previous track"
        case .togglePlayback: "playpause"
        case .next: "next track"
        }
    }
}

public actor SpotifyReader {
    public init() {}

    public func control(_ command: SpotifyCommand) throws {
        let source = """
        with timeout of 5 seconds
            tell application id "com.spotify.client" to \(command.appleScriptCommand)
        end timeout
        """
        _ = try execute(source)
    }

    public func read() throws -> SpotifyReadResult {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
        guard isRunning else { return .notRunning }

        let source = """
        with timeout of 5 seconds
            tell application id "com.spotify.client"
                set stateText to (player state as text)
                if stateText is "stopped" then return {stateText}
                set currentItem to current track
                return {stateText, name of currentItem, artist of currentItem, album of currentItem, album artist of currentItem, spotify url of currentItem, artwork url of currentItem, (duration of currentItem as text), (player position as text)}
            end tell
        end timeout
        """

        let response = try execute(source)

        guard response.numberOfItems >= 1 else { return .noTrack }
        let state = SpotifyPlaybackState(rawValue: string(response, at: 1)) ?? .stopped
        guard response.numberOfItems >= 9, state != .stopped else { return .noTrack }

        let artworkString = string(response, at: 7)
        let track = LocalTrack(
            title: string(response, at: 2),
            artist: string(response, at: 3),
            album: string(response, at: 4),
            albumArtist: string(response, at: 5),
            spotifyURL: string(response, at: 6),
            artworkURL: URL(string: artworkString),
            durationMilliseconds: Int(string(response, at: 8)) ?? 0,
            positionSeconds: Double(string(response, at: 9)) ?? 0,
            playbackState: state
        )
        return .track(track)
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyReaderError.scriptFailed("Unable to create the Spotify request.")
        }
        let response = script.executeAndReturnError(&error)

        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -1743 { throw SpotifyReaderError.automationDenied }
            if number == -1712 { throw SpotifyReaderError.scriptFailed("Spotify did not respond within five seconds.") }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
            throw SpotifyReaderError.scriptFailed(message)
        }

        return response
    }

    private func string(_ descriptor: NSAppleEventDescriptor, at index: Int) -> String {
        descriptor.atIndex(index)?.stringValue ?? ""
    }
}
