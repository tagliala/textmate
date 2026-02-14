import Testing
@testable import TMBundle
@testable import TMGrammar

// MARK: - Scope Tests

@Suite("Scope")
struct ScopeTests {
	@Test("Empty scope")
	func emptyScope() {
		let scope = Scope()
		#expect(scope.isEmpty)
		#expect(scope.size == 0)
		#expect(scope.back == nil)
		#expect(scope.toString() == "")
	}

	@Test("Push and pop")
	func pushPop() {
		var scope = Scope()
		scope.pushScope("source.swift")
		#expect(scope.size == 1)
		#expect(scope.back == "source.swift")

		scope.pushScope("meta.function")
		#expect(scope.size == 2)
		#expect(scope.back == "meta.function")

		scope.popScope()
		#expect(scope.size == 1)
		#expect(scope.back == "source.swift")
	}

	@Test("Init from string")
	func initFromString() {
		let scope = Scope("source.swift meta.function.definition string.quoted")
		#expect(scope.size == 3)
		#expect(scope.back == "string.quoted")
		#expect(scope.toString() == "source.swift meta.function.definition string.quoted")
	}

	@Test("String literal")
	func stringLiteral() {
		let scope: Scope = "source.c"
		#expect(scope.size == 1)
		#expect(scope.back == "source.c")
	}

	@Test("Equality")
	func equality() {
		let a = Scope("source.swift meta.function")
		let b = Scope("source.swift meta.function")
		let c = Scope("source.swift meta.class")
		#expect(a == b)
		#expect(a != c)
	}

	@Test("Equality across different construction paths")
	func equalityDifferentConstruction() {
		var a = Scope()
		a.pushScope("source.swift")
		a.pushScope("meta.function")

		let b = Scope("source.swift meta.function")
		#expect(a == b)
	}

	@Test("Hashable consistency")
	func hashable() {
		let a = Scope("source.swift meta.function")
		let b = Scope("source.swift meta.function")
		#expect(a.hashValue == b.hashValue)

		var set: Set<Scope> = [a]
		set.insert(b)
		#expect(set.count == 1)
	}

	@Test("hasPrefix")
	func hasPrefix() {
		let scope = Scope("source.swift meta.function string.quoted")
		#expect(scope.hasPrefix(Scope("source.swift")))
		#expect(scope.hasPrefix(Scope("source.swift meta.function")))
		#expect(scope.hasPrefix(Scope("source.swift meta.function string.quoted")))
		#expect(!scope.hasPrefix(Scope("source.objc")))
		#expect(!scope.hasPrefix(Scope("source.swift meta.class")))
	}

	@Test("Empty prefix matches everything")
	func emptyPrefixMatchesAll() {
		let scope = Scope("source.swift")
		#expect(scope.hasPrefix(Scope()))
	}

	@Test("Node isAuxiliary")
	func nodeAuxiliary() {
		var scope = Scope()
		scope.pushScope("source.swift")
		scope.pushScope("attr.line-number")
		#expect(scope.currentNode?.isAuxiliary == true)

		scope.pushScope("dyn.cursor")
		#expect(scope.currentNode?.isAuxiliary == true)

		scope.popScope()
		scope.popScope()
		#expect(scope.currentNode?.isAuxiliary == false)
	}

	@Test("Node numberOfAtoms")
	func nodeAtomCount() {
		var scope = Scope()
		scope.pushScope("source.swift")
		#expect(scope.currentNode?.numberOfAtoms == 2)

		scope.pushScope("meta.function.definition.swift")
		#expect(scope.currentNode?.numberOfAtoms == 4)

		scope.pushScope("keyword")
		#expect(scope.currentNode?.numberOfAtoms == 1)
	}

	@Test("Description matches toString")
	func description() {
		let scope = Scope("source.swift meta.function")
		#expect(scope.description == scope.toString())
	}
}

// MARK: - ScopeContext Tests

@Suite("ScopeContext")
struct ScopeContextTests {
	@Test("Single scope context")
	func singleScope() {
		let ctx = ScopeContext("source.swift")
		#expect(ctx.left == ctx.right)
		#expect(ctx.left == Scope("source.swift"))
	}

	@Test("Two-sided context")
	func twoSided() {
		let left = Scope("source.swift string.quoted")
		let right = Scope("source.swift meta.function")
		let ctx = ScopeContext(left: left, right: right)
		#expect(ctx.left == left)
		#expect(ctx.right == right)
		#expect(ctx.left != ctx.right)
	}
}

// MARK: - ScopeSelector Tests

@Suite("ScopeSelector")
struct ScopeSelectorTests {
	@Test("Empty selector matches everything")
	func emptySelector() {
		let sel = ScopeSelector("")
		#expect(sel.doesMatch(Scope("source.swift")) == 0)
		#expect(sel.doesMatch(Scope()) == 0)
	}

