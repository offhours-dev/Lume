//
//  M3UHTTPHeaders.swift
//  Lume
//
//  Per-channel HTTP headers in the three forms IPTV players read from an m3u:
//
//      #EXTVLCOPT:http-referrer=https://example.com/
//      #EXTHTTP:{"Referer":"https://example.com/","Origin":"https://example.com"}
//      https://example.com/live.m3u8|Referer=https%3A%2F%2Fexample.com%2F&User-Agent=Foo
//
//  Some sources play only when the player sends a Referer, Origin or
//  User-Agent. The parser collects them here; playback hands them to the
//  engine through `PlayableMedia.httpHeaders`.
//

import Foundation

nonisolated enum M3UHTTPHeaders {
    /// `#EXTVLCOPT` keys and the header each one sets.
    private static let vlcOptions = [
        "http-referrer": "Referer",
        "http-origin": "Origin",
        "http-user-agent": "User-Agent",
    ]

    /// Headers a directive line sets, or `nil` when the line is not one of the
    /// header forms (or carries nothing usable).
    static func directive(_ line: String) -> [String: String]? {
        if line.hasPrefix("#EXTVLCOPT:") {
            let option = line.dropFirst("#EXTVLCOPT:".count)
            guard let equals = option.firstIndex(of: "=") else { return nil }
            let key = option[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard let name = vlcOptions[key] else { return nil }
            return cleaned([name: String(option[option.index(after: equals)...])])
        }
        if line.hasPrefix("#EXTHTTP:") {
            let json = Data(line.dropFirst("#EXTHTTP:".count).utf8)
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
            return cleaned(object.compactMapValues { $0 as? String })
        }
        return nil
    }

    /// Splits the Kodi form `url|Name=value&Name=value` into the URL and its
    /// (percent-decoded) headers. A line without `|` comes back unchanged.
    static func splitURL(_ line: String) -> (url: String, headers: [String: String]?) {
        guard let pipe = line.firstIndex(of: "|") else { return (line, nil) }
        var headers: [String: String] = [:]
        for pair in line[line.index(after: pipe)...].split(separator: "&") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let name = pair[..<equals].removingPercentEncoding ?? String(pair[..<equals])
            let value = pair[pair.index(after: equals)...]
            headers[name] = value.removingPercentEncoding ?? String(value)
        }
        return (String(line[..<pipe]), cleaned(headers))
    }

    /// `base` with `overrides` laid over it; `nil` when both are empty.
    static func merged(_ base: [String: String]?, _ overrides: [String: String]?) -> [String: String]? {
        let result = (base ?? [:]).merging(overrides ?? [:]) { _, new in new }
        return result.isEmpty ? nil : result
    }

    /// Drops blank names and values, and any that carry a control character,
    /// which could otherwise smuggle extra header lines into a request.
    private static func cleaned(_ headers: [String: String]) -> [String: String]? {
        var result: [String: String] = [:]
        for (rawName, rawValue) in headers {
            let name = rawName.trimmingCharacters(in: .whitespaces)
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty,
                  !(name + value).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { continue }
            result[name] = value
        }
        return result.isEmpty ? nil : result
    }
}
