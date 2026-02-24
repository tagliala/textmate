import Foundation
import TMBundle

/// A compiled grammar rule, equivalent to C++ `parse::rule_t`.
///
/// This is the internal representation used by the parse engine.
/// Created by `GrammarCompiler` from `GrammarDefinition.Pattern`.
public final class GrammarRule: @unchecked Sendable {
	/// Unique identifier for this rule (used for caching).
	public let ruleID: Int

	/// Scope name string (may contain `$` format references).
	public var scopeString: String?

	/// Content scope name string (for begin/end regions).
	public var contentScopeString: String?

	/// Include reference string (`$self`, `$base`, `#name`, `scope#name`).
	public var includeString: String?

	/// Match/begin pattern string (Oniguruma regex).
	public var matchString: String?

	/// While pattern string (Oniguruma regex).
	public var whileString: String?

	/// End pattern string (Oniguruma regex).
	public var endString: String?

	/// Whether to apply end pattern last (applyEndPatternLast = "1").
	public var applyEndLast: String?

	/// Child rules (from `patterns` array).
	public var children: [GrammarRule] = []

	/// Capture group rules (for `match` or shared `captures`).
	public var captures: [String: GrammarRule]?

	/// Begin-specific capture group rules.
	public var beginCaptures: [String: GrammarRule]?

	/// While-specific capture group rules.
	public var whileCaptures: [String: GrammarRule]?

	/// End-specific capture group rules.
	public var endCaptures: [String: GrammarRule]?

	/// Repository of named reusable rules.
	public var repository: [String: GrammarRule]?

	/// Injection rules (selector → rule).
	public var injectionRules: [String: GrammarRule]?

	/// Compiled injections (selector + rule pairs).
	public var injections: [(selector: ScopeSelector, rule: GrammarRule)] = []

	// MARK: - Pre-compiled patterns

	/// Compiled match/begin pattern.
	public var matchPattern: OnigmoPattern?

	/// Compiled while pattern (nil if has back references).
	public var whilePattern: OnigmoPattern?

	/// Compiled end pattern (nil if has back references).
	public var endPattern: OnigmoPattern?

	/// Whether the match pattern contains `\G`.
	public var matchPatternIsAnchored: Bool = false

	// MARK: - Mutable state (used during include resolution)

	/// Resolved include target.
	public var include: GrammarRule?

	/// Used to prevent infinite recursion during include resolution.
	public var included: Bool = false

	/// Whether this is a root grammar rule.
	public var isRoot: Bool = false

	// MARK: - ID counter

	private nonisolated(unsafe) static var nextID = 0
	private static let idLock = NSLock()

	private static func allocateID() -> Int {
		idLock.lock()
		defer { idLock.unlock() }
		let id = nextID
		nextID += 1
		return id
	}

	public init() {
		ruleID = Self.allocateID()
	}
}

// MARK: - GrammarCompiler

/// Converts `GrammarDefinition` (plist data model) into a compiled
/// `GrammarRule` tree ready for the parse engine.
///
/// Mirrors C++ `convert_plist()` and `compile_patterns()`.
enum GrammarCompiler {
	/// Converts a `GrammarDefinition` into a root `GrammarRule`.
	static func compile(_ grammar: GrammarDefinition) -> GrammarRule {
		let root = convertPatternToRule(grammar)
		compilePatterns(root)
		return root
	}

	/// Converts a grammar definition's top-level structure to a rule.
	static func convertPatternToRule(_ grammar: GrammarDefinition) -> GrammarRule {
		let rule = GrammarRule()
		rule.scopeString = grammar.scopeName
		rule.children = grammar.patterns.map { convertPattern($0) }

		// Convert repository
		if !grammar.repository.isEmpty {
			var repo: [String: GrammarRule] = [:]
			for (key, group) in grammar.repository {
				if let pattern = group.pattern {
					repo[key] = convertPattern(pattern)
				} else if let patterns = group.patterns {
					let groupRule = GrammarRule()
					groupRule.children = patterns.map { convertPattern($0) }
					repo[key] = groupRule
				}
			}
			rule.repository = repo
		}

		return rule
	}

	/// Converts a single `GrammarDefinition.Pattern` to a `GrammarRule`.
	static func convertPattern(_ pattern: GrammarDefinition.Pattern) -> GrammarRule {
		let rule = GrammarRule()

		// Scope names
		rule.scopeString = pattern.name

		// Match/begin pattern
		if let begin = pattern.begin {
			rule.matchString = begin
			rule.endString = pattern.end
			rule.contentScopeString = pattern.contentName
			if let w = pattern.whilePattern {
				rule.whileString = w
			}
		} else if let match = pattern.match {
			rule.matchString = match
		}

		// Include
		rule.includeString = pattern.include

		// Children
		if let patterns = pattern.patterns {
			rule.children = patterns.map { convertPattern($0) }
		}

		// Captures
		rule.captures = convertCaptures(pattern.captures)
		rule.beginCaptures = convertCaptures(pattern.beginCaptures)
		rule.endCaptures = convertCaptures(pattern.endCaptures)

		return rule
	}

