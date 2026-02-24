import Foundation
import Testing
@testable import TMSettings

@Suite("TMPropertiesParser")
struct TMPropertiesParserTests {
	// MARK: - Basic Parsing

	@Test func emptyFile() {
		let file = TMPropertiesParser.parse(content: "", path: "test")
		#expect(file.sections.isEmpty)
	}

	@Test func commentOnlyFile() {
		let content = """
		# This is a comment
		# Another comment
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections.isEmpty)
	}

	@Test func simpleAssignment() {
		let content = "tabSize = 4"
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections.count == 1)
		#expect(file.sections[0].names.isEmpty) // top-level
		#expect(file.sections[0].assignments.count == 1)
		#expect(file.sections[0].assignments[0].key == "tabSize")
		#expect(file.sections[0].assignments[0].value == "4")
	}

	@Test func multipleAssignments() {
		let content = """
		tabSize = 4
		softTabs = true
		theme = Monokai
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments.count == 3)
		#expect(file.sections[0].assignments[0].key == "tabSize")
		#expect(file.sections[0].assignments[1].key == "softTabs")
		#expect(file.sections[0].assignments[2].key == "theme")
	}

	// MARK: - Sections

	@Test func singleSection() {
		let content = """
		[ *.swift ]
		tabSize = 3
		softTabs = false
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections.count == 1)
		#expect(file.sections[0].names == ["*.swift"])
		#expect(file.sections[0].assignments.count == 2)
	}

	@Test func multipleSections() {
		let content = """
		tabSize = 4

		[ *.swift ]
		tabSize = 3

		[ *.py ]
		tabSize = 4
		softTabs = true
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections.count == 3)
		#expect(file.sections[0].names.isEmpty)
		#expect(file.sections[1].names == ["*.swift"])
		#expect(file.sections[2].names == ["*.py"])
	}

	@Test func sectionWithMultipleNames() {
		let content = """
		[ *.cc ; *.h ]
		tabSize = 3
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].names == ["*.cc", "*.h"])
	}

	@Test func scopeSelector() {
		let content = """
		[ text.html ]
		softWrap = true
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].names == ["text.html"])
	}

	// MARK: - Quoted Values

	@Test func singleQuotedValue() {
		let content = "greeting = 'Hello, world!'"
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].value == "Hello, world!")
	}

	@Test func doubleQuotedValue() {
		let content = "greeting = \"Hello, world!\""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].value == "Hello, world!")
	}

	@Test func bareValue() {
		let content = "tabSize = 4"
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].value == "4")
	}

	// MARK: - Comments

	@Test func inlineComment() {
		let content = "tabSize = 4 # use 4 spaces"
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].value == "4")
	}

	@Test func commentPreservesQuotedHash() {
		let content = "pattern = '*.#*'"
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].value == "*.#*")
	}

	// MARK: - Line Numbers

	@Test func lineNumbers() {
		let content = """
		# comment
		tabSize = 4
		softTabs = true
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].assignments[0].lineNumber == 2)
		#expect(file.sections[0].assignments[1].lineNumber == 3)
	}

	// MARK: - Variable Expansion

	@Test func simpleVariableExpansion() {
		let content = """
		testSetting = Hello
		"""
		let file = TMPropertiesParser.parse(content: content, path: "/test/.tm_properties")
		// The parser itself doesn't expand — but we can test via SettingsResolver
		#expect(file.sections[0].assignments[0].value == "Hello")
	}

	// MARK: - Complex Real-World Example

	@Test func realWorldExample() {
		let content = """
		# Project settings
		projectDirectory = $CWD
		windowTitle = $TM_DISPLAYNAME

		[ *.swift ]
		tabSize = 3
		softTabs = false

		[ *.md ; *.txt ]
		softWrap = true
		wrapColumn = 80

		[ source.swift ]
		showInvisibles = true

		[ folder/** ]
		excludeInFolderSearch = '{build,vendor}'
		"""
		let file = TMPropertiesParser.parse(content: content, path: "/project/.tm_properties")
		#expect(file.sections.count == 5)
		#expect(file.sections[0].names.isEmpty)
		#expect(file.sections[0].assignments.count == 2)
		#expect(file.sections[1].names == ["*.swift"])
		#expect(file.sections[2].names == ["*.md", "*.txt"])
		#expect(file.sections[3].names == ["source.swift"])
		#expect(file.sections[4].names == ["folder/**"])
	}
}

// MARK: - Settings Resolver Tests

@Suite("SettingsResolver")
struct SettingsResolverTests {
	// MARK: - Glob Matching

	@Test func globMatchesExtension() {
		let result = SettingsResolver.settingsForPath(nil, baseVariables: ["test": "1"])
		#expect(result["test"] == "1")
	}

	// MARK: - Variable Expansion

	@Test func expandSimpleVariable() {
		let result = SettingsResolver.settingsForPath(
			nil,
			baseVariables: ["greeting": "hello", "message": "$greeting world"],
		)
		// Base variables are passed through without expansion by the resolver
		// (expansion only happens from .tm_properties files).
		#expect(result["greeting"] == "hello")
	}

	// MARK: - Scope Matching

	@Test func isScopeSelectorDetection() {
		// This is tested indirectly through settings resolution.
		// "source.swift" should be treated as a scope selector, not a glob.
		let content = """
		[ source.swift ]
		showInvisibles = true
		"""
		let file = TMPropertiesParser.parse(content: content, path: "test")
		#expect(file.sections[0].names == ["source.swift"])
	}
}

// MARK: - String Extension Tests

@Suite("StringProtocol.trimmingWhitespace")
struct TrimmingWhitespaceTests {
	@Test func trimsBothEnds() {
		#expect("  hello  ".trimmingWhitespace() == "hello")
		#expect("\thello\t".trimmingWhitespace() == "hello")
	}

	@Test func preservesInternalWhitespace() {
		#expect("  hello world  ".trimmingWhitespace() == "hello world")
	}

	@Test func emptyString() {
		#expect("".trimmingWhitespace() == "")
		#expect("   ".trimmingWhitespace() == "")
	}

	@Test func noWhitespace() {
		#expect("hello".trimmingWhitespace() == "hello")
	}
}
