import Foundation
import Testing
@testable import ConvertKit

@Suite struct FileFormatTests {
    @Test(arguments: [
        ("IMG_0412.HEIC", FileFormat.heic), ("photo.jpeg", .jpg), ("scan.TIF", .tiff),
        ("backup.tar.gz", .tgz), ("logs.TAR.XZ", .txz), ("stuff.7z", .sevenZip),
        ("notes.md", .txt), ("clip.m4v", .mp4), ("talk.mov", .mov), ("subs.vtt", .vtt),
    ])
    func detectsFromFilename(_ testCase: (String, FileFormat)) {
        #expect(FileFormat(url: URL(fileURLWithPath: "/tmp/\(testCase.0)")) == testCase.1)
    }

    @Test func unknownAndExtensionlessFilesAreNil() {
        #expect(FileFormat(url: URL(fileURLWithPath: "/tmp/file.qqqq")) == nil)
        #expect(FileFormat(url: URL(fileURLWithPath: "/tmp/Makefile")) == nil)
    }

    @Test func parsesUserTypedNames() {
        #expect(FileFormat(name: "JPEG") == .jpg)
        #expect(FileFormat(name: ".png") == .png)
        #expect(FileFormat(name: "7z") == .sevenZip)
        #expect(FileFormat(name: "tar.gz") == .tgz)
        #expect(FileFormat(name: "docx") == nil)
    }

    @Test func fileExtensions() {
        #expect(FileFormat.tgz.fileExtension == "tar.gz")
        #expect(FileFormat.sevenZip.fileExtension == "7z")
        #expect(FileFormat.jpg.fileExtension == "jpg")
    }

    @Test func categories() {
        #expect(FileFormat.heic.category == .image)
        #expect(FileFormat.pdf.category == .document)
        #expect(FileFormat.mov.category == .video)
        #expect(FileFormat.opus.category == .audio)
        #expect(FileFormat.vtt.category == .subtitle)
        #expect(FileFormat.rar.category == .archive)
    }

    @Test func errorMessagesAreSingleLineAndHelpful() {
        let missing = PeelError.missingTool(name: "ffmpeg", installHint: "brew install ffmpeg")
        #expect(missing.errorDescription?.contains("brew install ffmpeg") == true)
        let all: [PeelError] = [
            missing, .pageOutOfBounds(page: 9, count: 3), .invalidPageRange("x"),
            .toolFailed(name: "ffmpeg", exitCode: 1, lastLine: "boom", details: "a\nb\nboom"),
        ]
        for error in all { #expect(error.errorDescription?.contains("\n") == false) }
    }
}
