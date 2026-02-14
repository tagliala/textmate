import Foundation

/// Maximum line size in bytes before the parser truncates.
private let kParserMaxLineSize = 4096

// MARK: - ScopeTracker

/// Tracks scope additions and removals at specific byte positions.
/// Mirrors C++ `scopes_t` from parse.cc.
struct ScopeTracker {
	struct Record {
		let scope: String
		let isAdd: Bool
	}

	/// Ordered map of position → records.
	private var records: [(position: Int, record: Record)] = []

	/// Stack for cycle-detection tracking.
	var tracking: Int = 0
	var stack: [String] = []

	/// Adds a scope at the given position.
	mutating func add(_ position: Int, scope: String) {
		if tracking > 0 {
			stack.append(scope)
		}
		records.append((position: position, record: Record(scope: scope, isAdd: true)))
	}

	/// Removes a scope at the given position.
	mutating func remove(_ position: Int, scope: String, endRule _: Bool = false) {
		// For end rules, append at the end; otherwise insert at sorted position
		records.append((position: position, record: Record(scope: scope, isAdd: false)))

		if tracking > 0 {
			if let last = stack.last, last == scope {
				stack.removeLast()
			}
		}
	}

	/// Updates a scope by walking through recorded changes, producing
	/// a `position → scope` map.
	func update(_ initialScope: Scope, into map: inout [Int: Scope]) -> Scope {
		var scope = initialScope
		var pos = 0

		// Sort records by position for proper ordering
		let sorted = records.sorted { $0.position < $1.position }

		for entry in sorted {
			if pos != entry.position {
				map[pos] = scope
				pos = entry.position
			}

			if entry.record.isAdd {
				scope.pushScope(entry.record.scope)
			} else {
				// Remove the specified scope, handling out-of-order removal
				if scope.back == entry.record.scope {
					scope.popScope()
				} else {
					// Must search for and remove the scope
					var tempStack: [String] = []
					while scope.back != entry.record.scope, !scope.isEmpty {
						tempStack.append(scope.back!)
						scope.popScope()
					}
					if !scope.isEmpty {
						scope.popScope()
					}
					for s in tempStack.reversed() {
						scope.pushScope(s)
					}
				}
			}
		}

		map[pos] = scope
		return scope
	}
}

// MARK: - RankedMatch

/// A match result with its associated rule and priority ranking.
struct RankedMatch: Comparable {
	let rule: GrammarRule
	var match: OnigmoMatch
	let rank: Int
	let isEndPattern: Bool

	static func < (lhs: RankedMatch, rhs: RankedMatch) -> Bool {
		if lhs.match.matchBegin == rhs.match.matchBegin {
			return lhs.rank < rhs.rank
		}
		return lhs.match.matchBegin < rhs.match.matchBegin
	}

	static func == (lhs: RankedMatch, rhs: RankedMatch) -> Bool {
		lhs.match.matchBegin == rhs.match.matchBegin && lhs.rank == rhs.rank
	}
}

// MARK: - GrammarParser

/// The TextMate grammar parse engine.
///
/// Parses a line of text against a grammar and produces a map
/// of byte positions to scopes. This is the core of syntax highlighting.
///
/// Mirrors the C++ `parse::parse()` function.
public enum GrammarParser {
	/// Parses a single line of text.
	///
	/// - Parameters:
	///   - line: The UTF-8 text of the line (including trailing newline).
	///   - state: The parser state from the end of the previous line.
	///   - firstLine: Whether this is the first line of the document.
	/// - Returns: A tuple of (new state, scope map).
	public static func parseLine(
		_ line: String,
		state: ParserState,
		firstLine: Bool = false,
	) -> (state: ParserState, scopes: [Int: Scope]) {
		var buffer = Array(line.utf8)

		// Truncate very long lines
		if buffer.count > kParserMaxLineSize {
			// Find a safe UTF-8 boundary
			var end = kParserMaxLineSize
			while end > 0, (buffer[end] & 0xC0) == 0x80 {
				end -= 1
			}
			buffer = Array(buffer[..<end])
		}

		var scopes = ScopeTracker()
		let newState = parse(
			buffer: buffer, state: state,
			scopes: &scopes, firstLine: firstLine, startOffset: 0,
		)

		var scopeMap: [Int: Scope] = [:]
		newState.scope = scopes.update(state.scope, into: &scopeMap)
		return (state: newState, scopes: scopeMap)
	}

