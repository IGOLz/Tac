import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
import Vision
@testable import Tac

@Test func defaultShortcutDisplay() {
    #expect(HotKey.screenTextDefault.keys == ["⌃", "⇧", "⌘", "T"])
    #expect(HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | cmdKey)).displayString == "⌥⌘Space")
    #expect(HotKey(keyCode: UInt32(kVK_F5), modifiers: 0).displayString == "F5")
}

@Test func shortcutsMustNotGetInTheWayOfTyping() {
    #expect(HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: 0).validationError != nil)
    #expect(HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(shiftKey)).validationError != nil)
    #expect(HotKey(keyCode: UInt32(kVK_F5), modifiers: 0).validationError == nil)
    #expect(HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey)).validationError == nil)
    #expect(HotKey.screenTextDefault.validationError == nil)
}

@Test func shortcutRoundTripsThroughDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "TacTests.\(UUID().uuidString)"))
    #expect(HotKey.load("shortcut", from: defaults) == nil)
    let key = HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
    key.save("shortcut", to: defaults)
    #expect(HotKey.load("shortcut", from: defaults) == key)
}

/// One line per entry: (words, x, y). Each word is 40 pt wide with 10 pt gaps, lines 20 pt tall.
private func layout(_ rows: [([String], CGFloat, CGFloat)]) -> TextLayout {
    TextLayout(lines: rows.map { words, x, y in
        TextLine(words: words.enumerated().map { index, text in
            TextWord(text: text, rect: CGRect(x: x + CGFloat(index) * 50, y: y, width: 40, height: 20))
        })
    })
}

// Like the reported page: a title column on the left and "Popular Posts" in a sidebar at the same height.
private let page = layout([
    (["HOW", "TO"], 100, 500),
    (["Popular", "Posts"], 600, 480),
    (["CREATE"], 100, 400),
    (["November", "2026"], 600, 380),
    (["IMAGE"], 110, 300),
    (["INSIDE"], 100, 200),
])

@Test func linesAreInReadingOrder() {
    #expect(page.lines.map { $0.words[0].text } == ["HOW", "Popular", "CREATE", "November", "IMAGE", "INSIDE"])
}

@Test func pointerNearTextFindsTheWord() {
    // 8 pt left of "HOW" still counts; 20 pt away does not.
    #expect(page.word(near: CGPoint(x: 92, y: 510)) == TextPosition(line: 0, word: 0))
    #expect(page.word(near: CGPoint(x: 80, y: 510)) == nil)
    #expect(page.word(near: CGPoint(x: 165, y: 524)) == TextPosition(line: 0, word: 1))
}

@Test func dragDownSelectsOnlyTheStartingColumn() {
    let anchor = page.word(near: CGPoint(x: 105, y: 510))!
    let selection = page.selection(from: anchor, start: CGPoint(x: 105, y: 510), to: CGPoint(x: 130, y: 210))
    #expect(selection.text(in: page.lines) == "HOW TO\nCREATE\nIMAGE\nINSIDE")
}

@Test func dragWithinALineSelectsWords() {
    let anchor = page.word(near: CGPoint(x: 620, y: 490))!
    let selection = page.selection(from: anchor, start: CGPoint(x: 620, y: 490), to: CGPoint(x: 680, y: 490))
    #expect(selection.text(in: page.lines) == "Popular Posts")
    let backwards = page.selection(from: TextPosition(line: 1, word: 1), start: CGPoint(x: 680, y: 490), to: CGPoint(x: 600, y: 490))
    #expect(backwards.text(in: page.lines) == "Popular Posts")
}

@Test func dragUpSelectsInReadingOrder() {
    let anchor = page.word(near: CGPoint(x: 120, y: 410))!
    let selection = page.selection(from: anchor, start: CGPoint(x: 120, y: 410), to: CGPoint(x: 140, y: 510))
    #expect(selection.text(in: page.lines) == "HOW TO\nCREATE")
}

@Test func readingOrderIsDeterministicForStaggeredLines() {
    // Each pair is within half a line height, but the first and last are not: still one stable order.
    let staggered = layout([(["A"], 0, 100), (["B"], 100, 104), (["C"], 200, 108)])
    #expect(staggered.lines.map { $0.words[0].text } == ["C", "A", "B"] || staggered.lines.map { $0.words[0].text } == ["A", "B", "C"])
    #expect(layout([(["C"], 200, 108), (["A"], 0, 100), (["B"], 100, 104)]).lines == staggered.lines)
}

@Test func indentedLinesStayInTheParagraph() {
    let paragraph = layout([
        (["Short"], 100, 500),
        (["indented", "continuation"], 160, 475),
        (["Sidebar"], 600, 475),
    ])
    let anchor = paragraph.word(near: CGPoint(x: 110, y: 510))!
    let selection = paragraph.selection(from: anchor, start: CGPoint(x: 110, y: 510), to: CGPoint(x: 245, y: 480))
    #expect(selection.text(in: paragraph.lines) == "Short\nindented continuation")
}

@Test func highlightCoversSelectedWordsInAnyDirection() {
    // Logical order right to left, like Arabic or Hebrew.
    let rtl = TextLayout(lines: [TextLine(words: [
        TextWord(text: "first", rect: CGRect(x: 200, y: 0, width: 40, height: 20)),
        TextWord(text: "second", rect: CGRect(x: 100, y: 0, width: 40, height: 20)),
    ])])
    #expect(rtl.rects(for: TextSelection(ranges: [(0, 0...1)])) == [CGRect(x: 100, y: 0, width: 140, height: 20)])
}

// The warm-up image must contain real text, or Vision may skip loading its recognition models.
@Test func warmUpImageIsReadByBothRecognitionLevels() throws {
    let image = try #require(TextLayout.sampleImage())
    let size = CGSize(width: image.width, height: image.height)
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
        let layout = try TextLayout.recognize(image, size: size, level: level)
        let text = layout.lines.flatMap(\.words).map(\.text).joined(separator: " ")
        #expect(text.localizedCaseInsensitiveContains("reads"), "level \(level.rawValue) read: \(text)")
    }
}
