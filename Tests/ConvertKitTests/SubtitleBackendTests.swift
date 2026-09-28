import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct SubtitleBackendTests {
    let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\nHello\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nTwo\r\nlines\r\n"
    let vtt = """
    WEBVTT

    NOTE a comment

    00:01.000 --> 00:02.500 align:start
    Hello

    intro
    01:00:03.000 --> 01:00:04.000
    Later
    """

    @Test func parsesSRTWithBOMAndCRLF() throws {
        let cues = try SubtitleBackend.parse(srt)
        #expect(cues == [Cue(start: 1000, end: 2500, text: "Hello"), Cue(start: 3000, end: 4000, text: "Two\nlines")])
    }

    @Test func parsesVTTHeaderNotesSettingsAndIdentifiers() throws {
        let cues = try SubtitleBackend.parse(vtt)
        #expect(cues == [Cue(start: 1000, end: 2500, text: "Hello"), Cue(start: 3_603_000, end: 3_604_000, text: "Later")])
    }

    @Test func timestamps() {
        #expect(SubtitleBackend.parseTimestamp("00:00:01,000") == 1000)
        #expect(SubtitleBackend.parseTimestamp("01:02.5") == 62_500)
        #expect(SubtitleBackend.parseTimestamp("1:00:00.000") == 3_600_000)
        #expect(SubtitleBackend.parseTimestamp("nope") == nil)
        #expect(SubtitleBackend.formatTimestamp(3_723_004, separator: ",") == "01:02:03,004")
    }

    @Test func rendersSRT() throws {
        let out = try SubtitleBackend.render([Cue(start: 1000, end: 2500, text: "Hi")], as: .srt)
        #expect(out == "1\n00:00:01,000 --> 00:00:02,500\nHi\n")
    }

    @Test func rendersVTT() throws {
        let out = try SubtitleBackend.render([Cue(start: 1000, end: 2500, text: "Hi")], as: .vtt)
        #expect(out == "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHi\n")
    }

    @Test func rendersPlainText() throws {
        let out = try SubtitleBackend.render(try SubtitleBackend.parse(srt), as: .txt)
        #expect(out == "Hello\nTwo\nlines\n")
    }

    @Test func roundTripSRTtoVTTtoSRT() throws {
        let cues = try SubtitleBackend.parse(srt)
        let back = try SubtitleBackend.parse(try SubtitleBackend.render(cues, as: .vtt))
        #expect(back == cues)
    }

    @Test func noCuesIsAnError() {
        #expect(throws: PeelError.self) { try SubtitleBackend.parse("WEBVTT\n\n") }
    }

    @Test func convertsFiles() throws {
        let dir = try Fixtures.tempDir()
        let input = try Fixtures.writeText(srt, to: dir.appendingPathComponent("a.srt"))
        let output = dir.appendingPathComponent("a.vtt")
        try SubtitleBackend.convert(input, to: output, format: .vtt)
        #expect(try String(contentsOf: output, encoding: .utf8).hasPrefix("WEBVTT"))
    }
}