	// MARK: - Core Parse Loop

	/// The main parse function. Processes a line of text against the
	/// grammar rules from the current parser state.
	static func parse(
		buffer: [UInt8],
		state: ParserState,
		scopes: inout ScopeTracker,
		firstLine: Bool,
		startOffset i: Int,
	) -> ParserState {
		var stack = state
		var i = i

		// ==============================
		// = Apply the 'while' patterns =
		// ==============================

		var whileRules: [ParserState] = []
		var node: ParserState? = stack
		while let n = node, n.whilePattern != nil {
			whileRules.append(n)
			if let ss = n.scopeString {
				scopes.remove(i, scope: ss, endRule: true)
			}
			if let css = n.contentScopeString {
				scopes.remove(i, scope: css, endRule: true)
			}
			node = n.parent
		}

		var scope = whileRules.isEmpty
			? stack.scope
			: (whileRules.last?.parent?.scope ?? Scope())

		for ruleState in whileRules.reversed() {
			guard let whilePattern = ruleState.whilePattern else { break }

			if let m = whilePattern.search(
				in: buffer, range: i ..< buffer.count,
			) {
				let rule = ruleState.rule
				if let ss = rule.scopeString {
					let expanded = expandScopeName(ss, match: m)
					scope.pushScope(expanded)
					scopes.add(m.matchBegin, scope: expanded)
				}

				applyCaptures(
					scope: scope, match: m,
					captures: rule.whileCaptures ?? rule.captures,
					buffer: buffer, scopes: &scopes, firstLine: firstLine,
				)

				if let css = rule.contentScopeString {
					let expanded = expandScopeName(css, match: m)
					scope.pushScope(expanded)
					scopes.add(m.matchEnd, scope: expanded)
				}

				stack.anchor = m.matchEnd
				i = m.matchEnd
				continue
			}

			// While pattern didn't match — pop back to its parent
			if let parent = ruleState.parent {
				stack = parent
			}
			if stack.whilePattern != nil {
				stack.anchor = i
			}
			break
		}

		// ======================
		// = Parse rest of line =
		// ======================

		var rules = collectAndMatchRules(
			buffer: buffer, offset: i, firstLine: firstLine, state: stack,
		)

		while let best = rules.min() {
			rules.removeAll { $0 == best }
			let m = best

			if m.match.matchBegin < i {
				// Match is behind current position — re-search
				let ptrn: OnigmoPattern? = if m.isEndPattern {
					stack.endPattern
				} else {
					m.rule.matchPattern
				}

				if let ptrn,
				   let newMatch = ptrn.search(in: buffer, range: i ..< buffer.count)
				{
					var updated = m
					updated.match = newMatch
					rules.append(updated)
				}
				continue
			}

			i = m.match.matchEnd

			if m.isEndPattern {
				// End pattern matched — pop the current context
				if let css = stack.contentScopeString {
					scopes.remove(m.match.matchBegin, scope: css, endRule: true)
				}

				applyCaptures(
					scope: scope, match: m.match,
					captures: m.rule.endCaptures ?? m.rule.captures,
					buffer: buffer, scopes: &scopes, firstLine: firstLine,
				)

				if let ss = stack.scopeString {
					scopes.remove(m.match.matchEnd, scope: ss, endRule: true)
				}

				let nothingMatched = stack.zwBeginMatch && stack.anchor == i

				if let parent = stack.parent {
					stack = parent
					scope = stack.scope
				}

				if nothingMatched {
					break
				}
			} else if m.rule.whileString != nil || m.rule.endString != nil {
				// Begin part of a begin/end or begin/while rule
				if m.match.isEmpty, hasCycle(m.rule.ruleID, offset: i, state: stack) {
					break
				}

				let newState = ParserState(
					rule: m.rule, scope: Scope(), parent: stack,
				)

				if let ss = m.rule.scopeString {
					newState.scopeString = expandScopeName(ss, match: m.match)
					scope.pushScope(newState.scopeString!)
					scopes.add(m.match.matchBegin, scope: newState.scopeString!)
				}

				applyCaptures(
					scope: scope, match: m.match,
					captures: m.rule.beginCaptures ?? m.rule.captures,
					buffer: buffer, scopes: &scopes, firstLine: firstLine,
				)

				if let css = m.rule.contentScopeString {
					newState.contentScopeString = expandScopeName(
						css, match: m.match,
					)
					scope.pushScope(newState.contentScopeString!)
					scopes.add(m.match.matchEnd, scope: newState.contentScopeString!)
				}

				newState.scope = scope
				newState.whilePattern = m.rule.whilePattern
				newState.endPattern = m.rule.endPattern
				newState.applyEndLast = m.rule.applyEndLast == "1"
				newState.anchor = i
				newState.zwBeginMatch = m.match.isEmpty
				stack.anchor = Int.max

				// Expand back references for while/end patterns if needed
				if newState.whilePattern == nil, let ws = m.rule.whileString {
					newState.whilePattern = OnigmoPattern(
						expandBackReferences(ws, match: m.match),
					)
				}
				if newState.endPattern == nil, let es = m.rule.endString {
					newState.endPattern = OnigmoPattern(
						expandBackReferences(es, match: m.match),
					)
				}

				stack = newState
			} else {
				// Simple match rule
				if m.match.isEmpty {
					continue // Don't re-apply zero-width matches
				}

				if let ss = m.rule.scopeString {
					let expanded = expandScopeName(ss, match: m.match)
					scopes.add(m.match.matchBegin, scope: expanded)
					scopes.remove(m.match.matchEnd, scope: expanded)
				}

				applyCaptures(
					scope: scope, match: m.match,
					captures: m.rule.captures,
					buffer: buffer, scopes: &scopes, firstLine: firstLine,
				)

				// Re-search for the same pattern after the match
				if let newMatch = m.rule.matchPattern?.search(
					in: buffer, range: i ..< buffer.count,
				) {
					var updated = m
					updated.match = newMatch
					rules.append(updated)
				}

				continue // No context change, skip rule collection
			}

			// Context changed — collect new rules
			rules = collectAndMatchRules(
				buffer: buffer, offset: i, firstLine: firstLine, state: stack,
			)
		}

		// Set anchor for next line
		stack.anchor = (i >= buffer.count) ? 0 : Int.max
		return stack
	}

