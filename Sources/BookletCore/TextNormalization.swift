import Foundation

public enum TextNormalization {
    private static let editionLabels: Set<String> = [
        "deluxe", "deluxe edition", "deluxe version",
        "super deluxe", "super deluxe edition", "super deluxe version",
        "expanded edition", "special edition", "collectors edition",
        "anniversary", "anniversary edition", "anniversary version",
        "remaster", "remastered", "remastered edition",
    ]

    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func escapeLucene(_ value: String) -> String {
        let special = CharacterSet(charactersIn: "+-!(){}[]^\"~*?:\\/")
        return value.unicodeScalars.reduce(into: "") { result, scalar in
            if special.contains(scalar) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
    }

    static func year(from value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    public static func originalEditionTitle(from title: String) -> String? {
        var currentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var foundEdition = false
        while let originalTitle = titleRemovingEditionSuffix(from: currentTitle) {
            currentTitle = originalTitle
            foundEdition = true
        }
        return foundEdition ? currentTitle : nil
    }

    private static func titleRemovingEditionSuffix(from title: String) -> String? {
        for separator in [" (", " [", " - ", " – ", " — ", " : "] {
            guard let range = title.range(of: separator, options: .backwards) else { continue }
            let base = title[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else { continue }

            var edition = String(title[range.upperBound...])
            if separator == " (" {
                guard edition.hasSuffix(")") else { continue }
                edition.removeLast()
            } else if separator == " [" {
                guard edition.hasSuffix("]") else { continue }
                edition.removeLast()
            }

            let label = normalize(edition)
            let coreLabel = label.split(separator: " ").filter { word in
                if word == "remaster" || word == "remastered" || word == "version" { return false }
                if word.count == 4, let year = Int(word), (1900...2099).contains(year) { return false }
                return true
            }.joined(separator: " ")
            if editionLabels.contains(label) || editionLabels.contains(coreLabel) ||
                coreLabel.range(of: #"^\d{1,3}(st|nd|rd|th)? anniversary( deluxe)?( edition)?$"#, options: .regularExpression) != nil ||
                (coreLabel.isEmpty && (label.contains("remaster") || label.contains("remastered"))) {
                return base
            }
        }
        return nil
    }
}
