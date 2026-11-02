import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

/// Foundation-only SRT / WebVTT parser, shared by the iOS player and the portable tests.
enum SubtitleParser {
    /// Decodes subtitle bytes: UTF-8 (with or without BOM), UTF-16, Windows-1256 (Arabic), Latin-1.
    static func decodeText(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]),
           let text = String(data: bytes, encoding: .utf16) { return text }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        // 0x80000506 is the NSStringEncoding for CFStringEncoding windowsArabic (cp1256).
        let arabic = String.Encoding(rawValue: 0x80000506)
        if let text = String(data: bytes, encoding: arabic) { return text }
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    static func parse(_ raw: String) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues = [SubtitleCue]()
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[timingIndex].components(separatedBy: "-->")
            guard sides.count == 2,
                  let start = seconds(sides[0]),
                  let endText = sides[1].split(separator: " ", omittingEmptySubsequences: true).first,
                  let end = seconds(String(endText)) else { continue }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            let text = clean(body)
            if !text.isEmpty && end >= start { cues.append(SubtitleCue(start: start, end: end, text: text)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// The cue visible at `time`, or nil. Cues must be sorted by start time (as `parse` returns).
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        guard !cues.isEmpty, time.isFinite else { return nil }
        var low = 0
        var high = cues.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return nil }
        // Look back a few entries in case an earlier cue is still on screen.
        var index = found
        while index >= 0 && found - index < 3 {
            if cues[index].end >= time { return cues[index] }
            index -= 1
        }
        return nil
    }

    private static func seconds(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let number = Double(part) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    private static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&nbsp;": " ", "&#39;": "'"]
        for (entity, plain) in entities { result = result.replacingOccurrences(of: entity, with: plain) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
