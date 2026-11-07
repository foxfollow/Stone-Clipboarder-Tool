//
//  ContentClassifier.swift
//  StoneClipboarderTool
//

import Foundation
import NaturalLanguage

/// Finds what a text contains: links, emails, phone numbers, addresses,
/// dates (NSDataDetector), code, JSON, file paths, the language, and matches
/// of the user's regex rules. On-device only; never logs the text.
///
/// The result is stored on the item (`CBItem.categoryKeys`,
/// `languageCode`), so the Quick Picker filters and counts without reading
/// any content. A detector or rule adds `key`, plus `key.full` when the
/// match covers the whole (trimmed) text.
enum ContentClassifier {
    /// Bump when detection changes, so stored results are recomputed.
    static let version = 3
    /// Only this many leading characters are examined: keeps a capture
    /// fast and bounds what a user regex has to scan.
    static let maxLength = 4000
    /// JSON is parsed whole, up to this size.
    static let maxJSONLength = 1_000_000
    static let minLanguageLetters = 20
    static let minLanguageConfidence = 0.6

    struct RegexRule: Hashable {
        let id: String
        let pattern: String
        let caseSensitive: Bool
    }

    struct Result: Equatable {
        var keys: Set<String> = []
        var language: String?
    }

    static func fullKey(_ key: String) -> String { key + ".full" }

    /// The user's regex rules, compiled once for many texts.
    struct Ruleset {
        let rules: [RegexRule]
        /// Run `ImageClassifier` on images ("Analyze images" in Settings).
        let analyzeImages: Bool
        /// Written to `CBItem.classificationStamp`; changes whenever the
        /// classifier version, any rule or `analyzeImages` changes. Never 0
        /// (= unclassified).
        let stamp: Int
        fileprivate let compiled: [(id: String, contains: NSRegularExpression, entire: NSRegularExpression)]

        init(rules: [RegexRule], analyzeImages: Bool = true) {
            let sorted = rules.sorted { $0.id < $1.id }
            self.rules = sorted
            self.analyzeImages = analyzeImages
            self.stamp = ContentClassifier.stamp(for: sorted, analyzeImages: analyzeImages)
            self.compiled = sorted.compactMap { rule in
                var options: NSRegularExpression.Options = [.anchorsMatchLines]
                if !rule.caseSensitive { options.insert(.caseInsensitive) }
                var entireOptions: NSRegularExpression.Options = []
                if !rule.caseSensitive { entireOptions.insert(.caseInsensitive) }
                guard
                    let contains = try? NSRegularExpression(pattern: rule.pattern, options: options),
                    let entire = try? NSRegularExpression(pattern: "\\A(?:\(rule.pattern))\\z", options: entireOptions)
                else { return nil }
                return (rule.id, contains, entire)
            }
        }

        static let empty = Ruleset(rules: [])
    }

    /// FNV-1a over the version and the rules: stable across launches,
    /// unlike `Hasher`.
    static func stamp(for rules: [RegexRule], analyzeImages: Bool = true) -> Int {
        var text = "v\(version)" + (analyzeImages ? "+img" : "")
        for rule in rules.sorted(by: { $0.id < $1.id }) {
            text += "\u{1}\(rule.id)\u{2}\(rule.pattern)\u{2}\(rule.caseSensitive)"
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let value = Int(truncatingIfNeeded: hash)
        return value == 0 ? 1 : value
    }

    private static let detector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue)

    static func classify(_ text: String, ruleset: Ruleset = .empty) -> Result {
        let isTruncated = text.count > maxLength
        let head = isTruncated ? String(text.prefix(maxLength)) : text
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result() }

        var keys = Set<String>()
        // A "whole text" match is meaningless when the text was cut.
        let canBeFull = !isTruncated

        func add(_ key: String, full: Bool) {
            keys.insert(key)
            if full && canBeFull { keys.insert(fullKey(key)) }
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        detector?.enumerateMatches(in: trimmed, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let full = match.range == range
            switch match.resultType {
            case .link:
                if match.url?.scheme?.lowercased() == "mailto" {
                    add(ItemCategory.BuiltIn.email.rawValue, full: full)
                } else {
                    add(ItemCategory.BuiltIn.link.rawValue, full: full)
                }
            case .phoneNumber:
                add(ItemCategory.BuiltIn.phone.rawValue, full: full)
            case .address:
                add(ItemCategory.BuiltIn.address.rawValue, full: full)
            case .date:
                add(ItemCategory.BuiltIn.date.rawValue, full: full)
            default:
                break
            }
        }

        let isJSON = looksLikeJSON(text)
        if isJSON {
            keys.insert(ItemCategory.BuiltIn.json.rawValue)
        } else if looksLikeCode(trimmed) {
            keys.insert(ItemCategory.BuiltIn.code.rawValue)
        }

        if let pathFull = pathMatch(in: trimmed) {
            add(ItemCategory.BuiltIn.path.rawValue, full: pathFull)
        }

        for rule in ruleset.compiled {
            guard rule.contains.firstMatch(in: trimmed, range: range) != nil else { continue }
            let full = rule.entire.firstMatch(in: trimmed, range: range) != nil
            add(rule.id, full: full)
        }

        // Code, data and bare paths/links have no human language.
        let isMachineText = isJSON || keys.contains(ItemCategory.BuiltIn.code.rawValue)
            || keys.contains(fullKey(ItemCategory.BuiltIn.path.rawValue))
            || keys.contains(fullKey(ItemCategory.BuiltIn.link.rawValue))
            || keys.contains(fullKey(ItemCategory.BuiltIn.email.rawValue))
        let language = isMachineText ? nil : detectLanguage(trimmed)

        return Result(keys: keys, language: language)
    }

