import Foundation

/// One problem found by the card editor's live lint (design plan §4.4, guidelines §8.2).
struct CardLintIssue: Hashable, Identifiable, Sendable {
    enum Field: String, Hashable, Sendable { case front, back }
    enum Kind: String, Hashable, Sendable {
        case dollar, markdownBold, unbalancedInline, unbalancedDisplay, unbalancedEnvironment
        case unbalancedBraces, unbalancedTag, rawLessThan, contextualNumbering, crossReference
    }

    var field: Field
    var kind: Kind
    var message: String
    /// The whole field with the problem fixed, when a one-tap fix exists.
    var fixed: String?

    var id: String { "\(field.rawValue)-\(kind.rawValue)-\(message)" }
}

/// Pure text helpers for card fields: lint, one-tap fixes and section headers.
enum CardText {
    static let allowedTags: Set<String> = [
        "b", "i", "u", "em", "strong", "br", "ul", "ol", "li", "div", "span", "p", "sub", "sup", "hr", "img",
        "table", "tr", "td", "th", "tbody", "thead",
        "svg", "g", "path", "line", "polyline", "polygon", "rect", "circle", "ellipse", "text", "tspan",
        "defs", "marker", "use", "title", "foreignobject", "lineargradient", "radialgradient", "stop",
    ]

    // MARK: Lint

    static func lint(front: String, back: String) -> [CardLintIssue] {
        lint(front, field: .front) + lint(back, field: .back)
    }

    static func lint(_ text: String, field: CardLintIssue.Field) -> [CardLintIssue] {
        var issues: [CardLintIssue] = []
        func add(_ kind: CardLintIssue.Kind, _ message: String, fixed: String? = nil) {
            issues.append(CardLintIssue(field: field, kind: kind, message: message, fixed: fixed))
        }

        if containsUnescapedDollar(text) {
            let fixed = fixDollars(text)
            add(.dollar, "Uses $ for maths. Use \\( … \\) inline and \\[ … \\] for display.",
                fixed: containsUnescapedDollar(fixed) ? nil : fixed)
        }
        if text.contains("**") {
            add(.markdownBold, "Markdown ** isn't rendered. Use <b>…</b>.", fixed: fixMarkdownBold(text))
        }
        let inlineOpen = count(of: "\\(", in: text), inlineClose = count(of: "\\)", in: text)
        if inlineOpen != inlineClose {
            add(.unbalancedInline, "Unbalanced \\( \\): \(inlineOpen) opened, \(inlineClose) closed.")
        }
        let displayOpen = count(of: "\\[", in: text), displayClose = count(of: "\\]", in: text)
        if displayOpen != displayClose {
            add(.unbalancedDisplay, "Unbalanced \\[ \\]: \(displayOpen) opened, \(displayClose) closed.")
        }
        for env in unbalancedEnvironments(text) {
            add(.unbalancedEnvironment, "\\begin{\(env)} and \\end{\(env)} don't match.")
        }
        let braces = braceBalance(text)
        if braces != 0 {
            add(.unbalancedBraces, braces > 0 ? "\(braces) unclosed {." : "\(-braces) extra }.")
        }
        for tag in unbalancedTags(text) {
            add(.unbalancedTag, "<\(tag)> isn't closed properly.")
        }
        if hasRawLessThan(text) {
            add(.rawLessThan, "A raw < can break the card. Write &lt; (or \\lt in maths).", fixed: escapeRawLessThan(text))
        }
        for match in matches(of: #"\b(Theorem|Lemma|Proposition|Corollary|Definition|Example|Exercise|Section|Chapter)\s+\d+(\.\d+)*"#, in: text) {
            add(.contextualNumbering, "“\(match)” refers to the notes' numbering. Name the result instead.")
        }
        for match in matches(of: #"(?i)\b(equation|eq\.)\s*\(\d+(\.\d+)*\)"#, in: text) {
            add(.contextualNumbering, "“\(match)” refers to the notes' numbering. Restate it instead.")
        }
        for match in matches(of: #"(?i)\b(previous|next|earlier|last|other|above)\s+card"#, in: text) {
            add(.crossReference, "“\(match)”: cards must stand alone.")
        }
        return issues
    }

    static func containsUnescapedDollar(_ text: String) -> Bool {
        var previous: Character = " "
        for ch in text {
            if ch == "$" && previous != "\\" { return true }
            previous = ch
        }
        return false
    }

    /// `$$…$$` → `\[…\]`, `$…$` → `\(…\)`; `\$` stays. Unpaired `$` are left alone.
    static func fixDollars(_ text: String) -> String {
        var s = replacePairs(in: text, delimiter: "$$", open: "\\[", close: "\\]")
        s = replacePairs(in: s, delimiter: "$", open: "\\(", close: "\\)")
        return s
    }

    private static func replacePairs(in text: String, delimiter: String, open: String, close: String) -> String {
        let chars = Array(text)
        let d = Array(delimiter)
        var positions: [Int] = []
        var i = 0
        while i <= chars.count - d.count {
            if Array(chars[i..<(i + d.count)]) == d && (i == 0 || chars[i - 1] != "\\") {
                // For single $, skip ones that are part of $$ (already replaced) — none remain after the first pass.
                positions.append(i)
                i += d.count
            } else {
                i += 1
            }
        }
        guard positions.count >= 2 else { return text }
        let usable = positions.count - positions.count % 2
        var result = ""
        var cursor = 0
        for (n, pos) in positions.prefix(usable).enumerated() {
            result += String(chars[cursor..<pos])
            result += n % 2 == 0 ? open : close
            cursor = pos + d.count
        }
        result += String(chars[cursor...])
        return result
    }