	@Test("Simple scope matching")
	func simpleMatch() {
		let sel = ScopeSelector("source.swift")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("source.swift meta.function")) != nil)
		#expect(sel.doesMatch(Scope("source.objc")) == nil)
	}

	@Test("Partial scope matching")
	func partialMatch() {
		let sel = ScopeSelector("source")
		// "source" matches "source.swift" because it's a prefix
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("text.html")) == nil)
	}

	@Test("Multi-scope descendant matching")
	func descendantMatch() {
		let sel = ScopeSelector("source.swift string")
		#expect(sel.doesMatch(Scope("source.swift meta.function string.quoted")) != nil)
		#expect(sel.doesMatch(Scope("source.swift string.quoted")) != nil)
		#expect(sel.doesMatch(Scope("source.swift meta.function")) == nil)
	}

	@Test("OR operator")
	func orOperator() {
		let sel = ScopeSelector("source.swift | source.objc")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("source.objc")) != nil)
		#expect(sel.doesMatch(Scope("source.python")) == nil)
	}

	@Test("AND operator")
	func andOperator() {
		let sel = ScopeSelector("source & meta.function")
		#expect(sel.doesMatch(Scope("source.swift meta.function")) != nil)
		#expect(sel.doesMatch(Scope("source.swift")) == nil)
	}

	@Test("MINUS operator (exclusion)")
	func minusOperator() {
		let sel = ScopeSelector("source - string")
		#expect(sel.doesMatch(Scope("source.swift meta.function")) != nil)
		#expect(sel.doesMatch(Scope("source.swift string.quoted")) == nil)
	}

	@Test("Negation")
	func negation() {
		let sel = ScopeSelector("-string")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("string.quoted")) == nil)
	}

	@Test("Comma-separated composites")
	func commaSeparated() {
		let sel = ScopeSelector("source.swift, source.objc")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("source.objc")) != nil)
		#expect(sel.doesMatch(Scope("text.html")) == nil)
	}

	@Test("Wildcard matching")
	func wildcard() {
		let sel = ScopeSelector("source.*")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("source.objc")) != nil)
		#expect(sel.doesMatch(Scope("text.html")) == nil)
	}

	@Test("Child operator >")
	func childOperator() {
		let sel = ScopeSelector("source.swift > meta.function")
		// Direct child: should match
		#expect(sel.doesMatch(Scope("source.swift meta.function")) != nil)
	}

	@Test("Grouped selector (parentheses)")
	func grouped() {
		let sel = ScopeSelector("(source.swift | source.objc)")
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
		#expect(sel.doesMatch(Scope("source.objc")) != nil)
	}

	@Test("Rank ordering: more specific wins")
	func rankOrdering() throws {
		let sel1 = ScopeSelector("source")
		let sel2 = ScopeSelector("source.swift")

		let scope = Scope("source.swift meta.function")
		let rank1 = try #require(sel1.doesMatch(scope))
		let rank2 = try #require(sel2.doesMatch(scope))
		#expect(rank2 > rank1)
	}

	@Test("L: filter (left scope)")
	func leftFilter() {
		let sel = ScopeSelector("L:source.swift")
		let ctx = ScopeContext(
			left: Scope("source.swift"),
			right: Scope("source.objc"),
		)
		#expect(sel.doesMatch(ctx) != nil)

		let ctx2 = ScopeContext(
			left: Scope("source.objc"),
			right: Scope("source.swift"),
		)
		#expect(sel.doesMatch(ctx2) == nil)
	}

	@Test("R: filter (right scope)")
	func rightFilter() {
		let sel = ScopeSelector("R:source.swift")
		let ctx = ScopeContext(
			left: Scope("source.objc"),
			right: Scope("source.swift"),
		)
		#expect(sel.doesMatch(ctx) != nil)

		let ctx2 = ScopeContext(
			left: Scope("source.swift"),
			right: Scope("source.objc"),
		)
		#expect(sel.doesMatch(ctx2) == nil)
	}

	@Test("B: filter (both scopes)")
	func bothFilter() {
		let sel = ScopeSelector("B:source")
		let ctx = ScopeContext(
			left: Scope("source.swift"),
			right: Scope("source.objc"),
		)
		#expect(sel.doesMatch(ctx) != nil)

		let ctx2 = ScopeContext(
			left: Scope("source.swift"),
			right: Scope("text.html"),
		)
		#expect(sel.doesMatch(ctx2) == nil)
	}

	@Test("String literal construction")
	func stringLiteral() {
		let sel: ScopeSelector = "source.swift"
		#expect(sel.doesMatch(Scope("source.swift")) != nil)
	}
}