    // MARK: - JSON

    static func looksLikeJSON(_ text: String) -> Bool {
        guard text.count <= maxJSONLength else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[",
              let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: - Code

    /// Tools whose name alone starts a command line; prose rarely begins
    /// with them.
    private static let toolCommands: Set<String> = [
        "git", "brew", "sudo", "npm", "npx", "yarn", "pnpm", "pip", "pip3", "python3", "xcodebuild",
        "xcrun", "docker", "kubectl", "curl", "wget", "ssh", "scp", "chmod", "chown", "mkdir",
        "defaults", "launchctl", "killall", "cargo", "gh", "swiftc", "codesign", "ditto",
    ]

    /// Commands that are also common words: count only with flags, paths,
    /// pipes or assignments after them.
    private static let plainCommands: Set<String> = [
        "cd", "ls", "cat", "grep", "echo", "export", "rm", "mv", "cp", "open", "make", "tar",
        "unzip", "node", "go", "swift", "python",
    ]

    private static let codeLinePrefixes = [
        "func ", "let ", "var ", "const ", "def ", "class ", "struct ", "enum ", "import ",
        "return ", "if (", "if let ", "guard let ", "for (", "while (", "#include", "#import",
        "public ", "private ", "static ", "fn ", "package ", "using ", "namespace ", "//", "/*",
        "elif ", "else:", "try:", "except", "async ", "await ", "<?php", "<div", "<script", "</",
    ]

    private static let sqlPrefixes = ["SELECT ", "INSERT INTO ", "UPDATE ", "DELETE FROM ", "CREATE TABLE "]

    private static let codeLineSuffixes = [";", "{", "}", "};", "):", ") {", "=>", "->", "*/"]

    private static let codeOperators = ["==", "!=", "->", "::", "&&", "||", "+=", "=>"]

    /// Scores lines with code-like starts, ends or operators. Two or more
    /// such lines making up at least a third of the text is code; a single
    /// line needs a stronger signal; up to three shell lines count too.
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }

        if lines.count <= 3, lines.allSatisfy(isShellLine) { return true }
        if lines.count == 1 { return isStrongSingleCodeLine(lines[0]) }

        let codeLines = lines.filter(isCodeLine).count
        return codeLines >= 2 && codeLines * 3 >= lines.count
    }

    private static func isShellLine(_ line: String) -> Bool {
        if line.hasPrefix("$ ") || line.hasPrefix("% ") { return true }
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let command = parts.first.map(String.init) else { return false }
        if toolCommands.contains(command) { return true }
        guard plainCommands.contains(command) else { return false }
        let args = parts[1]
        return args.hasPrefix("-") || args.contains(" -") || args.contains("/") || args.contains("|")
            || args.contains("&&") || args.contains("=")
    }

    private static func isCodeLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if codeLinePrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        if sqlPrefixes.contains(where: { line.hasPrefix($0) }) { return true }
        if codeLineSuffixes.contains(where: { line.hasSuffix($0) }) { return true }
        return codeOperators.contains { line.contains($0) }
    }

    private static func isStrongSingleCodeLine(_ line: String) -> Bool {
        if line.hasSuffix(".") || line.hasSuffix("?") || line.hasSuffix("!") { return false }
        let lower = line.lowercased()
        let hasParens = line.contains("(") && line.contains(")")
        if codeLinePrefixes.contains(where: { lower.hasPrefix($0) }),
           line.contains("=") || line.contains("{") || hasParens {
            return true
        }
        if sqlPrefixes.contains(where: { line.hasPrefix($0) }) { return true }
        if line.hasSuffix(";") && hasParens { return true }
        return line.contains("=>") || (line.contains("->") && hasParens)
    }

    // MARK: - Paths

    private static let pathRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:^|(?<=[\s"'(]))(?:~/|file:///|/(?:Users|Volumes|Applications|System|Library|private|tmp|var|etc|opt|usr|bin|sbin|home|dev|mnt)(?:/|$)|[A-Za-z]:\\)[^\s"')]*"#,
        options: [.anchorsMatchLines])

    private static let pathStarts = ["~/", "file:///", "/"]

    /// nil when there is no path; true when the whole text is one path
    /// ("~/x", or a single line starting at the root with two or more
    /// separators, e.g. "/Users/me", "C:\\Temp\\a.txt").
    static func pathMatch(in trimmed: String) -> Bool? {
        if isEntirePath(trimmed) { return true }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return pathRegex?.firstMatch(in: trimmed, range: range) != nil ? false : nil
    }

    private static func isEntirePath(_ text: String) -> Bool {
        guard text.count <= 1024, !text.contains("\n"), !text.contains("  ") else { return false }
        let windows = text.count > 3 && text.first?.isLetter == true
            && text.dropFirst().hasPrefix(":\\")
        guard windows || pathStarts.contains(where: { text.hasPrefix($0) }) else { return false }
        let afterRoot = text.drop { $0 == "/" || $0 == "~" }
        guard let next = afterRoot.first, !next.isWhitespace else { return false }
        if text.hasPrefix("~/") || windows { return true }
        let separators = text.filter { $0 == "/" }.count
        return separators >= 2 && !text.hasSuffix(".")
    }

    // MARK: - Language

    static func detectLanguage(_ text: String) -> String? {
        let letters = text.unicodeScalars.lazy.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= minLanguageLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minLanguageConfidence, language != .undetermined else { return nil }
        return language.rawValue
    }
}
