import Foundation

/// Audio/video via an ffmpeg subprocess. Argument builders are pure so they can be tested without ffmpeg.
public enum MediaBackend {
    static let base = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"]
    /// libx264 and friends reject odd frame sizes; round down to even.
    static let evenScale = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    static let audioBitrateKbps = 128

    // MARK: Parsing

    /// "90", "1:30", "01:02:03.5" → seconds.
    public static func parseTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), let seconds = Double(parts[parts.count - 1]), seconds >= 0 else { return nil }
        var total = seconds
        for (index, part) in parts.dropLast().reversed().enumerated() {
            guard let value = Int(part), value >= 0 else { return nil }
            total += Double(value) * (index == 0 ? 60 : 3600)
        }
        return total
    }

    /// "25MB", "500kb", "1.5GB", "1000" → bytes (decimal units).
    public static func parseSize(_ text: String) -> Int? {
        let upper = text.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("G", 1e9), ("M", 1e6), ("K", 1e3), ("B", 1)]
        var number = upper
        var multiplier = 1.0
        if let unit = units.first(where: { upper.hasSuffix($0.0) }) {
            number = String(upper.dropLast(unit.0.count))
            multiplier = unit.1
        }
        guard let value = Double(number.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return Int(value * multiplier)
    }

    // MARK: Argument builders

    public static func convertArguments(input: URL, output: URL, format: FileFormat) throws -> [String] {
        if format == .gif { return gifArguments(input: input, output: output, fps: 12, width: 480) }
        let codec: [String]
        switch format {
        case .mp4, .mov:
            codec = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-vf", evenScale, "-c:a", "aac", "-b:a", "192k",
                     "-movflags", "+faststart"]
        case .mkv:
            codec = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-vf", evenScale, "-c:a", "aac", "-b:a", "192k"]
        case .webm:
            codec = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-vf", evenScale, "-c:a", "libopus", "-b:a", "128k"]
        case .avi:
            codec = ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-q:a", "4"]
        case .wmv:
            codec = ["-c:v", "wmv2", "-b:v", "2M", "-c:a", "wmav2", "-b:a", "192k"]
        case .mp3: codec = ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: codec = ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav: codec = ["-vn", "-c:a", "pcm_s16le"]
        case .flac: codec = ["-vn", "-c:a", "flac"]
        case .ogg, .opus: codec = ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case .aiff: codec = ["-vn", "-c:a", "pcm_s16be"]
        case .wma: codec = ["-vn", "-c:a", "wmav2", "-b:a", "192k"]
        default:
            throw PeelError.unsupportedConversion(from: input.pathExtension.lowercased(), to: format.rawValue)
        }
        return base + ["-i", input.path] + codec + [output.path]
    }

    /// Two-step palette in one filter graph for good GIF colours.
    public static func gifArguments(input: URL, output: URL, fps: Int, width: Int) -> [String] {
        let filter = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
        return base + ["-i", input.path, "-vf", filter, "-loop", "0", output.path]
    }

    /// Stream copy (fast, no quality loss; cuts snap to keyframes).
    public static func trimArguments(input: URL, output: URL, from: Double, until: Double) -> [String] {
        base + ["-ss", String(format: "%.3f", from), "-i", input.path, "-t", String(format: "%.3f", until - from),
                "-c", "copy", "-avoid_negative_ts", "make_zero", output.path]
    }

    public static func compressArguments(input: URL, output: URL) -> [String] {
        base + ["-i", input.path, "-c:v", "libx264", "-crf", "28", "-preset", "medium", "-pix_fmt", "yuv420p",
                "-vf", evenScale, "-c:a", "aac", "-b:a", "\(audioBitrateKbps)k", "-movflags", "+faststart", output.path]
    }

    /// Video kbit/s that lands the file near `targetBytes`, leaving room for 128k audio.
    public static func videoBitrate(targetBytes: Int, duration: Double) throws -> Int {
        let totalKbps = Double(targetBytes) * 8 / 1000 / max(duration, 0.1)
        let video = Int(totalKbps) - audioBitrateKbps
        guard video >= 100 else {
            throw PeelError.invalidArgument("target size is too small for a \(Int(duration.rounded()))s video")
        }
        return video
    }

    // MARK: Operations

    public static func convert(_ input: URL, to output: URL, format: FileFormat, locator: ToolLocator = .standard) throws {
        let ffmpeg = try locator.require(.ffmpeg)
        try AtomicOutput.write(to: output) { temp in
            try ProcessRunner.runChecked(ffmpeg, try convertArguments(input: input, output: temp, format: format))
        }
    }

    public static func gif(_ input: URL, to output: URL, fps: Int = 12, width: Int = 480,
                           locator: ToolLocator = .standard) throws {
        let ffmpeg = try locator.require(.ffmpeg)
        try AtomicOutput.write(to: output) { temp in
            try ProcessRunner.runChecked(ffmpeg, gifArguments(input: input, output: temp, fps: fps, width: width))
        }
    }

    public static func trim(_ input: URL, to output: URL, from: Double, until: Double,
                            locator: ToolLocator = .standard) throws {
        guard until > from else { throw PeelError.invalidArgument("end time must be after start time") }
        let ffmpeg = try locator.require(.ffmpeg)
        try AtomicOutput.write(to: output) { temp in
            try ProcessRunner.runChecked(ffmpeg, trimArguments(input: input, output: temp, from: from, until: until))
        }
    }

    /// Without `targetBytes`: H.264 CRF 28. With it: two-pass encode aimed at that size.
    public static func compress(_ input: URL, to output: URL, targetBytes: Int?, locator: ToolLocator = .standard) throws {
        let ffmpeg = try locator.require(.ffmpeg)
        guard let targetBytes else {
            try AtomicOutput.write(to: output) { temp in
                try ProcessRunner.runChecked(ffmpeg, compressArguments(input: input, output: temp))
            }
            return
        }
        let kbps = try videoBitrate(targetBytes: targetBytes, duration: try duration(of: input, locator: locator))
        let logDir = FileManager.default.temporaryDirectory.appendingPathComponent("peel-pass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }
        let log = logDir.appendingPathComponent("pass").path
        let video = ["-c:v", "libx264", "-b:v", "\(kbps)k", "-pix_fmt", "yuv420p", "-vf", evenScale, "-passlogfile", log]
        try ProcessRunner.runChecked(ffmpeg, base + ["-i", input.path] + video + ["-pass", "1", "-an", "-f", "null", "/dev/null"])
        try AtomicOutput.write(to: output) { temp in
            try ProcessRunner.runChecked(ffmpeg, base + ["-i", input.path] + video
                + ["-pass", "2", "-c:a", "aac", "-b:a", "\(audioBitrateKbps)k", temp.path])
        }
    }

    public static func duration(of input: URL, locator: ToolLocator = .standard) throws -> Double {
        let ffprobe = try locator.require(.ffprobe)
        let result = try ProcessRunner.runChecked(ffprobe, ["-v", "error", "-show_entries", "format=duration",
                                                            "-of", "default=noprint_wrappers=1:nokey=1", input.path])
        guard let seconds = Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PeelError.unreadableFile(input)
        }
        return seconds
    }
}