	// MARK: - Rule Collection

	/// Collects all rules applicable in the current state and matches
	/// them against the remaining text.
	private static func collectAndMatchRules(
		buffer: [UInt8],
		offset i: Int,
		firstLine: Bool,
		state: ParserState,
	) -> [RankedMatch] {
		var childRules: [GrammarRule] = []
		var groups: [GrammarRule] = []
		collectChildren(state.rule.children, into: &childRules, groups: &groups)

		// Collect injections
		var injectedPre: [GrammarRule] = []
		var injectedPost: [GrammarRule] = []
		collectInjections(
			state: state, scope: state.scope, groups: groups,
			pre: &injectedPre, post: &injectedPost,
		)

		// Reset included flags
		for g in groups {
			g.included = false
		}

		// Match rules against text
		var results: [RankedMatch] = []
		var rank = 0

		// Pre-injected rules
		rank = applyRules(
			injectedPre, buffer: buffer, offset: i,
			firstLine: firstLine, state: state, startRank: rank,
			results: &results,
		)

		let endPatternRank = rank + 1
		rank += 1

		// Child rules
		rank = applyRules(
			childRules, buffer: buffer, offset: i,
			firstLine: firstLine, state: state, startRank: rank,
			results: &results,
		)

		// End pattern
		if let endPattern = state.endPattern {
			if let m = endPattern.search(in: buffer, range: i ..< buffer.count) {
				results.append(RankedMatch(
					rule: state.rule, match: m,
					rank: state.applyEndLast ? rank + 1 : endPatternRank,
					isEndPattern: true,
				))
				if state.applyEndLast { rank += 1 }
			}
		}

		// Post-injected rules
		rank = applyRules(
			injectedPost, buffer: buffer, offset: i,
			firstLine: firstLine, state: state, startRank: rank,
			results: &results,
		)

		return results
	}

	/// Matches a list of rules against the text and appends results.
	@discardableResult
	private static func applyRules(
		_ rules: [GrammarRule],
		buffer: [UInt8],
		offset i: Int,
		firstLine _: Bool,
		state _: ParserState,
		startRank: Int,
		results: inout [RankedMatch],
	) -> Int {
		var rank = startRank
		for rule in rules {
			rule.included = false

			guard let pattern = rule.matchPattern else { continue }
			if let m = pattern.search(in: buffer, range: i ..< buffer.count) {
				rank += 1
				results.append(RankedMatch(
					rule: rule, match: m, rank: rank, isEndPattern: false,
				))
			}
		}
		return rank
	}

	// MARK: - Rule Tree Walking

