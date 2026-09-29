import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import ConvertKit
import TestSupport

/// Deferred review minors, fixed.
@Suite struct LeftoverTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    // Tool errors: show the meaningful line, not ffmpeg's/tar's generic trailer.
    @Test func ffmpegNoStreamIsExplained() {
        let result = ProcessResult(exitCode: 234, stdout: "", stderr: """
            [out#0/mp3 @ 0x7a] Output file does not contain any stream
            Error opening output file x.mp3.
            Error opening output files: Invalid argument
            """)
        #expect(result.meaningfulErrorLine == "the input has nothing that fits this format (for example, a video with no audio track)")
    }

    @Test func ffmpegTrailerIsSkipped() {
        let result = ProcessResult(exitCode: 234, stdout: "", stderr: """
            [wmv2 @ 0x76] width must be multiple of 2
            [vost#0:0/wmv2 @ 0x76] [enc:wmv2 @ 0x76] Error while opening encoder - maybe incorrect parameters such as bit_rate, rate, width or height.
            [vf#0:0 @ 0x76] Error sending frames to consumers: Invalid argument
            [vf#0:0 @ 0x76] Task finished with error code: -22 (Invalid argument)
            [vf#0:0 @ 0x76] Terminating thread with return code -22 (Invalid argument)
            [out#0/asf @ 0x76] Nothing was written into output file, because at least one of its streams received no packets.
            """)
        #expect(result.meaningfulErrorLine == "width must be multiple of 2")
    }

    @Test func tarTrailerIsSkipped() {
        let result = ProcessResult(exitCode: 1, stdout: "", stderr: "tar: ../evil: Path contains '..'\ntar: Error exit delayed from previous errors.\n")
        #expect(result.meaningfulErrorLine == "tar: ../evil: Path contains '..'")
    }

    @Test func signalsAreReportedAsSuch() {
        #expect {
            try ProcessRunner.runChecked(URL(fileURLWithPath: "/bin/sh"), ["-c", "kill -9 $$"])
        } throws: { error in
            guard case let .toolFailed(_, _, lastLine, _)? = error as? PeelError else { return false }
            return lastLine.contains("signal 9")
        }
    }

    // pdf info: what a viewer shows (crop box, rotation); nothing made up for locked files.
    @Test func infoUsesCropBoxAndRotation() throws {
        let doc = try #require(PDFDocument(url: try Fixtures.makeMarkedPDF(at: dir.appendingPathComponent("plain.pdf"))))
        doc.page(at: 0)?.setBounds(CGRect(x: 0, y: 50, width: 100, height: 50), for: .cropBox)
        doc.page(at: 0)?.rotation = 90
        let url = dir.appendingPathComponent("c.pdf")
        #expect(doc.write(to: url))
        #expect(try PDFBackend.info(url).pageSize == CGSize(width: 50, height: 100))
    }

    @Test func infoOnLockedPDFHasNoPageSize() throws {
        let locked = try Fixtures.makePDF(at: dir.appendingPathComponent("l.pdf"), pages: 1, password: "pw")
        #expect(try PDFBackend.info(locked).pageSize == nil)
    }

    // Trim that starts past the end fails instead of writing a stray tail clip.
    @Test(.enabled(if: Fixtures.has(.ffmpeg) && Fixtures.has(.ffprobe)))
    func trimPastTheEndFails() throws {
        let clip = dir.appendingPathComponent("clip.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=2:size=160x120:rate=10", "-c:v", "mpeg4", clip.path,
        ])
        let out = dir.appendingPathComponent("t.mov")
        #expect {
            try MediaBackend.trim(clip, to: out, from: 5, until: 8)
        } throws: { error in
            (error as? PeelError)?.errorDescription?.contains("after the end") == true
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    // Archive errors name the file, not peel's internal staging folder.
    @Test func unreadableArchiveInputIsNamedPlainly() throws {
        let locked = try Fixtures.writeText("x", to: dir.appendingPathComponent("secret.txt"))
        let other = try Fixtures.writeText("y", to: dir.appendingPathComponent("other.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        #expect {
            try ArchiveBackend.create([other, locked], at: dir.appendingPathComponent("x.zip"))
        } throws: { error in
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return text.contains("secret.txt") && !text.contains("peel-stage")
        }
    }

    // Merge/zip are one job: early exits report one outcome, not one per file.
    @Test func groupedActionsReportOneOutcomeWhenCancelled() throws {
        let token = CancelToken()
        token.cancel()
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        let b = try Fixtures.makePDF(at: dir.appendingPathComponent("b.pdf"), pages: 1)
        #expect(ActionRunner().run(.pdfMerge, on: [a, b], cancel: token).count == 1)
        #expect(ActionRunner().run(.zip, on: [a, b], cancel: token).count == 1)
    }

    // Resizing keeps a wide-gamut (Display P3) image's colour space.
    @Test func resizeKeepsDisplayP3() throws {
        let p3 = try Fixtures.makeImage(at: dir.appendingPathComponent("p3.png"), width: 40, height: 30, type: .png,
                                        colorSpace: CGColorSpace.displayP3)
        let out = dir.appendingPathComponent("small.png")
        try ImageBackend.convert(p3, to: out, format: .png, options: ImageOptions(width: 20))
        #expect(Fixtures.profileName(out)?.contains("P3") == true)
    }

    // Review follow-up: extended-range / float colour spaces can't back an 8-bit bitmap — fall back to sRGB.
    @Test func extendedRangeImagesStillConvert() throws {
        let hdr = try Fixtures.makeHDRImage(at: dir.appendingPathComponent("hdr.tiff"), width: 40, height: 30)
        let transparent = try Fixtures.makeHDRImage(at: dir.appendingPathComponent("t.tiff"), width: 40, height: 30, alpha: true)
        #expect(throws: Never.self) { try ImageBackend.convert(hdr, to: dir.appendingPathComponent("a.png"), format: .png, options: ImageOptions(width: 20)) }
        #expect(throws: Never.self) { try ImageBackend.convert(transparent, to: dir.appendingPathComponent("b.jpg"), format: .jpg) }
        #expect(ImageBackend.rgbSpace(of: try ImageBackend.load(hdr), bitmap: true).name != CGColorSpace.extendedSRGB)
    }

    @Test func signalKillDoesNotPretendToBeAnExitCode() {
        let error = PeelError.toolFailed(name: "ffmpeg", exitCode: 9, lastLine: "was stopped (signal 9)", details: "")
        #expect(error.errorDescription == "ffmpeg was stopped (signal 9)")
    }
}