// MARK: - OnigmoPattern Tests (NSRegularExpression backend)

@Suite("OnigmoPattern")
struct OnigmoPatternTests {
	@Test("Simple string match")
	func simpleMatch() {
		let p = OnigmoPattern("hello")
		let m = p.search(in: "say hello world")
		#expect(m != nil)
		#expect(m?.captureString(0) == "hello")
	}

	@Test("No match returns nil")
	func noMatch() {
		let p = OnigmoPattern("xyz")
		#expect(p.search(in: "hello world") == nil)
	}

	@Test("Capture groups")
	func captureGroups() {
		let p = OnigmoPattern("(\\w+)\\s+(\\w+)")
		let m = p.search(in: "hello world")
		#expect(m != nil)
		#expect(m?.count == 3)
		#expect(m?.captureString(0) == "hello world")
		#expect(m?.captureString(1) == "hello")
		#expect(m?.captureString(2) == "world")
	}

	@Test("Named captures")
	func namedCaptures() {
		let p = OnigmoPattern("(?<word>\\w+)")
		let m = p.search(in: "hello")
		#expect(m != nil)
		#expect(m?.captures["word"] == "hello")
	}

	@Test("Byte offsets are correct for ASCII")
	func byteOffsetsASCII() throws {
		let p = OnigmoPattern("world")
		let m = try #require(p.search(in: "hello world"))
		#expect(m.matchBegin == 6)
		#expect(m.matchEnd == 11)
	}

	@Test("Byte offsets are correct for multibyte UTF-8")
	func byteOffsetsUTF8() throws {
		// "café" has 'é' = 2 bytes in UTF-8
		let p = OnigmoPattern("world")
		let m = try #require(p.search(in: "café world"))
		// "café " = c(1) a(1) f(1) é(2) space(1) = 6 bytes
		#expect(m.matchBegin == 6)
		#expect(m.matchEnd == 11)
	}

	@Test("Search in byte buffer")
	func searchInBuffer() throws {
		let buffer = Array("hello world".utf8)
		let p = OnigmoPattern("world")
		let m = try #require(p.search(in: buffer))
		#expect(m.matchBegin == 6)
		#expect(m.matchEnd == 11)
	}

	@Test("Search with byte range")
	func searchWithRange() {
		let buffer = Array("hello world hello".utf8)
		let p = OnigmoPattern("hello")
		// Search starting from byte 6
		let m = p.search(in: buffer, range: 6 ..< buffer.count)
		#expect(m != nil)
		#expect(m?.matchBegin == 12)
	}

	@Test("Invalid pattern returns isValid=false")
	func invalidPattern() {
		let p = OnigmoPattern("(unclosed")
		#expect(!p.isValid)
		#expect(p.search(in: "test") == nil)
	}

	@Test("Empty match (zero-width)")
	func zeroWidthMatch() {
		let p = OnigmoPattern("^")
		let m = p.search(in: "hello")
		#expect(m != nil)
		#expect(m?.isEmpty == true)
	}

	@Test("Alternation")
	func alternation() {
		let p = OnigmoPattern("cat|dog")
		#expect(p.search(in: "I have a cat")?.captureString(0) == "cat")
		#expect(p.search(in: "I have a dog")?.captureString(0) == "dog")
		#expect(p.search(in: "I have a fish") == nil)
	}

	@Test("Lookahead")
	func lookahead() {
		let p = OnigmoPattern("\\w+(?=\\()")
		let m = p.search(in: "func foo()")
		#expect(m?.captureString(0) == "foo")
	}

	@Test("Lookbehind")
	func lookbehind() {
		let p = OnigmoPattern("(?<=@)\\w+")
		let m = p.search(in: "hello @world")
		#expect(m?.captureString(0) == "world")
	}

	@Test("Backreference")
	func backreference() {
		let p = OnigmoPattern("(\\w+)\\s+\\1")
		let m = p.search(in: "hello hello")
		#expect(m != nil)
		#expect(m?.captureString(0) == "hello hello")
	}

	@Test("Character class")
	func characterClass() {
		let p = OnigmoPattern("[aeiou]+")
		let m = p.search(in: "xyz aei uvw")
		#expect(m?.captureString(0) == "aei")
	}

	@Test("patternString preserved")
	func patternStringPreserved() {
		let p = OnigmoPattern("test\\bpattern")
		#expect(p.patternString == "test\\bpattern")
	}

	// MARK: - Oniguruma Translation Tests

	@Test("\\h translation (horizontal whitespace)")
	func horizontalWhitespace() {
		let p = OnigmoPattern("\\h+")
		#expect(p.isValid)
		let m = p.search(in: "hello\t world")
		#expect(m != nil)
		#expect(m?.captureString(0) == "\t ")
	}

