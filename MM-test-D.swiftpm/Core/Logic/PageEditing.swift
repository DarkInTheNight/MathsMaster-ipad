import Foundation

/// Pure edits on a document's page list (design plan §3.5, §3.7). The editor applies these and
/// moves ink files to match; keeping them here means they can be unit-tested.
extension DocumentManifest {
    /// The template a new page inserted at `index` should get: the nearest template page's
    /// (so a notebook keeps its paper), else the answer sheet for example sheets, else the default.
    func templateForNewPage(near index: Int) -> (PageTemplate, PageSize) {
        let order = pages.indices.sorted { abs($0 - index) < abs($1 - index) }
        for i in order {
            if case .template(let template) = pages[i].background {
                return (template, pages[i].size)
            }
        }
        return (kind == .exampleSheet ? .answerSheet : .default, .a4Portrait)
    }

    /// Inserts a template page at `index` (clamped). Returns the new page.
    @discardableResult
    mutating func insertTemplatePage(at index: Int, template: PageTemplate? = nil, question: Int? = nil) -> Page {
        let i = min(max(0, index), pages.count)
        let (nearTemplate, nearSize) = templateForNewPage(near: i)
        let page = Page(size: nearSize, background: .template(template ?? nearTemplate), question: question)
        pages.insert(page, at: i)
        return page
    }

    /// Copies the page at `index` (same background and question) right after it, with a new ID.
    /// Returns the new page; the caller copies the ink.
    @discardableResult
    mutating func duplicatePage(at index: Int) -> Page? {
        guard pages.indices.contains(index) else { return nil }
        var copy = pages[index]
        copy.id = UUID()
        pages.insert(copy, at: index + 1)
        return copy
    }

    /// Removes a page. A document always keeps at least one page, so removing the last one fails.
    @discardableResult
    mutating func removePage(at index: Int) -> Page? {
        guard pages.indices.contains(index), pages.count > 1 else { return nil }
        bookmarks.removeAll { $0.pageID == pages[index].id }
        return pages.remove(at: index)
    }

    /// Moves the pages at `offsets` so they land before `destination` (SwiftUI `onMove` semantics).
    mutating func movePages(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.filter { pages.indices.contains($0) }.map { pages[$0] }
        guard !moving.isEmpty else { return }
        let before = offsets.filter { $0 < destination }.count
        for i in offsets.sorted(by: >) where pages.indices.contains(i) { pages.remove(at: i) }
        let target = min(max(0, destination - before), pages.count)
        pages.insert(contentsOf: moving, at: target)
    }

    /// Changes the template of the given pages (PDF pages are left alone).
    mutating func setTemplate(_ template: PageTemplate, at indices: [Int]) {
        for i in indices where pages.indices.contains(i) {
            if case .template = pages[i].background {
                pages[i].background = .template(template)
            }
        }
    }

    // MARK: Example sheets

    /// The first answer page tagged with question `number`.
    func firstPageIndex(forQuestion number: Int) -> Int? {
        pages.firstIndex { $0.question == number }
    }

    /// Adds an answer page for question `number`, after the pages for earlier questions,
    /// so answers stay in question order. Returns its index.
    @discardableResult
    mutating func addAnswerPage(forQuestion number: Int) -> Int {
        let index = (pages.lastIndex { ($0.question ?? 0) <= number }).map { $0 + 1 } ?? 0
        insertTemplatePage(at: index, template: kind == .exampleSheet ? .answerSheet : nil, question: number)
        return index
    }

    /// The question a page answers: its own tag, else the nearest tagged page before it.
    func effectiveQuestion(ofPageAt index: Int) -> Int? {
        guard pages.indices.contains(index) else { return nil }
        for i in stride(from: index, through: 0, by: -1) {
            if let q = pages[i].question { return q }
        }
        return nil
    }

    /// Page indices for a hand-in: answers in question order, pages for the same question in
    /// their current order; untagged pages at the start stay at the start.
    func handInPageOrder() -> [Int] {
        pages.indices
            .map { (index: $0, question: effectiveQuestion(ofPageAt: $0) ?? 0) }
            .sorted { ($0.question, $0.index) < ($1.question, $1.index) }
            .map(\.index)
    }
}

extension ExampleSheetInfo {
    func status(of number: Int) -> QuestionStatus {
        questions.first { $0.number == number }?.status ?? .notStarted
    }

    mutating func setStatus(_ status: QuestionStatus, for number: Int) {
        if let i = questions.firstIndex(where: { $0.number == number }) {
            questions[i].status = status
        } else {
            questions.append(SheetQuestion(number: number, status: status))
            questions.sort { $0.number < $1.number }
        }
    }

    /// Makes sure questions 1…count exist (keeping existing statuses).
    mutating func ensureQuestions(count: Int) {
        guard count > 0 else { return }
        for n in 1...count where !questions.contains(where: { $0.number == n }) {
            questions.append(SheetQuestion(number: n))
        }
        questions.sort { $0.number < $1.number }
    }
}

extension QuestionStatus {
    var displayName: String {
        switch self {
        case .notStarted: return "Not started"
        case .attempted: return "Attempted"
        case .done: return "Done"
        case .stuck: return "Stuck"
        }
    }
}

/// Finds where questions start in an example sheet's text (design plan §3.7): `1.`, `2.`, `3.`
/// at line starts, accepted only in sequence so "3.5" in the middle of a line or a stray
/// "12." doesn't count.
enum QuestionDetector {
    struct Start: Equatable, Sendable {
        var number: Int
        var page: Int
        /// UTF-16 offset of the number in that page's text (for `PDFPage.selection(for:)`).
        var offset: Int
        /// UTF-16 length of the number and the dot.
        var length: Int
    }

    static func detect(pageTexts: [String]) -> [Start] {
        var result: [Start] = []
        var expected = 1
        for (pageIndex, text) in pageTexts.enumerated() {
            let ns = text as NSString
            var lineStart = 0
            while lineStart < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                if let start = questionNumber(in: ns, line: lineRange), start.number == expected {
                    result.append(Start(number: start.number, page: pageIndex, offset: start.offset, length: start.length))
                    expected += 1
                }
                lineStart = NSMaxRange(lineRange)
                if lineRange.length == 0 { break }
            }
        }
        return result
    }

    /// "  12. Text" → (12, offset of "1", 3). Also accepts "12 ." and "12)" is ignored on purpose.
    private static func questionNumber(in text: NSString, line: NSRange) -> (number: Int, offset: Int, length: Int)? {
        var i = line.location
        let end = NSMaxRange(line)
        func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0xA0 }
        func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }
        while i < end, isSpace(text.character(at: i)) { i += 1 }
        let digitsStart = i
        var value = 0
        while i < end, isDigit(text.character(at: i)), i - digitsStart < 2 {
            value = value * 10 + Int(text.character(at: i) - 0x30)
            i += 1
        }
        guard i > digitsStart, i < end, !isDigit(text.character(at: i)) else { return nil }
        guard text.character(at: i) == 0x2E else { return nil }  // "."
        let dot = i
        i += 1
        // The dot must end the token: "1.5" is a number, not a question.
        if i < end, isDigit(text.character(at: i)) { return nil }
        return (value, digitsStart, dot - digitsStart + 1)
    }
}
