import Foundation
import Testing
@testable import ConvertKit

@Suite struct ActionCatalogTests {
    private func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }
    private func kinds(_ files: [URL], locator: ToolLocator = ToolLocator(searchPaths: [])) -> [ActionKind] {
        ActionCatalog.entries(for: files, locator: locator).map(\.kind)
    }

    @Test func nothingSelected() {
        #expect(ActionCatalog.entries(for: []).isEmpty)
    }

    @Test func pdfsGetPDFToolsFirstAndZipLast() {
        let many = kinds(urls("a.pdf", "b.pdf"))
        #expect(Array(many.prefix(5)) == [.pdfMerge, .pdfSplit, .pdfExtract, .pdfDelete, .pdfRotate])
        #expect(many.contains(.convert(.png)))
        #expect(many.last == .zip)
        #expect(!kinds(urls("a.pdf")).contains(.pdfMerge))
    }

    @Test func imagesGetConvertTargets() {
        let found = kinds(urls("a.heic", "b.png"))
        #expect(found.contains(.convert(.jpg)))
        #expect(found.contains(.convert(.pdf)))
        #expect(!found.contains(.pdfSplit))
    }

    @Test func mixedSelectionOffersCommonTargetsOnly() {
        let found = kinds(urls("a.pdf", "b.png"))
        #expect(found.contains(.convert(.png)))
        #expect(!found.contains(.convert(.txt)))
        #expect(!found.contains(.pdfMerge))
    }

    @Test func videoGetsMediaTools() {
        let one = kinds(urls("a.mov"))
        #expect(one.contains(.mediaCompress) && one.contains(.mediaTrim) && one.contains(.mediaGif) && one.contains(.mediaAudio))
        #expect(!kinds(urls("a.mov", "b.mp4")).contains(.mediaTrim))
    }

    @Test func archivesGetExtract() {
        #expect(kinds(urls("a.zip")).contains(.extract))
        #expect(kinds(urls("a.zip", "b.txt")).contains(.extract) == false)
    }

    @Test func unknownFilesCanOnlyBeZipped() {
        #expect(kinds(urls("a.qqqq")) == [.zip])
    }

    @Test func availabilityReflectsInstalledTools() {
        let entries = ActionCatalog.entries(for: urls("a.png"), locator: ToolLocator(searchPaths: []))
        #expect(entries.first { $0.kind == .convert(.webp) }?.missing == [MissingTool(tool: .cwebp)])
        #expect(entries.first { $0.kind == .convert(.jpg) }?.isAvailable == true)
        let video = ActionCatalog.entries(for: urls("a.mov"), locator: ToolLocator(searchPaths: []))
        #expect(video.first { $0.kind == .mediaGif }?.missing == [MissingTool(tool: .ffmpeg)])
        let rar = ActionCatalog.entries(for: urls("a.rar"), locator: ToolLocator(searchPaths: []))
        #expect(rar.first { $0.kind == .extract }?.missing == [MissingTool(tool: .unar)])
        #expect(ActionCatalog.entries(for: urls("a.zip"), locator: ToolLocator(searchPaths: []))
            .first { $0.kind == .extract }?.isAvailable == true)
    }

    @Test func combinedInstallCommand() {
        let missing = [MissingTool(tool: .ffmpeg), MissingTool(tool: .ffprobe), MissingTool(tool: .cwebp)]
        #expect(ActionCatalog.installCommand(for: missing) == "brew install ffmpeg webp")
    }

    @Test func titlesAndExplanations() {
        #expect(ActionKind.convert(.jpg).title == "Convert to JPG")
        #expect(ActionKind.pdfMerge.title == "Merge PDFs")
        let text = MissingTool(tool: .ffmpeg).explanation
        #expect(text.contains("ffmpeg") && text.contains("brew install ffmpeg") && text.contains("video"))
    }
}