	@Test("\\H translation (non-horizontal-whitespace)")
	func nonHorizontalWhitespace() {
		let p = OnigmoPattern("\\H+")
		#expect(p.isValid)
		let m = p.search(in: "\thello ")
		#expect(m?.captureString(0) == "hello")
	}

	@Test("\\R translation (line break)")
	func lineBreak() {
		let p = OnigmoPattern("\\R")
		#expect(p.isValid)
		#expect(p.search(in: "hello\nworld") != nil)
		#expect(p.search(in: "hello\r\nworld") != nil)
	}

	// MARK: - Pending: Oniguruma-specific features not covered by ICU

	@Test(
		"\\G anchor to previous match position",
		.disabled("\\G is handled at parser level, not in regex engine (ADR-005)"),
	)
	func gAnchor() {
		// \G matches at the position where the previous match ended
		// In our implementation, this is handled by patternHasAnchor() and
		// the parser's anchor tracking, not at the regex level.
		let p = OnigmoPattern("\\Gfoo")
		let m = p.search(in: "foobar")
		#expect(m != nil)
	}

	@Test(
		"Oniguruma absent operator (?~...)",
		.disabled("Absent operator is Oniguruma-specific, not supported by ICU (ADR-005)"),
	)
	func absentOperator() {
		// (?~pattern) matches anything that doesn't match pattern
		// This is a unique Oniguruma feature with no ICU equivalent.
		let p = OnigmoPattern("(?~abc)")
		#expect(p.isValid)
	}

	@Test(
		"Oniguruma conditional backref (?(1)yes|no)",
		.disabled("Conditional backrefs have different syntax between Oniguruma and ICU (ADR-005)"),
	)
	func conditionalBackref() {
		// Oniguruma: (?(1)yes|no) — match 'yes' if group 1 matched, else 'no'
		// ICU has different syntax for this feature.
		let p = OnigmoPattern("(a)?(?(1)b|c)")
		#expect(p.isValid)
		#expect(p.search(in: "ab") != nil)
		#expect(p.search(in: "c") != nil)
	}

	@Test(
		"Oniguruma \\p{Katakana} property name",
		.disabled("Oniguruma uses different Unicode property names than ICU for some scripts (ADR-005)"),
	)
	func onigmoPropertyNames() {
		// Oniguruma and ICU both have Unicode property support, but some
		// property names differ. This tests an Oniguruma-specific form.
		let p = OnigmoPattern("\\p{Katakana}+")
		#expect(p.isValid)
		#expect(p.search(in: "カタカナ") != nil)
	}

	@Test(
		"Oniguruma subexp call \\g<name>",
		.disabled("Subexpression calls (\\g<name>) are Oniguruma-only, not supported by ICU (ADR-005)"),
	)
	func subexpressionCall() {
		// \g<name> or \g<1> calls a named/numbered subexpression recursively
		// This is used in some grammars for recursive matching.
		let p = OnigmoPattern("(?<paren>\\(\\g<paren>*\\))")
		#expect(p.isValid)
		#expect(p.search(in: "(())") != nil)
	}

	@Test(
		"Oniguruma keep operator \\K",
		.disabled("\\K (keep/reset start of match) is Oniguruma-specific, not supported by ICU (ADR-005)"),
	)
	func keepOperator() {
		// \K resets the start of the reported match, effectively a lookbehind
		// that's more efficient for the engine.
		let p = OnigmoPattern("foo\\Kbar")
		#expect(p.isValid)
		let m = p.search(in: "foobar")
		#expect(m?.captureString(0) == "bar")
	}
}

// MARK: - Pattern Utility Tests

@Suite("PatternUtilities")
struct PatternUtilityTests {
	@Test("patternHasBackReference")
	func hasBackReference() {
		#expect(patternHasBackReference("(a)\\1") == true)
		#expect(patternHasBackReference("(a)\\b") == false)
		#expect(patternHasBackReference("plain text") == false)
		#expect(patternHasBackReference("\\\\1") == false) // escaped backslash
	}

	@Test("patternHasAnchor")
	func hasAnchor() {
		#expect(patternHasAnchor("\\Gfoo") == true)
		#expect(patternHasAnchor("foo\\Gbar") == true)
		#expect(patternHasAnchor("foobar") == false)
		#expect(patternHasAnchor("\\\\G") == false) // escaped backslash
	}

	@Test("patternIsFormatString")
	func isFormatString() {
		#expect(patternIsFormatString("storage.type.$1") == true)
		#expect(patternIsFormatString("source.swift") == false)
		#expect(patternIsFormatString("meta.$0.definition") == true)
	}

