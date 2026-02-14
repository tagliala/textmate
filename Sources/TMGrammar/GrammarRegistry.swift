import Foundation
import TMBundle

/// Registry of loaded TextMate grammars, providing grammar lookup by scope
/// name and handling cross-grammar includes.
///
/// Mirrors C++ `parse::grammar_t` (the grammar manager aspects).
public final class GrammarRegistry: @unchecked Sendable {
	/// Cached grammars keyed by scope name.
	private var grammars: [String: GrammarRule] = [:]

	/// Grammar definitions available for loading (scope → definition).
	private var definitions: [String: GrammarDefinition] = [:]

	/// Lock for thread-safe access.
	private let lock = NSLock()

	public init() {}

	// MARK: - Registration

	/// Registers a grammar definition for later loading.
	public func register(_ definition: GrammarDefinition) {
		lock.lock()
		defer { lock.unlock() }
		definitions[definition.scopeName] = definition
	}

	/// Registers multiple grammar definitions.
	public func register(_ defs: [GrammarDefinition]) {
		lock.lock()
		defer { lock.unlock() }
		for d in defs {
			definitions[d.scopeName] = d
		}
	}

	// MARK: - Loading

	/// Loads and compiles a grammar for the given scope name.
	///
	/// Returns a compiled `GrammarRule` with all includes resolved,
	/// or `nil` if no grammar is registered for the scope.
	public func grammar(forScope scope: String) -> GrammarRule? {
		lock.lock()
		if let cached = grammars[scope] {
			lock.unlock()
			return cached
		}
		guard let definition = definitions[scope] else {
			lock.unlock()
			return nil
		}
		lock.unlock()

		return addGrammar(scope: scope, definition: definition, base: nil)
	}

	/// Compiles and registers a grammar.
	private func addGrammar(
		scope: String,
		definition: GrammarDefinition,
		base: GrammarRule?,
	) -> GrammarRule {
		let rule = GrammarCompiler.compile(definition)

		lock.lock()
		grammars[scope] = rule
		lock.unlock()

		// Resolve includes
		let baseRule = base ?? rule
		GrammarCompiler.setupIncludes(
			rule: rule, base: baseRule, self: rule,
			stack: RuleStack(rule: rule)
		)

		// Resolve external grammar references
		resolveExternalIncludes(rule: rule, base: baseRule)

		return rule
	}

	/// Walks the rule tree resolving external grammar references
	/// (those containing a scope name like `"source.swift"` or
	/// `"source.swift#name"`).
	private func resolveExternalIncludes(
		rule: GrammarRule, base: GrammarRule
	) {
		var visited = Set<Int>()
		resolveExternalIncludesRecursive(rule: rule, base: base, visited: &visited)
	}

	private func resolveExternalIncludesRecursive(
		rule: GrammarRule, base: GrammarRule, visited: inout Set<Int>
	) {
		guard !visited.contains(rule.ruleID) else { return }
		visited.insert(rule.ruleID)

		if let includeStr = rule.includeString, rule.include == nil,
			!includeStr.isEmpty,
			!includeStr.hasPrefix("#"),
			includeStr != "$self", includeStr != "$base"
		{
			// External reference: "scope" or "scope#name"
			let parts = includeStr.split(separator: "#", maxSplits: 1)
			let scopeName = String(parts[0])

			if let externalGrammar = findOrLoadGrammar(
				scope: scopeName, base: base
			) {
				if parts.count > 1 {
					// scope#name — look up in repository
					let name = String(parts[1])
					rule.include = externalGrammar.repository?[name]
				} else {
					rule.include = externalGrammar
				}
			}
		}

		// Recurse
		for child in rule.children {
			resolveExternalIncludesRecursive(
				rule: child, base: base, visited: &visited
			)
		}

		let maps: [[String: GrammarRule]?] = [
			rule.repository, rule.captures,
			rule.beginCaptures, rule.whileCaptures, rule.endCaptures,
		]
		for map in maps {
			guard let map else { continue }
			for (_, subrule) in map {
				resolveExternalIncludesRecursive(
					rule: subrule, base: base, visited: &visited
				)
			}
		}
	}

	/// Finds a cached grammar or loads it from definitions.
	private func findOrLoadGrammar(
		scope: String, base: GrammarRule
	) -> GrammarRule? {
		lock.lock()
		if let cached = grammars[scope] {
			lock.unlock()
			return cached
		}
		guard let definition = definitions[scope] else {
			lock.unlock()
			return nil
		}
		lock.unlock()

		return addGrammar(scope: scope, definition: definition, base: base)
	}

	// MARK: - Injection Grammars

	/// Returns all grammar rules that have injection selectors.
	public func injectionGrammars() -> [(selector: ScopeSelector, rule: GrammarRule)] {
		let result: [(selector: ScopeSelector, rule: GrammarRule)] = []

		// Look for grammars with injectionSelector in their definition
		// (This would require extending GrammarDefinition to include
		// injectionSelector; for now, injections come from the grammar's
		// own injection_rules which are handled during compilation.)

		return result
	}

	// MARK: - Seed State

	/// Creates the initial parser state for the given scope name.
	public func seed(forScope scope: String) -> ParserState? {
		guard let rule = grammar(forScope: scope) else { return nil }
		return ParserState(rule: rule, scope: rule.scopeString ?? scope)
	}

	// MARK: - Clearing

	/// Clears all cached grammars (but keeps definitions).
	public func clearCache() {
		lock.lock()
		defer { lock.unlock() }
		grammars.removeAll()
	}

	/// The number of registered grammar definitions.
	public var definitionCount: Int {
		lock.lock()
		defer { lock.unlock() }
		return definitions.count
	}

	/// The number of compiled (cached) grammars.
	public var cachedCount: Int {
		lock.lock()
		defer { lock.unlock() }
		return grammars.count
	}
}
