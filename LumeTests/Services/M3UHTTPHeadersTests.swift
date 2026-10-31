//
//  M3UHTTPHeadersTests.swift
//  LumeTests
//

import Foundation
@testable import Lume
import Testing

private func parseEntries(_ content: String) async throws -> [M3UEntry] {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m3u")
    try content.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    var entries: [M3UEntry] = []
    try await M3UParser.parseStreaming(fileURL: url, batchSize: 100) { _ in } onBatch: { batch, _ in
        entries.append(contentsOf: batch)
    }
    return entries
}

struct M3UHTTPHeadersTests {
    @Test func `EXTVLCOPT header options become headers`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan A
        #EXTVLCOPT:http-referrer=https://example.com/
        #EXTVLCOPT:http-origin=https://example.com
        #EXTVLCOPT:http-user-agent=Foo/1.0
        #EXTVLCOPT:network-caching=1000
        https://example.com/a.m3u8
        """)
        #expect(entries.first?.httpHeaders == [
            "Referer": "https://example.com/",
            "Origin": "https://example.com",
            "User-Agent": "Foo/1.0",
        ])
    }

    @Test func `EXTHTTP JSON becomes headers`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan B
        #EXTHTTP:{"Referer":"https://example.com/","Origin":"https://example.com"}
        https://example.com/b.m3u8
        """)
        #expect(entries.first?.httpHeaders == ["Referer": "https://example.com/", "Origin": "https://example.com"])
    }

    @Test func `pipe headers are split off the URL and decoded`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan C
        https://example.com/c.m3u8|Referer=https%3A%2F%2Fexample.com%2F&User-Agent=Foo%20Bar
        """)
        #expect(entries.first?.url == "https://example.com/c.m3u8")
        #expect(entries.first?.httpHeaders == ["Referer": "https://example.com/", "User-Agent": "Foo Bar"])
    }

    @Test func `pipe headers win over directive lines`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan D
        #EXTVLCOPT:http-referrer=https://old.example/
        https://example.com/d.m3u8|Referer=https://new.example/
        """)
        #expect(entries.first?.httpHeaders == ["Referer": "https://new.example/"])
    }

    @Test func `headers do not carry over to the next entry`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan E
        #EXTVLCOPT:http-referrer=https://example.com/
        https://example.com/e.m3u8
        #EXTINF:-1,Chan F
        https://example.com/f.m3u8
        """)
        #expect(entries.count == 2)
        #expect(entries.last?.httpHeaders == nil)
    }

    @Test func `entries without header lines have none`() async throws {
        let entries = try await parseEntries("""
        #EXTM3U
        #EXTINF:-1,Chan G
        https://example.com/g.m3u8
        """)
        #expect(entries.first?.httpHeaders == nil)
    }

    @Test func `control characters and malformed lines are dropped`() {
        #expect(M3UHTTPHeaders.directive("#EXTVLCOPT:http-referrer=https://a.example/\u{0D}X-Injected: 1") == nil)
        #expect(M3UHTTPHeaders.directive("#EXTHTTP:{not json") == nil)
        #expect(M3UHTTPHeaders.directive("#EXTVLCOPT:http-referrer") == nil)
        #expect(M3UHTTPHeaders.directive("#EXTVLCOPT:http-referrer=") == nil)
    }

    @Test func `stored headers encode the same way every time`() {
        let headers = ["User-Agent": "Foo", "Referer": "https://example.com/", "Origin": "https://example.com"]
        let first = LiveStream.encodeHTTPHeaders(headers)
        #expect(first == LiveStream.encodeHTTPHeaders(headers))
        #expect(first == #"{"Origin":"https:\/\/example.com","Referer":"https:\/\/example.com\/","User-Agent":"Foo"}"#)
        #expect(LiveStream.encodeHTTPHeaders(nil) == nil)
        #expect(LiveStream.encodeHTTPHeaders([:]) == nil)
    }

    @Test func `a live channel with headers skips VLCKit`() throws {
        let url = try #require(URL(string: "https://example.com/a.m3u8"))
        let withHeaders = PlayableMedia(
            id: "live-1", url: url, title: "A", subtitle: nil, posterURL: nil, kind: .live, startTime: 0,
            contentRef: .live("p-live-1"), httpHeaders: ["Referer": "https://example.com/"]
        )
        let without = PlayableMedia(
            id: "live-2", url: url, title: "B", subtitle: nil, posterURL: nil, kind: .live, startTime: 0,
            contentRef: .live("p-live-2")
        )
        #expect(withHeaders.unsupportedEngines == [.vlcKit])
        #expect(without.unsupportedEngines.isEmpty)
        #expect(PlayerEnginePriority.playable([.ksPlayer, .vlcKit, .avPlayer], for: withHeaders) == [.ksPlayer, .avPlayer])
    }
}
