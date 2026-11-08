import CoreGraphics
import CoreText
import Foundation
@preconcurrency import Vision

/// A recognized word with its box in view coordinates (origin bottom-left, like AppKit).
struct TextWord: Equatable, Sendable {
    let text: String
    let rect: CGRect
}

/// A recognized line: its words in reading order and the box around them.
struct TextLine: Equatable, Sendable {
    let words: [TextWord]
    let rect: CGRect

    init(words: [TextWord]) {
        self.words = words
        rect = words.dropFirst().reduce(words.first?.rect ?? .null) { $0.union($1.rect) }
    }
}

/// Where a selection starts or ends: a word of a line.
struct TextPosition: Equatable, Sendable {
    let line: Int
    let word: Int
}

/// Selected words per line, in reading order.
struct TextSelection: Equatable, Sendable {
    var ranges: [(line: Int, words: ClosedRange<Int>)]

    static func == (a: TextSelection, b: TextSelection) -> Bool {
        a.ranges.map(\.line) == b.ranges.map(\.line) && a.ranges.map(\.words) == b.ranges.map(\.words)
    }

    var isEmpty: Bool { ranges.isEmpty }

    func text(in lines: [TextLine]) -> String {
        ranges.map { range in
            lines[range.line].words[range.words].map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }
}

/// Geometry of the text on one screen: hit testing near words and column-aware selection.
struct TextLayout: Sendable {
    /// How far from a word the pointer still counts as on it.
    static let tolerance: CGFloat = 12

    /// Lines top to bottom, then left to right.
    let lines: [TextLine]
    /// Text block (paragraph or column) of each line, by index.
    let blocks: [Int]

    init(lines: [TextLine]) {
        self.lines = Self.readingOrder(lines.filter { !$0.words.isEmpty })
        blocks = Self.blocks(self.lines)
    }

