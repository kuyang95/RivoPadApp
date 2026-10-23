import Foundation

/// A readable label; the URL used for editing and navigation is never rewritten.
enum BrowserAddressDisplay {
    static func text(_ input: String) -> String {
        guard let url = URLComponents(string: input),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              let schemeEnd = input.range(of: "://") else { return input }
        let rest = input[schemeEnd.upperBound...]
        let authority = rest.prefix { !"/?#".contains($0) }.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let path = url.percentEncodedPath
        let pattern = try? NSRegularExpression(pattern: "(?:%[0-9a-fA-F]{2})+")
        var readable = path
        for match in (pattern?.matches(in: path, range: NSRange(path.startIndex..., in: path)) ?? []).reversed() {
            guard let range = Range(match.range, in: path),
                  let decoded = String(path[range]).removingPercentEncoding else { continue }
            let safe = decoded.unicodeScalars.map { scalar -> String in
                if scalar.value > 127 && !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                    !CharacterSet.controlCharacters.contains(scalar) && scalar.properties.generalCategory != .format {
                    return String(scalar)
                }
                return String(scalar).addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? String(scalar)
            }.joined()
            guard let outputRange = Range(match.range, in: readable) else { continue }
            readable.replaceSubrange(outputRange, with: safe)
        }
        return (scheme == "http" ? "http://" : "") + authority + (readable == "/" ? "" : readable)
    }
}
