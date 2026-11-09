import XCTest
@testable import StoneClipboarderTool

final class ContentClassifierTests: XCTestCase {

    private func keys(_ text: String, rules: [ContentClassifier.RegexRule] = []) -> Set<String> {
        ContentClassifier.classify(text, ruleset: ContentClassifier.Ruleset(rules: rules)).keys
    }

    // MARK: - Detectors

    func testBareLinkIsAnEntireLink() {
        XCTAssertEqual(keys("  https://example.com/a?b=1 \n"), ["link", "link.full"])
    }

    func testLinkInsideTextIsContainsOnly() {
        let found = keys("See https://example.com for details")
        XCTAssertTrue(found.contains("link"))
        XCTAssertFalse(found.contains("link.full"))
    }

    func testEmailIsNotALink() {
        XCTAssertEqual(keys("someone@example.com"), ["email", "email.full"])
        let found = keys("Write to someone@example.com today")
        XCTAssertTrue(found.contains("email"))
        XCTAssertFalse(found.contains("link"))
    }

    func testPhoneNumber() {
        XCTAssertTrue(keys("+1 (408) 555-0123").contains("phone.full"))
        XCTAssertTrue(keys("Call me at +1 408 555 0123 tomorrow").contains("phone"))
    }

    func testDate() {
        let found = keys("Meeting on March 5, 2026 in the office")
        XCTAssertTrue(found.contains("date"))
        XCTAssertFalse(found.contains("date.full"))
    }

    func testAddress() {
        XCTAssertTrue(keys("1 Infinite Loop, Cupertino, CA 95014").contains("address"))
    }

    func testPlainProseHasNoKeys() {
        XCTAssertEqual(keys("Dear colleagues, thank you for the nice meeting."), [])
    }

    func testEmptyTextIsUnclassified() {
        XCTAssertEqual(ContentClassifier.classify("   \n "), ContentClassifier.Result())
    }

    // MARK: - JSON and code