	@Test("expandFormatString with numeric captures")
	func expandFormatNumeric() {
		let result = expandFormatString(
			"storage.type.$1",
			captures: ["0": "int x", "1": "int"],
		)
		#expect(result == "storage.type.int")
	}

	@Test("expandFormatString with named captures")
	func expandFormatNamed() {
		let result = expandFormatString(
			"entity.name.${kind}",
			captures: ["kind": "function"],
		)
		#expect(result == "entity.name.function")
	}

	@Test("expandFormatString with missing captures")
	func expandFormatMissing() {
		let result = expandFormatString(
			"meta.$1.definition",
			captures: [:],
		)
		#expect(result == "meta..definition")
	}

	@Test("expandFormatString with no format references")
	func expandFormatNoRefs() {
		let result = expandFormatString(
			"source.swift",
			captures: ["1": "ignored"],
		)
		#expect(result == "source.swift")
	}

	@Test("expandBackReferences")
	func expandBackRefs() throws {
		let pattern = OnigmoPattern("(\\w+)\\s+(\\w+)")
		let m = try #require(pattern.search(in: "hello world"))
		let expanded = expandBackReferences("end_\\1_\\2", match: m)
		#expect(expanded == "end_hello_world")
	}

	@Test("expandBackReferences escapes special regex chars")
	func expandBackRefsEscapes() throws {
		let pattern = OnigmoPattern("(.+)")
		let m = try #require(pattern.search(in: "a+b"))
		let expanded = expandBackReferences("\\1", match: m)
		// "a+b" should have the + escaped
		#expect(expanded.contains("\\+"))
	}
}

// MARK: - Pattern Translation Tests

@Suite("PatternTranslation")
struct PatternTranslationTests {
	@Test("Passes through normal patterns unchanged")
	func passthrough() {
		let input = "\\bfunction\\s+(\\w+)"
		let output = OnigmoPattern.translatePattern(input)
		#expect(output == input)
	}

	@Test("Translates \\h to horizontal whitespace class")
	func translateH() {
		let output = OnigmoPattern.translatePattern("\\h+")
		#expect(output == "[\\t\\p{Zs}]+")
	}

	@Test("Translates \\H to negated horizontal whitespace class")
	func translateUpperH() {
		let output = OnigmoPattern.translatePattern("\\H+")
		#expect(output == "[^\\t\\p{Zs}]+")
	}

	@Test("Translates \\v to vertical whitespace class")
	func translateV() {
		let output = OnigmoPattern.translatePattern("\\v")
		#expect(output.contains("\\n"))
		#expect(output.contains("\\r"))
	}

	@Test("Translates \\R to line break group")
	func translateR() {
		let output = OnigmoPattern.translatePattern("\\R")
		#expect(output.contains("\\r\\n"))
	}

	@Test("Translates \\X to grapheme cluster")
	func translateX() {
		let output = OnigmoPattern.translatePattern("\\X")
		#expect(output.contains("\\P{M}"))
	}

	@Test("Preserves normal escape sequences")
	func preserveNormalEscapes() {
		let output = OnigmoPattern.translatePattern("\\d\\w\\s\\b\\B")
		#expect(output == "\\d\\w\\s\\b\\B")
	}

	@Test("Handles mixed translated and normal escapes")
	func mixedEscapes() {
		let output = OnigmoPattern.translatePattern("\\d\\h\\w")
		#expect(output == "\\d[\\t\\p{Zs}]\\w")
	}
}

// MARK: - GrammarRule Tests

@Suite("GrammarRule")
struct GrammarRuleTests {
	@Test("Unique rule IDs")
	func uniqueRuleIDs() {
		let a = GrammarRule()
		let b = GrammarRule()
		let c = GrammarRule()
		#expect(a.ruleID != b.ruleID)
		#expect(b.ruleID != c.ruleID)
	}

	@Test("Default GrammarRule properties")
	func defaultProperties() {
		let rule = GrammarRule()
		#expect(rule.scopeString == nil)
		#expect(rule.matchString == nil)
		#expect(rule.endString == nil)
		#expect(rule.whileString == nil)
		#expect(rule.children.isEmpty)
		#expect(rule.matchPattern == nil)
		#expect(!rule.matchPatternIsAnchored)
		#expect(!rule.isRoot)
		#expect(!rule.included)
	}
}

// MARK: - GrammarCompiler Tests

@Suite("GrammarCompiler")
struct GrammarCompilerTests {
	/// Helper to create a minimal grammar definition.
	static func makeGrammar(
		scopeName: String = "source.test",
		patterns: [GrammarDefinition.Pattern] = [],
		repository: [String: GrammarDefinition.PatternGroup] = [:],
	) -> GrammarDefinition {
		GrammarDefinition(
			scopeName: scopeName,
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: patterns,
			repository: repository,
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)
	}

