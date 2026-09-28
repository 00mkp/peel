import ArgumentParser
import ConvertKit
import Foundation

struct MediaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "media",
        abstract: "Trim, compress, pull audio from, or GIF-ify video (needs ffmpeg).",
        subcommands: [Trim.self, Compress.self, Audio.self, Gif.self])
}

extension MediaCommand {
    struct Trim: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Cut a clip between two times (fast, no re-encode).")
        @Argument(help: "Video or audio file.") var file: String
        @Option(help: "Start: SS, MM:SS or HH:MM:SS(.ms).") var from: String
        @Option(help: "End time.") var to: String
        @OptionGroup var options: OutputOptions

        func validate() throws {
            guard let start = MediaBackend.parseTime(from), let end = MediaBackend.parseTime(to) else {
                throw ValidationError("times look like 90, 1:30 or 01:02:03.5")
            }
            guard end > start else { throw ValidationError("--to must be after --from") }
        }

        func run() throws {
            guard let start = MediaBackend.parseTime(from), let end = MediaBackend.parseTime(to) else { return }
            try runSingle(file, suffix: "-trimmed", options: options) {
                try MediaBackend.trim($0, to: $1, from: start, until: end)
            }
        }
    }

    struct Compress: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a video smaller (H.264).")
        @Argument(help: "Video file.") var file: String
        @Option(help: "Target size such as 25MB (two-pass; needs ffprobe).") var size: String?
        @OptionGroup var options: OutputOptions

        func validate() throws {
            if let size, MediaBackend.parseSize(size) == nil {
                throw ValidationError("--size looks like 25MB, 500KB or 1.5GB")
            }
        }

        func run() throws {
            let source = FileFormat(url: Paths.url(file))
            let ext = (source == .mov || source == .mkv) ? source!.fileExtension : "mp4"
            let bytes = size.flatMap(MediaBackend.parseSize)
            try runSingle(file, suffix: "-compressed", ext: ext, options: options) {
                try MediaBackend.compress($0, to: $1, targetBytes: bytes)
            }
        }
    }

    struct Audio: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Extract the audio track.")
        @Argument(help: "Video file.") var file: String
        @Option(help: "Audio format: mp3, m4a, wav, flac, ogg, opus, aiff, wma.") var to: FileFormat
        @OptionGroup var options: OutputOptions

        func validate() throws {
            guard to.category == .audio else { throw ValidationError("--to must be an audio format (mp3, m4a, wav, …)") }
        }

        func run() throws {
            try runSingle(file, suffix: "", ext: to.fileExtension, options: options) {
                try MediaBackend.convert($0, to: $1, format: to)
            }
        }
    }

    struct Gif: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn a video into an animated GIF.")
        @Argument(help: "Video file.") var file: String
        @Option(help: "Frames per second.") var fps = 12
        @Option(help: "Width in pixels (height keeps the aspect ratio).") var width = 480
        @OptionGroup var options: OutputOptions

        func validate() throws {
            guard (1...50).contains(fps) else { throw ValidationError("--fps must be 1-50") }
            guard (16...3840).contains(width) else { throw ValidationError("--width must be 16-3840") }
        }

        func run() throws {
            try runSingle(file, suffix: "", ext: "gif", options: options) {
                try MediaBackend.gif($0, to: $1, fps: fps, width: width)
            }
        }
    }
}