    func testJSONObjectAndArray() {
        XCTAssertEqual(keys(#"{"a": 1, "b": [true, null]}"#), ["json"])
        XCTAssertTrue(keys("[1, 2, 3]").contains("json"))
    }

    func testBrokenJSONIsNotJSON() {
        XCTAssertFalse(keys(#"{"a": 1"#).contains("json"))
    }

    func testSwiftCode() {
        let swift = """
        func greet(_ name: String) -> String {
            let greeting = "Hello, " + name
            return greeting
        }
        """
        XCTAssertTrue(keys(swift).contains("code"))
    }

    func testPythonCode() {
        XCTAssertTrue(keys("def double(x):\n    return x * 2").contains("code"))
    }

    func testShellCommands() {
        XCTAssertTrue(keys("git commit -m \"fix\"").contains("code"))
        XCTAssertTrue(keys("$ make run").contains("code"))
        XCTAssertTrue(keys("cd ~/Projects && ls -la").contains("code"))
    }

    func testSingleCodeLines() {
        XCTAssertTrue(keys("let total = items.count").contains("code"))
        XCTAssertTrue(keys("print(value);").contains("code"))
        XCTAssertTrue(keys("SELECT * FROM users").contains("code"))
        XCTAssertTrue(keys("const add = (a, b) => a + b").contains("code"))
    }

    func testProseThatLooksLikeCommandsIsNotCode() {
        XCTAssertFalse(keys("make sense of it").contains("code"))
        XCTAssertFalse(keys("Let me know (if you can).").contains("code"))
        XCTAssertFalse(keys("open the door").contains("code"))
        XCTAssertFalse(keys("№ 9351/2026 від 19.05.2026").contains("code"))
    }

    // MARK: - Paths

    func testEntirePaths() {
        XCTAssertTrue(keys("/Users/me/Documents/report.pdf").contains("path.full"))
        XCTAssertTrue(keys("~/Desktop").contains("path.full"))
        XCTAssertTrue(keys(#"C:\Temp\a.txt"#).contains("path.full"))
        XCTAssertTrue(keys("file:///Users/me/a.txt").contains("path"))
    }

    func testPathInsideText() {
        let found = keys("The log is in /Users/me/Library/Logs/app.log if you need it")
        XCTAssertTrue(found.contains("path"))
        XCTAssertFalse(found.contains("path.full"))
    }

    func testSlashesInProseAreNotPaths() {
        XCTAssertFalse(keys("№ 9351/2026 від 19.05.2026").contains("path"))
        XCTAssertFalse(keys("and/or").contains("path"))
        XCTAssertNil(ContentClassifier.pathMatch(in: "/s"))
    }

    // MARK: - Language

    func testLanguages() {
        let ukrainian = "Лист подяки від адміністрації державної служби за співпрацю у минулому році"
        let english = "Thank you very much for your help with the project last week, it was great"
        XCTAssertEqual(ContentClassifier.classify(ukrainian).language, "uk")
        XCTAssertEqual(ContentClassifier.classify(english).language, "en")
    }

    func testShortTextHasNoLanguage() {
        XCTAssertNil(ContentClassifier.classify("Hi there").language)
    }

    func testCodeAndBareLinksHaveNoLanguage() {
        XCTAssertNil(ContentClassifier.classify("https://example.com/some/long/path/with/words/in/it").language)
        XCTAssertNil(ContentClassifier.classify(#"{"message": "this is a long english sentence inside json"}"#).language)
    }

    // MARK: - Regex rules

    func testRegexRuleContainsAndEntire() {
        let rule = ContentClassifier.RegexRule(id: "doc", pattern: #"№\s*\d+/\d{4}"#, caseSensitive: false)
        XCTAssertEqual(keys("№ 9351/2026", rules: [rule]), ["doc", "doc.full"])
        let found = keys("№ 9351/2026 від 19.05.2026", rules: [rule])
        XCTAssertTrue(found.contains("doc"))
        XCTAssertFalse(found.contains("doc.full"))
    }

    func testRegexCaseSensitivity() {
        let insensitive = ContentClassifier.RegexRule(id: "a", pattern: "invoice", caseSensitive: false)
        let sensitive = ContentClassifier.RegexRule(id: "b", pattern: "invoice", caseSensitive: true)
        let found = keys("INVOICE 12", rules: [insensitive, sensitive])
        XCTAssertTrue(found.contains("a"))
        XCTAssertFalse(found.contains("b"))
    }

    func testARuleWhoseEntireFormDoesNotCompileStillMatches() {
        // In (?x) mode "#" starts a comment, which swallows the wrapper's ")".
        let rule = ContentClassifier.RegexRule(id: "x", pattern: "(?x)invoice # a note", caseSensitive: false)
        XCTAssertTrue(ItemCategory.isValidPattern(rule.pattern))
        XCTAssertEqual(keys("Invoice 7", rules: [rule]), ["x"])
        XCTAssertEqual(keys("invoice", rules: [rule]), ["x", "x.full"])
        let alternation = ContentClassifier.RegexRule(id: "y", pattern: "(?x) inv | invoice  # note", caseSensitive: false)
        XCTAssertEqual(keys("invoice", rules: [alternation]), ["y", "y.full"], "a shorter alternative doesn't hide the whole match")
    }

    func testInvalidRegexIsSkipped() {
        let broken = ContentClassifier.RegexRule(id: "x", pattern: "(unclosed", caseSensitive: false)
        XCTAssertFalse(keys("(unclosed", rules: [broken]).contains("x"))
    }

    func testOnlyTheHeadIsExaminedAndNeverCountsAsEntire() {
        let rule = ContentClassifier.RegexRule(id: "tail", pattern: "TAIL", caseSensitive: true)
        let long = String(repeating: "a", count: ContentClassifier.maxLength) + "TAIL"
        XCTAssertFalse(keys(long, rules: [rule]).contains("tail"))

        let longLink = "https://example.com/" + String(repeating: "a", count: ContentClassifier.maxLength)
        XCTAssertFalse(keys(longLink).contains("link.full"))
    }

    // MARK: - Stamp

    func testStampIsStableAndChangesWithRules() {
        let a = ContentClassifier.RegexRule(id: "a", pattern: "x", caseSensitive: false)
        let b = ContentClassifier.RegexRule(id: "b", pattern: "y", caseSensitive: false)
        XCTAssertEqual(ContentClassifier.stamp(for: [a, b]), ContentClassifier.stamp(for: [b, a]), "order-independent")
        XCTAssertNotEqual(ContentClassifier.stamp(for: [a]), ContentClassifier.stamp(for: [a, b]))
        let changed = ContentClassifier.RegexRule(id: "a", pattern: "x", caseSensitive: true)
        XCTAssertNotEqual(ContentClassifier.stamp(for: [a]), ContentClassifier.stamp(for: [changed]))
        XCTAssertNotEqual(ContentClassifier.Ruleset.empty.stamp, 0)
        XCTAssertEqual(ContentClassifier.Ruleset(rules: [a], analyzeImages: true).stamp,
                       ContentClassifier.Ruleset(rules: [a], analyzeImages: false).stamp,
                       "the image switch doesn't touch text items")
    }
}