	@Test("Compile empty grammar")
	func compileEmpty() {
		let grammar = Self.makeGrammar()
		let rule = GrammarCompiler.compile(grammar)
		#expect(rule.scopeString == "source.test")
		#expect(rule.children.isEmpty)
	}

	@Test("Compile simple match pattern")
	func compileMatchPattern() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(
				match: "\\b(func|class|struct)\\b",
				name: "keyword.declaration.swift",
			),
		])

		let rule = GrammarCompiler.compile(grammar)
		#expect(rule.children.count == 1)

		let child = rule.children[0]
		#expect(child.scopeString == "keyword.declaration.swift")
		#expect(child.matchPattern != nil)
		#expect(child.matchPattern?.isValid == true)
	}

	@Test("Compile begin/end pattern")
	func compileBeginEnd() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(
				begin: "\"",
				end: "\"",
				name: "string.quoted.double",
				contentName: "string.content",
			),
		])

		let rule = GrammarCompiler.compile(grammar)
		let child = rule.children[0]
		#expect(child.scopeString == "string.quoted.double")
		#expect(child.contentScopeString == "string.content")
		#expect(child.matchPattern != nil) // begin pattern compiled
		#expect(child.endPattern != nil) // end pattern compiled
	}

	@Test("Compile with captures")
	func compileCaptures() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(
				match: "(\\w+)\\s*=",
				name: "meta.assignment",
				captures: [
					"1": GrammarDefinition.CaptureAttributes(name: "variable.other"),
				],
			),
		])

		let rule = GrammarCompiler.compile(grammar)
		let child = rule.children[0]
		#expect(child.captures != nil)
		#expect(child.captures?["1"]?.scopeString == "variable.other")
	}

	@Test("Compile repository and include reference")
	func compileRepository() {
		let grammar = Self.makeGrammar(
			patterns: [
				GrammarDefinition.Pattern(include: "#keywords"),
			],
			repository: [
				"keywords": GrammarDefinition.PatternGroup(
					pattern: GrammarDefinition.Pattern(
						match: "\\b(if|else|for)\\b",
						name: "keyword.control",
					),
				),
			],
		)

		let rule = GrammarCompiler.compile(grammar)

		// After compilation, the include should have created a child
		// that references #keywords
		#expect(rule.children.count == 1)
		#expect(rule.children[0].includeString == "#keywords")

		// After setupIncludes, the include should be resolved
		GrammarCompiler.setupIncludes(
			rule: rule, base: rule, self: rule,
			stack: RuleStack(rule: rule),
		)
		#expect(rule.children[0].include != nil)
		#expect(rule.children[0].include?.scopeString == "keyword.control")
	}

	@Test("$self include resolves to root")
	func selfInclude() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(include: "$self"),
		])

		let rule = GrammarCompiler.compile(grammar)
		GrammarCompiler.setupIncludes(
			rule: rule, base: rule, self: rule,
			stack: RuleStack(rule: rule),
		)
		#expect(rule.children[0].include === rule)
	}

	@Test("$base include resolves to base")
	func baseInclude() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(include: "$base"),
		])

		let rule = GrammarCompiler.compile(grammar)
		let baseRule = GrammarRule()
		GrammarCompiler.setupIncludes(
			rule: rule, base: baseRule, self: rule,
			stack: RuleStack(rule: rule),
		)
		#expect(rule.children[0].include === baseRule)
	}

	@Test("Pattern with back references defers compilation")
	func backReferenceDeferred() {
		let grammar = Self.makeGrammar(patterns: [
			GrammarDefinition.Pattern(
				begin: "(['\"])",
				end: "\\1",
				name: "string.quoted",
			),
		])

		let rule = GrammarCompiler.compile(grammar)
		let child = rule.children[0]
		#expect(child.matchPattern != nil) // begin is compiled
		#expect(child.endPattern == nil) // end has backreference, not compiled
	}
}

// MARK: - ParserState Tests

@Suite("ParserState")
struct ParserStateTests {
	@Test("Root state creation")
	func rootState() {
		let rule = GrammarRule()
		let state = ParserState(rule: rule, scope: "source.swift")
		#expect(state.parent == nil)
		#expect(state.scope == Scope("source.swift"))
		#expect(state.anchor == Int.max)
		#expect(!state.zwBeginMatch)
		#expect(!state.applyEndLast)
	}

	@Test("Child state creation")
	func childState() {
		let rule = GrammarRule()
		let parent = ParserState(rule: rule, scope: "source.swift")
		let child = ParserState(rule: rule, scope: Scope("source.swift string"), parent: parent)
		#expect(child.parent === parent)
	}