	/// Converts capture definitions to capture rules.
	private static func convertCaptures(
		_ captures: [String: GrammarDefinition.CaptureAttributes]?,
	) -> [String: GrammarRule]? {
		guard let captures, !captures.isEmpty else { return nil }

		var result: [String: GrammarRule] = [:]
		for (key, attrs) in captures {
			let rule = GrammarRule()
			rule.scopeString = attrs.name
			if let patterns = attrs.patterns {
				rule.children = patterns.map { convertPattern($0) }
			}
			result[key] = rule
		}
		return result
	}

	// MARK: - Pattern Compilation

	/// Compiles regex patterns in a rule tree.
	/// Mirrors C++ `compile_patterns()`.
	static func compilePatterns(_ rule: GrammarRule) {
		if let matchStr = rule.matchString {
			rule.matchPattern = OnigmoPattern(matchStr)
			rule.matchPatternIsAnchored = patternHasAnchor(matchStr)

			if rule.matchPattern?.isValid != true {
				// Log compilation error silently
			}
		}

		if let whileStr = rule.whileString, !patternHasBackReference(whileStr) {
			rule.whilePattern = OnigmoPattern(whileStr)
		}

		if let endStr = rule.endString, !patternHasBackReference(endStr) {
			rule.endPattern = OnigmoPattern(endStr)
		}

		// Recurse into children
		for child in rule.children {
			compilePatterns(child)
		}

		// Recurse into repository and capture maps
		let maps: [[String: GrammarRule]?] = [
			rule.repository, rule.injectionRules,
			rule.captures, rule.beginCaptures,
			rule.whileCaptures, rule.endCaptures,
		]
		for map in maps {
			guard let map else { continue }
			for (_, subrule) in map {
				compilePatterns(subrule)
			}
		}

		// Convert injection rules to injections array
		if let injRules = rule.injectionRules {
			for (selectorStr, injRule) in injRules {
				let selector = ScopeSelector(selectorStr)
				rule.injections.append((selector: selector, rule: injRule))
			}
			rule.injectionRules = nil
		}
	}

	// MARK: - Include Resolution

	/// Resolves `include` references throughout the rule tree.
	/// Mirrors C++ `grammar_t::setup_includes()`.
	static func setupIncludes(
		rule: GrammarRule,
		base: GrammarRule,
		self selfRule: GrammarRule,
		stack: RuleStack,
	) {
		guard rule.include == nil else { return }

		let includeStr = rule.includeString
		if includeStr == "$base" {
			rule.include = base
		} else if includeStr == "$self" {
			rule.include = selfRule
		} else if let includeStr, !includeStr.isEmpty {
			if includeStr.hasPrefix("#") {
				// Repository reference
				let name = String(includeStr.dropFirst())
				var node: RuleStack? = stack
				while let current = node, rule.include == nil {
					rule.include = current.rule.repository?[name]
					node = current.parent
				}
			}
			// External grammar references (scope#name) are handled
			// by the GrammarRegistry at a higher level.

			// Don't log errors for external references — they'll be
			// resolved when the referenced grammar is loaded.
		} else if includeStr == nil || includeStr?.isEmpty == true {
			// No include — recurse into children
			for child in rule.children {
				setupIncludes(
					rule: child, base: base, self: selfRule,
					stack: RuleStack(rule: rule, parent: stack),
				)
			}

			let maps: [[String: GrammarRule]?] = [
				rule.repository, rule.injectionRules,
				rule.captures, rule.beginCaptures,
				rule.whileCaptures, rule.endCaptures,
			]
			for map in maps {
				guard let map else { continue }
				for (_, subrule) in map {
					setupIncludes(
						rule: subrule, base: base, self: selfRule,
						stack: RuleStack(rule: rule, parent: stack),
					)
				}
			}
		}
	}
}

// MARK: - RuleStack (for include resolution)

/// A stack of rules used during include resolution to walk up the
/// repository hierarchy. Mirrors C++ `grammar_t::rule_stack_t`.
public final class RuleStack {
	public let rule: GrammarRule
	public let parent: RuleStack?

	public init(rule: GrammarRule, parent: RuleStack? = nil) {
		self.rule = rule
		self.parent = parent
	}
}