    static func fixMarkdownBold(_ text: String) -> String {
        let parts = text.components(separatedBy: "**")
        guard parts.count >= 3 else { return text }
        var result = parts[0]
        let pairs = (parts.count - 1) / 2
        for k in 0..<pairs {
            result += "<b>" + parts[2 * k + 1] + "</b>" + parts[2 * k + 2]
        }
        if (parts.count - 1) % 2 == 1 { result += "**" + parts[parts.count - 1] }
        return result
    }

    static func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    static func unbalancedEnvironments(_ text: String) -> [String] {
        var stack: [String] = []
        var bad: [String] = []
        for m in matchGroups(of: #"\\(begin|end)\{([^}]*)\}"#, in: text) {
            if m[1] == "begin" {
                stack.append(m[2])
            } else if stack.last == m[2] {
                stack.removeLast()
            } else {
                bad.append(m[2])
            }
        }
        return Array(Set(bad + stack)).sorted()
    }

    /// `{` minus `}`, ignoring escaped `\{` and `\}`.
    static func braceBalance(_ text: String) -> Int {
        var balance = 0
        var previous: Character = " "
        for ch in text {
            if previous != "\\" {
                if ch == "{" { balance += 1 } else if ch == "}" { balance -= 1 }
            }
            previous = (previous == "\\" && ch == "\\") ? " " : ch
        }
        return balance
    }

    /// Paired tags of the card subset (`b`, `i`, `ul`, `li`, …) that are not properly nested.
    static func unbalancedTags(_ text: String) -> [String] {
        let paired: Set<String> = ["b", "i", "u", "em", "strong", "ul", "ol", "li", "sub", "sup", "svg"]
        var stack: [String] = []
        var bad = Set<String>()
        for m in matchGroups(of: #"<(/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*?(/?)>"#, in: text) {
            let name = m[2].lowercased()
            guard paired.contains(name), m[3] != "/" else { continue }
            if m[1].isEmpty {
                stack.append(name)
            } else if let index = stack.lastIndex(of: name) {
                if index != stack.count - 1 { bad.formUnion(stack[(index + 1)...]) }
                stack.removeSubrange(index...)
            } else {
                bad.insert(name)
            }
        }
        // Inside an <svg>, other tags are not ours to check.
        bad.formUnion(stack)
        return bad.sorted()
    }

    /// A `<` that doesn't start a known tag, a closing tag or a comment.
    static func hasRawLessThan(_ text: String) -> Bool {
        rawLessThanOffsets(text).isEmpty == false
    }

    static func escapeRawLessThan(_ text: String) -> String {
        var chars = Array(text)
        for offset in rawLessThanOffsets(text).reversed() {
            chars.replaceSubrange(offset...offset, with: Array("&lt;"))
        }
        return String(chars)
    }

    private static func rawLessThanOffsets(_ text: String) -> [Int] {
        let chars = Array(text)
        var offsets: [Int] = []
        for (i, ch) in chars.enumerated() where ch == "<" {
            var j = i + 1
            if j < chars.count && (chars[j] == "/" || chars[j] == "!") { j += 1 }
            var name = ""
            while j < chars.count && (chars[j].isLetter || chars[j].isNumber) {
                name.append(chars[j]); j += 1
            }
            let terminatesName = j < chars.count && (chars[j] == ">" || chars[j] == " " || chars[j] == "/" || chars[j] == "\n")
            let isComment = i + 3 < chars.count && String(chars[i...(i + 3)]) == "<!--"
            if isComment { continue }
            if !name.isEmpty && terminatesName && allowedTags.contains(name.lowercased()) { continue }
            offsets.append(i)
        }
        return offsets
    }

    // MARK: Sections

    /// The guidelines' bold section headers, e.g. `<b>1. Motivation:</b>` → "Motivation".
    /// The card web view numbers the same `<b>` elements, so chip `n` scrolls to header `n`.
    static func sections(in html: String) -> [String] {
        matchGroups(of: #"<b>([^<]{1,60}?):\s*</b>"#, in: html).map { m in
            var title = m[1].trimmingCharacters(in: .whitespaces)
            if let r = title.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
                title.removeSubrange(r)
            }
            return title
        }
    }

    // MARK: Plain text

    /// A one-line preview for lists: tags dropped, entities and maths delimiters simplified.
    static func plainPreview(_ html: String, limit: Int = 140) -> String {
        var s = html.replacingOccurrences(of: #"<svg[\s\S]*?</svg>"#, with: " [diagram] ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&nbsp;", " "), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        for delimiter in ["\\(", "\\)", "\\[", "\\]"] { s = s.replacingOccurrences(of: delimiter, with: "") }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }

    // MARK: Regex helpers

    private static func matches(of pattern: String, in text: String) -> [String] {
        matchGroups(of: pattern, in: text).map { $0[0] }
    }

    private static func matchGroups(of pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}

extension CardText {
    /// Strips everything outside the card subset: scripts, styles, iframes, event handlers and `javascript:` URLs.
    static func sanitize(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "iframe", "object", "embed", "link", "meta"] {
            s = s.replacingOccurrences(of: "<\(tag)[\\s\\S]*?</\(tag)\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: "<\(tag)\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"\s+on[a-zA-Z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)(href|src|xlink:href)\s*=\s*("|')\s*javascript:[^"']*("|')"#, with: "", options: .regularExpression)
        return s
    }
}