    /// Rows top to bottom, then lines left to right in each row. A line joins the current row when
    /// its centre is within half the row's first line height, which keeps the order deterministic.
    private static func readingOrder(_ lines: [TextLine]) -> [TextLine] {
        let byTop = lines.sorted { $0.rect.midY != $1.rect.midY ? $0.rect.midY > $1.rect.midY : $0.rect.minX < $1.rect.minX }
        var rows: [[TextLine]] = []
        for line in byTop {
            if let first = rows.last?.first, first.rect.midY - line.rect.midY < first.rect.height / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }

    /// Groups lines into blocks: lines that overlap horizontally (allowing for indents) and are
    /// close vertically belong together, so a column next to them stays separate.
    private static func blocks(_ lines: [TextLine]) -> [Int] {
        var parent = Array(lines.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in lines.indices {
            for j in lines.indices where j > i {
                let a = lines[i].rect, b = lines[j].rect
                let height = max(a.height, b.height)
                let horizontalGap = max(a.minX - b.maxX, b.minX - a.maxX, 0)
                let verticalGap = max(a.minY - b.maxY, b.minY - a.maxY, 0)
                let sameRow = abs(a.midY - b.midY) < min(a.height, b.height) / 2
                if !sameRow, horizontalGap <= height, verticalGap <= height * 1.5 { parent[root(j)] = root(i) }
            }
        }
        return lines.indices.map(root)
    }

    var isEmpty: Bool { lines.isEmpty }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The word nearest to `point`, if it is within the tolerance.
    func word(near point: CGPoint, tolerance: CGFloat = TextLayout.tolerance) -> TextPosition? {
        var best: (position: TextPosition, distance: CGFloat)?
        for (lineIndex, line) in lines.enumerated() where Self.distance(point, line.rect) <= tolerance {
            for (wordIndex, word) in line.words.enumerated() {
                let d = Self.distance(point, word.rect)
                if d <= tolerance, d < best?.distance ?? .infinity {
                    best = (TextPosition(line: lineIndex, word: wordIndex), d)
                }
            }
        }
        return best?.position
    }

    /// The word of a line closest to `x`.
    private func word(in line: Int, at x: CGFloat) -> Int {
        let words = lines[line].words
        return words.indices.min { abs(x - min(max(x, words[$0].rect.minX), words[$0].rect.maxX))
            < abs(x - min(max(x, words[$1].rect.minX), words[$1].rect.maxX)) } ?? 0
    }

    /// Selection from `anchor` to the pointer. Only the anchor's block and lines under the dragged
    /// span take part, so a sidebar beside the text at the same height is left out unless the
    /// drag reaches across to it.
    func selection(from anchor: TextPosition, start: CGPoint, to point: CGPoint) -> TextSelection {
        let span = (min(start.x, point.x), max(start.x, point.x))
        let candidates = lines.indices.filter { index in
            let rect = lines[index].rect
            return blocks[index] == blocks[anchor.line] || (rect.maxX >= span.0 && rect.minX <= span.1)
        }
        // The line the pointer is on, or the closest one vertically within the column.
        let focusLine = candidates.min { a, b in
            let da = verticalDistance(point.y, lines[a].rect), db = verticalDistance(point.y, lines[b].rect)
            return da != db ? da < db : abs(point.x - lines[a].rect.midX) < abs(point.x - lines[b].rect.midX)
        } ?? anchor.line
        let focus = TextPosition(line: focusLine, word: word(in: focusLine, at: point.x))

        let (first, last) = anchor.line < focus.line || (anchor.line == focus.line && anchor.word <= focus.word)
            ? (anchor, focus) : (focus, anchor)
        let top = lines[first.line].rect.midY, bottom = lines[last.line].rect.midY
        let selected = candidates.filter { index in
            let mid = lines[index].rect.midY
            return index == first.line || index == last.line || (mid <= top && mid >= bottom && index > first.line && index < last.line)
        }
        return TextSelection(ranges: selected.sorted().map { index in
            let count = lines[index].words.count
            let from = index == first.line ? first.word : 0
            let to = index == last.line ? last.word : count - 1
            return (index, min(from, to)...max(from, to))
        })
    }

    private func verticalDistance(_ y: CGFloat, _ rect: CGRect) -> CGFloat {
        max(rect.minY - y, 0, y - rect.maxY)
    }

    func word(_ position: TextPosition) -> TextSelection {
        TextSelection(ranges: [(position.line, position.word...position.word)])
    }

    /// Highlight boxes for a selection, one per line: the union of its selected words, which also
    /// holds for right-to-left text where logical order runs against x.
    func rects(for selection: TextSelection) -> [CGRect] {
        selection.ranges.map { range in
            lines[range.line].words[range.words].map(\.rect).reduce(CGRect.null) { $0.union($1) }
        }
    }

    /// An image with real text: a blank one may let Vision skip loading its recognition models.
    static func sampleImage() -> CGImage? {
        let size = CGSize(width: 640, height: 96)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
        let text = NSAttributedString(string: "Tac reads text 2026", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 24, y: 32)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        return context.makeImage()
    }

    /// Runs the whole accurate pipeline once, so its models are loaded before the first capture.
    /// The first run on a Mac can take a minute or more while macOS prepares them.
    @discardableResult
    static func warmUp() -> Bool {
        guard let image = sampleImage(),
              let layout = try? recognize(image, size: CGSize(width: image.width, height: image.height)) else { return false }
        return !layout.isEmpty
    }

    /// Recognizes text on-device with Vision. `.accurate` detects the language automatically;
    /// `.fast` loads much quicker and covers the first capture while `.accurate` is still preparing.
    static func recognize(_ image: CGImage, size: CGSize, level: VNRequestTextRecognitionLevel = .accurate) throws -> TextLayout {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = level == .accurate
        if level == .accurate { request.automaticallyDetectsLanguage = true }
        try VNImageRequestHandler(cgImage: image).perform([request])
        func viewRect(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX * size.width, y: box.minY * size.height, width: box.width * size.width, height: box.height * size.height)
        }
        let lines = (request.results ?? []).compactMap { observation -> TextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string
            let lineBox = viewRect(observation.boundingBox)
            var words: [TextWord] = []
            // Words are runs of non-space characters, so punctuation stays with its word.
            var index = string.startIndex
            while index < string.endIndex {
                guard let start = string[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let end = string[start...].firstIndex(where: \.isWhitespace) ?? string.endIndex
                let range = start..<end
                let box = (try? candidate.boundingBox(for: range)).map { viewRect($0.boundingBox) }
                    ?? Self.estimate(range, in: string, lineBox: lineBox)
                // Word boxes share the line's height so a row highlights evenly.
                words.append(TextWord(text: String(string[range]),
                                      rect: CGRect(x: box.minX, y: lineBox.minY, width: box.width, height: lineBox.height)))
                index = end
            }
            return words.isEmpty ? nil : TextLine(words: words)
        }
        return TextLayout(lines: lines)
    }

    /// Proportional position of a word when Vision can't box it.
    private static func estimate(_ range: Range<String.Index>, in string: String, lineBox: CGRect) -> CGRect {
        let total = CGFloat(max(string.count, 1))
        let start = CGFloat(string.distance(from: string.startIndex, to: range.lowerBound))
        let length = CGFloat(string.distance(from: range.lowerBound, to: range.upperBound))
        return CGRect(x: lineBox.minX + lineBox.width * start / total, y: lineBox.minY,
                      width: lineBox.width * length / total, height: lineBox.height)
    }
}
