import Testing
@testable import TMSearchReplace

@Suite("ReplacementTemplate")
struct ReplacementTemplateTests {
	@Test("Plain text replacement")
	func plainText() {
		let template = ReplacementTemplate("hello world")
		let result = template.expand(with: [:])
		#expect(result == "hello world")
	}

	@Test("Numbered capture reference $1")
	func numberedCapture() {
		let template = ReplacementTemplate("Hello $1!")
		let result = template.expand(with: ["1": "World"])
		#expect(result == "Hello World!")
	}

	@Test("Full match reference $0")
	func fullMatchCapture() {
		let template = ReplacementTemplate("[$0]")
		let result = template.expand(with: ["0": "matched"])
		#expect(result == "[matched]")
	}

	@Test("Multiple capture references")
	func multipleCaptures() {
		let template = ReplacementTemplate("$2 = $1")
		let result = template.expand(with: ["1": "key", "2": "value"])
		#expect(result == "value = key")
	}

	@Test("Braced capture reference ${1}")
	func bracedCapture() {
		let template = ReplacementTemplate("${1}xyz")
		let result = template.expand(with: ["1": "abc"])
		#expect(result == "abcxyz")
	}

	@Test("Named capture reference ${name}")
	func namedCapture() {
		let template = ReplacementTemplate("Hello ${name}")
		let result = template.expand(with: ["name": "World"])
		#expect(result == "Hello World")
	}

	@Test("Missing capture expands to empty")
	func missingCapture() {
		let template = ReplacementTemplate("$1 and $2")
		let result = template.expand(with: ["1": "first"])
		#expect(result == "first and ")
	}

	@Test("Escape sequences")
	func escapeSequences() {
		let template = ReplacementTemplate("line1\\nline2\\ttab\\\\backslash\\$dollar")
		let result = template.expand(with: [:])
		#expect(result == "line1\nline2\ttab\\backslash$dollar")
	}

	@Test("Upcase transform")
	func upcaseTransform() {
		let template = ReplacementTemplate("${1:/upcase}")
		let result = template.expand(with: ["1": "hello"])
		#expect(result == "HELLO")
	}

	@Test("Downcase transform")
	func downcaseTransform() {
		let template = ReplacementTemplate("${1:/downcase}")
		let result = template.expand(with: ["1": "HELLO"])
		#expect(result == "hello")
	}

	@Test("Capitalize transform")
	func capitalizeTransform() {
		let template = ReplacementTemplate("${1:/capitalize}")
		let result = template.expand(with: ["1": "hello world"])
		#expect(result == "Hello World")
	}

	@Test("Conditional with captured group present")
	func conditionalPresent() {
		let template = ReplacementTemplate("(?1:yes:no)")
		let result = template.expand(with: ["1": "something"])
		#expect(result == "yes")
	}

	@Test("Conditional with captured group absent")
	func conditionalAbsent() {
		let template = ReplacementTemplate("(?1:yes:no)")
		let result = template.expand(with: [:])
		#expect(result == "no")
	}

	@Test("Conditional without else part")
	func conditionalNoElse() {
		let template = ReplacementTemplate("(?1:found)")
		let result = template.expand(with: [:])
		#expect(result == "")
	}

	@Test("Conditional with capture present, no else")
	func conditionalPresentNoElse() {
		let template = ReplacementTemplate("(?1:found)")
		let result = template.expand(with: ["1": "x"])
		#expect(result == "found")
	}

	@Test("Dollar sign at end of template")
	func dollarAtEnd() {
		let template = ReplacementTemplate("cost: $")
		let result = template.expand(with: [:])
		#expect(result == "cost: $")
	}

	@Test("Empty template")
	func emptyTemplate() {
		let template = ReplacementTemplate("")
		let result = template.expand(with: ["1": "something"])
		#expect(result == "")
	}

	@Test("Complex template with multiple features")
	func complexTemplate() {
		let template = ReplacementTemplate("${1:/upcase}(?2:=$2) // was $0")
		let result = template.expand(with: ["0": "x=1", "1": "x", "2": "1"])
		#expect(result == "X=1 // was x=1")
	}

	@Test("ReplaceAll convenience method")
	func replaceAll() throws {
		let result = try ReplacementTemplate.replaceAll(
			in: "hello world",
			pattern: "(\\w+)",
			replacement: "[$1]",
			options: .regularExpression,
		)
		#expect(result == "[hello] [world]")
	}

	@Test("ReplaceAll with no matches returns original")
	func replaceAllNoMatch() throws {
		let result = try ReplacementTemplate.replaceAll(
			in: "hello world",
			pattern: "xyz",
			replacement: "replaced",
			options: .regularExpression,
		)
		#expect(result == "hello world")
	}
}