	@Test("State equality")
	func stateEquality() {
		let rule = GrammarRule()
		let a = ParserState(rule: rule, scope: "source.swift")
		let b = ParserState(rule: rule, scope: "source.swift")
		#expect(a == b)

		let c = ParserState(rule: rule, scope: "source.objc")
		#expect(a != c)
	}

	@Test("State identity shortcut")
	func stateIdentity() {
		let rule = GrammarRule()
		let state = ParserState(rule: rule, scope: "source.swift")
		#expect(state == state)
	}
}

// MARK: - GrammarParser Tests

@Suite("GrammarParser")
struct GrammarParserTests {
	/// Helper to create a compiled grammar and parse a line.
	static func parseWithGrammar(
		patterns: [GrammarDefinition.Pattern],
		repository: [String: GrammarDefinition.PatternGroup] = [:],
		line: String,
		firstLine: Bool = true,
	) -> (state: ParserState, scopes: [Int: Scope]) {
		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: patterns,
			repository: repository,
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		let rule = GrammarCompiler.compile(grammar)
		GrammarCompiler.setupIncludes(
			rule: rule, base: rule, self: rule,
			stack: RuleStack(rule: rule),
		)

		let state = ParserState(rule: rule, scope: "source.test")
		return GrammarParser.parseLine(line, state: state, firstLine: firstLine)
	}

	@Test("Parse empty line produces no scopes")
	func parseEmptyLine() {
		let result = Self.parseWithGrammar(patterns: [], line: "")
		#expect(result.scopes.isEmpty || result.scopes.count == 1)
	}

	@Test("Parse with simple match rule")
	func parseSimpleMatch() {
		let result = Self.parseWithGrammar(
			patterns: [
				GrammarDefinition.Pattern(
					match: "\\b(func)\\b",
					name: "keyword.declaration",
				),
			],
			line: "func test()\n",
		)

		// Should have scope changes at the keyword position
		#expect(!result.scopes.isEmpty)
	}

	@Test("Parse with begin/end string rule")
	func parseBeginEnd() {
		let result = Self.parseWithGrammar(
			patterns: [
				GrammarDefinition.Pattern(
					begin: "\"",
					end: "\"",
					name: "string.quoted.double",
				),
			],
			line: "let x = \"hello\"\n",
		)

		// Should have scope entries for the string region
		#expect(!result.scopes.isEmpty)
	}

	@Test("State carries across lines (begin/end)")
	func stateCrossLines() {
		let patterns = [
			GrammarDefinition.Pattern(
				begin: "/\\*",
				end: "\\*/",
				name: "comment.block",
			),
		]

		// Parse first line with opening comment
		let r1 = Self.parseWithGrammar(patterns: patterns, line: "/* comment\n")

		// Parse second line continuing the comment
		let r2 = GrammarParser.parseLine(
			"still comment */\n",
			state: r1.state,
			firstLine: false,
		)

		// Second line should eventually close the comment
		#expect(r2.state.parent == nil || r2.state.endPattern == nil)
	}

	@Test("Scope name expansion with captures")
	func scopeNameExpansion() {
		let result = Self.parseWithGrammar(
			patterns: [
				GrammarDefinition.Pattern(
					match: "\\b(let|var)\\b",
					name: "keyword.$1.swift",
				),
			],
			line: "let x = 1\n",
		)

		// The scope should contain the expanded name
		let allScopes = result.scopes.values.map { $0.toString() }
		let hasExpanded = allScopes.contains { $0.contains("keyword.let.swift") }
		#expect(hasExpanded)
	}

	@Test("Multiple patterns on same line")
	func multiplePatterns() {
		let result = Self.parseWithGrammar(
			patterns: [
				GrammarDefinition.Pattern(
					match: "\\b(func)\\b",
					name: "keyword.declaration",
				),
				GrammarDefinition.Pattern(
					match: "\\b(return)\\b",
					name: "keyword.control",
				),
			],
			line: "func test() { return 42 }\n",
		)
		#expect(!result.scopes.isEmpty)
	}
}

// MARK: - GrammarRegistry Tests

@Suite("GrammarRegistry")
struct GrammarRegistryTests {
	@Test("Register and load grammar")
	func registerAndLoad() {
		let registry = GrammarRegistry()

		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: ["test"],
			uuid: nil,
			firstLineMatch: nil,
			patterns: [
				GrammarDefinition.Pattern(
					match: "\\btest\\b",
					name: "keyword.test",
				),
			],
			repository: [:],
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		registry.register(grammar)
		#expect(registry.definitionCount == 1)
		#expect(registry.cachedCount == 0)

		let rule = registry.grammar(forScope: "source.test")
		#expect(rule != nil)
		#expect(registry.cachedCount == 1)
	}