	/// Collects match-capable rules from children, following includes.
	static func collectChildren(
		_ children: [GrammarRule],
		into rules: inout [GrammarRule],
		groups: inout [GrammarRule],
	) {
		for child in children {
			collectRule(child, into: &rules, groups: &groups)
		}
	}

	/// Collects a single rule, following include chains.
	private static func collectRule(
		_ rule: GrammarRule,
		into rules: inout [GrammarRule],
		groups: inout [GrammarRule],
	) {
		var current: GrammarRule? = rule

		// Follow include chain
		while let r = current, r.include != nil, !r.included {
			r.included = true
			groups.append(r)
			current = r.include
		}

		guard let r = current, !r.included else { return }

		if r.matchPattern != nil {
			r.included = true
			rules.append(r)
		} else if !r.children.isEmpty {
			r.included = true
			groups.append(r)
			collectChildren(r.children, into: &rules, groups: &groups)
		}
	}

	/// Collects injection rules that match the current scope.
	private static func collectInjections(
		state: ParserState,
		scope: Scope,
		groups: [GrammarRule],
		pre: inout [GrammarRule],
		post: inout [GrammarRule],
	) {
		let context = ScopeContext(scope)

		// Walk up the state stack
		var node: ParserState? = state
		while let n = node {
			for (selector, rule) in n.rule.injections {
				if selector.doesMatch(context) != nil {
					var dummy: [GrammarRule] = []
					collectRule(rule, into: &pre, groups: &dummy)
				}
			}
			node = n.parent
		}

		// Check groups
		for group in groups {
			if group.isRoot { continue }
			for (selector, rule) in group.injections {
				if selector.doesMatch(context) != nil {
					var dummy: [GrammarRule] = []
					collectRule(rule, into: &post, groups: &dummy)
				}
			}
		}
	}

	// MARK: - Captures

	/// Applies capture group rules to scoped regions.
	private static func applyCaptures(
		scope: Scope,
		match: OnigmoMatch,
		captures: [String: GrammarRule]?,
		buffer: [UInt8],
		scopes: inout ScopeTracker,
		firstLine: Bool,
	) {
		guard let captures, !captures.isEmpty else { return }

		// Build sorted list of (position, length, rule) for matching captures
		var captureRules: [(from: Int, to: Int, rule: GrammarRule)] = []

		for (key, rule) in captures {
			guard let index = Int(key) else { continue }
			guard match.didMatch(index) else { continue }
			let from = match.begin(index)
			let to = match.end(index)
			guard from != to else { continue }
			captureRules.append((from: from, to: to, rule: rule))
		}

		// Sort by position, then by length (longer matches first)
		captureRules.sort { a, b in
			if a.from != b.from { return a.from < b.from }
			return (a.to - a.from) > (b.to - b.from)
		}

		for (from, to, rule) in captureRules {
			if let ss = rule.scopeString {
				let expanded = expandScopeName(ss, match: match)
				scopes.add(from, scope: expanded)
				scopes.remove(to, scope: expanded)
			}

			if !rule.children.isEmpty {
				let captureState = ParserState(
					rule: rule, scope: scope, parent: ParserState(rule: rule, scope: ""),
				)
				captureState.anchor = from

				let savedStack = scopes.stack
				scopes.tracking += 1
				_ = parse(
					buffer: Array(buffer[0 ..< to]),
					state: captureState,
					scopes: &scopes,
					firstLine: firstLine,
					startOffset: from,
				)
				// Remove any scopes that were opened but not closed
				while !scopes.stack.isEmpty {
					scopes.remove(to, scope: scopes.stack.last!, endRule: true)
				}
				scopes.tracking -= 1
				scopes.stack = savedStack
			}
		}
	}

	// MARK: - Utility

	/// Checks for infinite recursion in begin/end rules.
	private static func hasCycle(
		_ ruleID: Int, offset i: Int, state: ParserState,
	) -> Bool {
		if !state.zwBeginMatch || state.anchor != i {
			return false
		}
		if ruleID == state.rule.ruleID {
			return true
		}
		if let parent = state.parent {
			return hasCycle(ruleID, offset: i, state: parent)
		}
		return false
	}

	/// Expands format string references in a scope name.
	private static func expandScopeName(
		_ name: String, match: OnigmoMatch,
	) -> String {
		guard patternIsFormatString(name) else { return name }
		return expandFormatString(name, captures: match.captures)
	}
}
