import Foundation

public struct CoverArtClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func artwork(for releaseID: String) async throws -> [BookletPage] {
        var request = URLRequest(url: URL(string: "https://coverartarchive.org/release/\(releaseID)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 404 { return [] }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try Self.decodePages(from: data)
    }

    static func decodePages(from data: Data) throws -> [BookletPage] {
        try JSONDecoder().decode(Response.self, from: data).images
            .filter { $0.approved != false }
            .compactMap(\.model)
    }
}

private struct Response: Decodable {
    let images: [ImageDTO]
}

private struct ImageDTO: Decodable {
    let id: FlexibleID
    let image: String
    let thumbnails: [String: String]?
    let types: [String]?
    let comment: String?
    let approved: Bool?
    let front: Bool?
    let back: Bool?

    var model: BookletPage? {
        guard let original = secureURL(image) else { return nil }
        let thumbnail = secureURL(thumbnails?["250"] ?? thumbnails?["small"] ?? image) ?? original
        let preview = secureURL(thumbnails?["1200"] ?? thumbnails?["500"] ?? thumbnails?["large"] ?? image) ?? original
        return BookletPage(
            id: id.value,
            imageURL: original,
            thumbnailURL: thumbnail,
            previewURL: preview,
            types: types ?? [],
            comment: comment ?? "",
            isFront: front ?? false,
            isBack: back ?? false
        )
    }

    private func secureURL(_ value: String) -> URL? {
        URL(string: value.replacingOccurrences(of: "http://", with: "https://"))
    }
}

private enum FlexibleID: Decodable {
    case string(String)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .integer(try container.decode(Int.self))
        }
    }

    var value: String {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        }
    }
}