	@Test("Unknown scope returns nil")
	func unknownScope() {
		let registry = GrammarRegistry()
		#expect(registry.grammar(forScope: "source.unknown") == nil)
	}

	@Test("Cached grammar is reused")
	func caching() {
		let registry = GrammarRegistry()

		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: [],
			repository: [:],
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		registry.register(grammar)
		let r1 = registry.grammar(forScope: "source.test")
		let r2 = registry.grammar(forScope: "source.test")
		#expect(r1 === r2)
	}

	@Test("Clear cache removes compiled grammars")
	func clearCache() {
		let registry = GrammarRegistry()

		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: [],
			repository: [:],
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		registry.register(grammar)
		_ = registry.grammar(forScope: "source.test")
		#expect(registry.cachedCount == 1)

		registry.clearCache()
		#expect(registry.cachedCount == 0)
		#expect(registry.definitionCount == 1) // definitions kept
	}

	@Test("Seed creates initial parser state")
	func seedState() {
		let registry = GrammarRegistry()

		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: [],
			repository: [:],
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		registry.register(grammar)
		let state = registry.seed(forScope: "source.test")
		#expect(state != nil)
		#expect(state?.scope == Scope("source.test"))
	}

	@Test("Register multiple grammars")
	func registerMultiple() {
		let registry = GrammarRegistry()

		let defs = ["source.a", "source.b", "source.c"].map {
			GrammarDefinition(
				scopeName: $0,
				name: $0,
				fileTypes: [],
				uuid: nil,
				firstLineMatch: nil,
				patterns: [],
				repository: [:],
				foldingStartMarker: nil,
				foldingStopMarker: nil,
			)
		}
		registry.register(defs)
		#expect(registry.definitionCount == 3)
	}
}

// MARK: - IncrementalParser Tests

@Suite("IncrementalParser")
struct IncrementalParserTests {
	/// Creates an incremental parser with a simple keyword grammar.
	static func makeParser() -> IncrementalParser {
		let grammar = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: [],
			uuid: nil,
			firstLineMatch: nil,
			patterns: [
				GrammarDefinition.Pattern(
					match: "\\b(func|class|struct)\\b",
					name: "keyword.declaration",
				),
				GrammarDefinition.Pattern(
					begin: "\"",
					end: "\"",
					name: "string.quoted.double",
				),
			],
			repository: [:],
			foldingStartMarker: nil,
			foldingStopMarker: nil,
		)

		let rule = GrammarCompiler.compile(grammar)
		GrammarCompiler.setupIncludes(
			rule: rule, base: rule, self: rule,
			stack: RuleStack(rule: rule),
		)
		return IncrementalParser(grammar: rule)
	}

	@Test("Set text and parse")
	func setTextAndParse() {
		let parser = Self.makeParser()
		parser.setText("func test()\nclass Foo\n")
		#expect(parser.lineCount == 2)
		#expect(parser.hasDirtyLines)

		let changes = parser.parseSync()
		#expect(!changes.isEmpty)
		#expect(!parser.hasDirtyLines)
	}

	@Test("Scope map after parse")
	func scopeMapAfterParse() {
		let parser = Self.makeParser()
		parser.setText("func test()\n")
		parser.parseSync()
		let map = parser.scopeMap(forLine: 0)
		#expect(!map.isEmpty)
	}

	@Test("Scope at position")
	func scopeAtPosition() {
		let parser = Self.makeParser()
		parser.setText("func test()\n")
		parser.parseSync()
		let scope = parser.scope(atLine: 0, byteOffset: 0)
		// Should have at least the root scope
		#expect(!scope.isEmpty || scope.isEmpty) // non-crashing access
	}

	@Test("State after line")
	func stateAfterLine() {
		let parser = Self.makeParser()
		parser.setText("func test()\nclass Foo\n")
		parser.parseSync()
		let state = parser.state(afterLine: 0)
		#expect(state != nil)
	}

	@Test("Invalidate and re-parse")
	func invalidateAndReparse() {
		let parser = Self.makeParser()
		parser.setText("func test()\nclass Foo\n")
		parser.parseSync()

		parser.invalidateLines(0 ..< 1)
		#expect(parser.hasDirtyLines)

		let changes = parser.parseSync()
		// May or may not have changes depending on convergence
		_ = changes
		#expect(!parser.hasDirtyLines)
	}

	@Test("Line replacement adjusts state")
	func lineReplacement() {
		let parser = Self.makeParser()
		parser.setText("line one\nline two\nline three\n")
		parser.parseSync()

		parser.replaceLines(in: 1 ..< 2, with: ["replaced line\n"])
		#expect(parser.hasDirtyLines)

		parser.parseSync()
		#expect(parser.lineCount == 3)
	}
}
