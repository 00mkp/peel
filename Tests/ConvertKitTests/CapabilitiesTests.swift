import Testing
@testable import ConvertKit

@Suite struct CapabilitiesTests {
    @Test func imageTargets() {
        let targets = Capabilities.targets(for: .heic)
        for expected: FileFormat in [.jpg, .png, .heic, .webp, .avif, .pdf] { #expect(targets.contains(expected)) }
        #expect(!targets.contains(.svg))
    }

    @Test func toolsAreRecorded() {
        #expect(Capabilities.conversion(from: .heic, to: .jpg)?.tools == [])
        #expect(Capabilities.conversion(from: .heic, to: .webp)?.tools == [.cwebp])
        #expect(Capabilities.conversion(from: .svg, to: .webp)?.tools == [.rsvgConvert, .cwebp])
        #expect(Capabilities.conversion(from: .mov, to: .mp4)?.tools == [.ffmpeg])
    }

    @Test func backends() {
        #expect(Capabilities.conversion(from: .pdf, to: .png)?.backend == .pdf)
        #expect(Capabilities.conversion(from: .png, to: .pdf)?.backend == .pdf)
        #expect(Capabilities.conversion(from: .txt, to: .pdf)?.backend == .pdf)
        #expect(Capabilities.conversion(from: .srt, to: .vtt)?.backend == .subtitle)
        #expect(Capabilities.conversion(from: .mp4, to: .mp3)?.backend == .media)
        #expect(Capabilities.conversion(from: .mp4, to: .gif)?.backend == .media)
        #expect(Capabilities.conversion(from: .gif, to: .mp4)?.backend == .media)
        #expect(Capabilities.conversion(from: .gif, to: .png)?.backend == .image)
    }

    @Test func unsupportedPairsAreNil() {
        #expect(Capabilities.conversion(from: .zip, to: .pdf) == nil)
        #expect(Capabilities.conversion(from: .mp4, to: .mp4) == nil)
        #expect(Capabilities.conversion(from: .mp3, to: .mp4) == nil)
        #expect(Capabilities.targets(for: .rar).isEmpty)
    }

    @Test func imagesMayConvertToTheirOwnFormat() {
        // Used for resizing/recompressing: `peel convert big.jpg --to jpg --width 800`
        #expect(Capabilities.conversion(from: .jpg, to: .jpg) != nil)
    }

    @Test func missingToolsUsesLocator() {
        let conversion = Capabilities.conversion(from: .svg, to: .avif)!
        #expect(Capabilities.missingTools(for: conversion, locator: ToolLocator(searchPaths: []))
            == [.rsvgConvert, .avifenc])
    }
}
