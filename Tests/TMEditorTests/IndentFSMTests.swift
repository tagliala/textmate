import Foundation
import Testing
@testable import TMEditor

@Suite("IndentFSM — Auto-Indentation")
struct IndentFSMTests {
	// MARK: - Helpers

	/// C-style indent patterns.
	private static let cPatterns: [IndentFSM.PatternType: NSRegularExpression] = {
		var p: [IndentFSM.PatternType: NSRegularExpression] = [:]
		p[.increase] = try! NSRegularExpression(pattern: "\\{[^}]*$")
		p[.decrease] = try! NSRegularExpression(pattern: "^\\s*\\}")
		p[.increaseNext] = try! NSRegularExpression(pattern: "[^;,{}]$")
		p[.ignore] = try! NSRegularExpression(pattern: "^\\s*(/\\*|\\*|//|#)")
		return p
	}()

	// MARK: - Leading Whitespace

	@Test func leadingWhitespaceSpaces() {
		#expect(IndentFSM.leadingWhitespace("    hello", tabSize: 4) == 4)
	}

	@Test func leadingWhitespaceTabs() {
		#expect(IndentFSM.leadingWhitespace("\thello", tabSize: 4) == 4)
	}

	@Test func leadingWhitespaceMixed() {
		#expect(IndentFSM.leadingWhitespace("\t  hello", tabSize: 4) == 6)
	}

	@Test func leadingWhitespaceNone() {
		#expect(IndentFSM.leadingWhitespace("hello", tabSize: 4) == 0)
	}

	// MARK: - Create Indent

	@Test func createIndentSoftTabs() {
		let indent = IndentFSM.createIndent(size: 8, tabSize: 4, softTabs: true)
		#expect(indent == "        ")
	}

	@Test func createIndentHardTabs() {
		let indent = IndentFSM.createIndent(size: 8, tabSize: 4, softTabs: false)
		#expect(indent == "\t\t")
	}

	@Test func createIndentMixed() {
		let indent = IndentFSM.createIndent(size: 6, tabSize: 4, softTabs: false)
		#expect(indent == "\t  ")
	}

	// MARK: - Basic Indent Scanning

	@Test func simpleIncrease() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		// Seed with a line that ends with `{`
		let seeded = fsm.isSeeded("int main() {", patterns: Self.cPatterns)
		#expect(!seeded)

		// Now scan the next line — should indent by 4
		let indent = fsm.scanLine("    return 0;", patterns: Self.cPatterns)
		#expect(indent == 4)
	}

	@Test func decreaseOnClosingBrace() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		_ = fsm.isSeeded("void foo() {", patterns: Self.cPatterns)
		_ = fsm.isSeeded("    if (true) {", patterns: Self.cPatterns)
		let indent = fsm.scanLine("    }", patterns: Self.cPatterns)
		#expect(indent == 0)
	}

	@Test func ignoredLines() {
		let fsm = IndentFSM(indentSize: 4, tabSize: 4)
		#expect(fsm.isIgnored("    // comment", patterns: Self.cPatterns))
		#expect(fsm.isIgnored("    * continuation", patterns: Self.cPatterns))
		#expect(fsm.isIgnored("", patterns: Self.cPatterns))
		#expect(!fsm.isIgnored("int x = 1;", patterns: Self.cPatterns))
	}

	// MARK: - Seeding

	@Test func seedingWithContext() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		// Feed context lines until seeded
		let s1 = fsm.isSeeded("void foo() {", patterns: Self.cPatterns)
		#expect(!s1)
		let s2 = fsm.isSeeded("    int x = 1;", patterns: Self.cPatterns)
		#expect(s2)

		// Now scan the inserted line
		let indent = fsm.scanLine("    int y = 2;", patterns: Self.cPatterns)
		#expect(indent == 4)
	}

	@Test func seedingSkipsBlankLines() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		let s1 = fsm.isSeeded("", patterns: Self.cPatterns)
		#expect(!s1) // blank
		let s2 = fsm.isSeeded("void foo() {", patterns: Self.cPatterns)
		#expect(!s2) // first real
		let s3 = fsm.isSeeded("    int x;", patterns: Self.cPatterns)
		#expect(s3) // second real → seeded
	}

	@Test func seedingSkipsComments() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		let s1 = fsm.isSeeded("// header comment", patterns: Self.cPatterns)
		#expect(!s1)
		let s2 = fsm.isSeeded("int main() {", patterns: Self.cPatterns)
		#expect(!s2)
		let s3 = fsm.isSeeded("    return 0;", patterns: Self.cPatterns)
		#expect(s3)
	}

	// MARK: - Multi-line Program

	@Test func multiLineProgram() {
		var fsm = IndentFSM(indentSize: 4, tabSize: 4)

		// Seed
		_ = fsm.isSeeded("int main() {", patterns: Self.cPatterns)
		_ = fsm.isSeeded("    int x = 0;", patterns: Self.cPatterns)

		// Scan lines
		let indent1 = fsm.scanLine("    while (true) {", patterns: Self.cPatterns)
		#expect(indent1 == 4)

		let indent2 = fsm.scanLine("        x++;", patterns: Self.cPatterns)
		#expect(indent2 == 8)

		let indent3 = fsm.scanLine("    }", patterns: Self.cPatterns)
		#expect(indent3 == 4)

		let indent4 = fsm.scanLine("}", patterns: Self.cPatterns)
		#expect(indent4 == 0)
	}

	// MARK: - Pattern Types

	@Test func patternTypeOptionSet() {
		let both: IndentFSM.PatternType = [.increase, .decrease]
		#expect(both.contains(.increase))
		#expect(both.contains(.decrease))
		#expect(!both.contains(.ignore))
	}
}
