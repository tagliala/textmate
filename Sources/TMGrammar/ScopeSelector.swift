// TextMate scope selector parser and matcher.
//
// Grammar (from C++ `scope/src/parse.cc`):
// ```
// atom:        «string» | '*'
// scope:       «atom» ('.' «atom»)*
// path:        '^'? «scope» ('>'? «scope»)* '$'?
// group:       '(' «selector» ')'
// filter:      ("L:"|"R:"|"B:") («group» | «path»)
// expression:  '-'? («filter» | «group» | «path»)
// composite:   «expression» ([|&-] «expression»)*
// selector:    «composite» (',' «composite»)*
// ```

import Foundation

// MARK: - Selector Types (mirrors C++ scope::types)

/// A single scope component in a selector path (e.g. `"meta.function"`).
struct SelectorScope {
	var atoms: String = ""
	var anchorToPrevious: Bool = false
}

/// A path in a selector: `^? scope (>? scope)* $?`.
struct SelectorPath {
	var scopes: [SelectorScope] = []
	var anchorToBOL: Bool = false
	var anchorToEOL: Bool = false
}

/// Anything that can match against scopes.
protocol SelectorMatchable: Sendable {
	func doesMatch(left: Scope, right: Scope, rank: inout Double) -> Bool
}

/// A path matcher.
final class PathMatcher: SelectorMatchable, @unchecked Sendable {
	let path: SelectorPath

	init(_ path: SelectorPath) {
		self.path = path
	}

	func doesMatch(left _: Scope, right: Scope, rank: inout Double) -> Bool {
		pathDoesMatch(path, scope: right, rank: &rank)
	}
}

/// A group: `(selector)`.
final class GroupMatcher: SelectorMatchable, @unchecked Sendable {
	let selector: SelectorData

	init(_ selector: SelectorData) {
		self.selector = selector
	}

	func doesMatch(left: Scope, right: Scope, rank: inout Double) -> Bool {
		selector.doesMatch(left: left, right: right, rank: &rank)
	}
}

/// A filter: `L:`, `R:`, or `B:` prefixed matcher.
final class FilterMatcher: SelectorMatchable, @unchecked Sendable {
	enum Side: Character {
		case left = "L"
		case right = "R"
		case both = "B"
	}

	let side: Side
	let selector: SelectorMatchable

	init(side: Side, selector: SelectorMatchable) {
		self.side = side
		self.selector = selector
	}

	func doesMatch(left: Scope, right: Scope, rank: inout Double) -> Bool {
		switch side {
		case .left:
			return selector.doesMatch(left: left, right: left, rank: &rank)
		case .right:
			return selector.doesMatch(left: right, right: right, rank: &rank)
		case .both:
			var r1: Double = 0
			var r2: Double = 0
			let m1 = selector.doesMatch(left: left, right: left, rank: &r1)
			let m2 = selector.doesMatch(left: right, right: right, rank: &r2)
			if m1, m2 {
				rank = max(r1, r2)
				return true
			}
			return false
		}
	}
}

/// An expression: optional negation + matcher + operator.
struct ExpressionData {
	enum Op: Character {
		case none = "\0"
		case or = "|"
		case and = "&"
		case minus = "-"
	}

	var op: Op
	var negate: Bool = false
	var selector: SelectorMatchable?

	init(op: Op = .none) {
		self.op = op
	}
}

/// A composite: expressions joined by operators.
struct CompositeData {
	var expressions: [ExpressionData] = []

	func doesMatch(left: Scope, right: Scope, rank: inout Double) -> Bool {
		var result = false
		var sum: Double = 0

		for expr in expressions {
			var r: Double = 0
			var local = expr.selector?.doesMatch(left: left, right: right, rank: &r) ?? false
			if local {
				sum = max(r, sum)
			}
			if expr.negate {
				local = !local
			}

			switch expr.op {
			case .none: result = local
			case .or: result = result || local
			case .and: result = result && local
			case .minus: result = result && !local
			}
		}

		if result {
			rank = sum
		}
		return result
	}
}

/// The top-level selector: composites separated by commas.
struct SelectorData: Sendable {
	var composites: [CompositeData] = []

	func doesMatch(left: Scope, right: Scope, rank: inout Double) -> Bool {
		var result = false
		var sum: Double = 0

		for composite in composites {
			var r: Double = 0
			if composite.doesMatch(left: left, right: right, rank: &r) {
				sum = max(r, sum)
				result = true
			}
		}

		if result {
			rank = sum
		}
		return result
	}
}

// MARK: - Sendable conformances

extension CompositeData: @unchecked Sendable {}
extension ExpressionData: @unchecked Sendable {}

// MARK: - Path Matching (mirrors C++ scope::types::path_t::does_match)

/// Matches a scope atom against a selector atom, supporting `*` wildcards.
private func prefixMatch(_ selector: String, _ scope: String) -> Bool {
	var si = selector.startIndex
	var ri = scope.startIndex

	while si < selector.endIndex, ri < scope.endIndex {
		if selector[si] == scope[ri] {
			si = selector.index(after: si)
			ri = scope.index(after: ri)
		} else if selector[si] == "*" {
			si = selector.index(after: si)
			while ri < scope.endIndex, scope[ri] != "." {
				ri = scope.index(after: ri)
			}
		} else {
			return false
		}
	}

	return si == selector.endIndex
		&& (ri == scope.endIndex || scope[ri] == ".")
}

/// Matches a `SelectorPath` against a `Scope`, computing rank score.
private func pathDoesMatch(_ path: SelectorPath, scope: Scope, rank: inout Double) -> Bool {
	var node = scope.currentNode
	var selIdx = path.scopes.count - 1

	var btNode: Scope.Node?
	var btSelIdx = -1
	var btScore: Double = 0

	var power: Double = 0

	// Skip auxiliary scopes when anchored to EOL
	if path.anchorToEOL {
		while let n = node, n.isAuxiliary {
			power += Double(n.numberOfAtoms)
			node = n.parent
		}
		btSelIdx = selIdx
	}

	var score: Double = 0

	while let n = node, selIdx >= 0 {
		power += Double(n.numberOfAtoms)

		let sel = path.scopes[selIdx]

		// Check anchor_to_bol: don't match at the last (top-of-stack) position
		// if there are more scopes above
		let isRedundantNonBOLMatch = path.anchorToBOL && n.parent != nil
			&& selIdx == 0

		if !isRedundantNonBOLMatch, prefixMatch(sel.atoms, n.atoms) {
			if sel.anchorToPrevious {
				if btSelIdx < 0 {
					btNode = n
					btSelIdx = selIdx
					btScore = score
				}
			} else if btSelIdx >= 0 {
				btSelIdx = -1
			}

			// Score: sum of 1/2^(power-len) for each atom matched
			var len = sel.atoms.reduce(1) { $0 + ($1 == "." ? 1 : 0) }
			while len > 0 {
				len -= 1
				score += 1.0 / pow(2.0, power - Double(len))
			}

			selIdx -= 1
		} else if btSelIdx >= 0 {
			guard btNode != nil else { break }
			node = btNode
			selIdx = btSelIdx
			score = btScore
			btSelIdx = -1
		}

		node = n.parent
	}

	rank = selIdx < 0 ? score : 0
	return selIdx < 0
}

// MARK: - Selector Parser (mirrors C++ scope::parse)

private struct SelectorParser {
	var it: String.Index
	var last: String.Index
	let source: String

	init(_ string: String) {
		source = string
		it = string.startIndex
		last = string.endIndex
	}

	// MARK: Utilities

	mutating func skipWS() {
		while it < last, source[it] == " " || source[it] == "\t" {
			it = source.index(after: it)
		}
	}

	mutating func parseChar(_ chars: String, into dst: inout Character) -> Bool {
		guard it < last, chars.contains(source[it]) else { return false }
		dst = source[it]
		it = source.index(after: it)
		return true
	}

	mutating func parseChar(_ ch: Character) -> Bool {
		guard it < last, source[it] == ch else { return false }
		it = source.index(after: it)
		return true
	}

	// MARK: Grammar

	mutating func parseScope(_ res: inout SelectorScope) -> Bool {
		var dummy: Character = "\0"
		if parseChar(">", into: &dummy) { skipWS() }
		res.anchorToPrevious = dummy == ">"

		let from = it
		repeat {
			guard it < last else { break }
			let ch = source[it]
			guard ch.isLetter || ch.isNumber || ch == "*" || ch.asciiValue.map({ $0 >= 0x80 }) == true else { break }
			while it < last {
				let c = source[it]
				guard c.isLetter || c.isNumber || c == "_" || c == "-" || c == "+"
					|| c == "*" || c.asciiValue.map({ $0 > 0x7F }) == true
				else {
					break
				}
				it = source.index(after: it)
			}
		} while parseChar(".")

		res.atoms = String(source[from ..< it])
		return from != it
	}

	mutating func parsePath(_ res: inout SelectorPath) -> Bool {
		let hadCaret = parseChar("^")
		if hadCaret { skipWS() }
		res.anchorToBOL = hadCaret

		while true {
			var scope = SelectorScope()
			if !parseScope(&scope) {
				break
			}
			res.scopes.append(scope)
			skipWS()
			guard it < last else { break }
		}

		res.anchorToEOL = parseChar("$")
		return true
	}

	mutating func parseGroup(_ res: inout SelectorMatchable?) -> Bool {
		let bt = it
		guard parseChar("(") else { return false }
		var selector = SelectorData()
		guard parseSelector(&selector) else { it = bt
			return false
		}
		skipWS()
		guard parseChar(")") else { it = bt
			return false
		}
		res = GroupMatcher(selector)
		return true
	}

	mutating func parseFilter(_ res: inout SelectorMatchable?) -> Bool {
		let bt = it
		var side: Character = "\0"
		if parseChar("LRB", into: &side), parseChar(":") {
			skipWS()
			var inner: SelectorMatchable?
			if parseGroup(&inner) || {
				var path = SelectorPath()
				if parsePath(&path) {
					inner = PathMatcher(path)
					return true
				}
				return false
			}() {
				let s: FilterMatcher.Side = switch side {
				case "L": .left
				case "R": .right
				default: .both
				}
				res = FilterMatcher(side: s, selector: inner!)
				return true
			}
		}
		it = bt
		return false
	}

	mutating func parseExpression(_ res: inout ExpressionData) -> Bool {
		if parseChar("-") {
			skipWS()
			res.negate = true
		}

		var matcher: SelectorMatchable?
		if parseFilter(&matcher) {
			res.selector = matcher
			return true
		}
		if parseGroup(&matcher) {
			res.selector = matcher
			return true
		}

		var path = SelectorPath()
		if parsePath(&path), !path.scopes.isEmpty {
			res.selector = PathMatcher(path)
			return true
		}

		return false
	}

	mutating func parseComposite(_ res: inout CompositeData) -> Bool {
		var rc = false
		var op: Character = "\0"
		var opEnum: ExpressionData.Op = .none

		repeat {
			var expr = ExpressionData(op: opEnum)
			if !parseExpression(&expr) { break }
			res.expressions.append(expr)
			rc = true
			skipWS()
			op = "\0"
		} while parseChar("&|-", into: &op) && {
			skipWS()
			opEnum = ExpressionData.Op(rawValue: op) ?? .none
			return true
		}()

		return rc
	}

	mutating func parseSelector(_ res: inout SelectorData) -> Bool {
		var rc = false
		skipWS()
		repeat {
			var composite = CompositeData()
			if !parseComposite(&composite) { break }
			res.composites.append(composite)
			rc = true
			skipWS()
		} while parseChar(",") && { skipWS()
			return true
		}()
		return rc
	}
}

// MARK: - Public API

/// A compiled scope selector that can be matched against scopes.
///
/// Scope selectors use the TextMate selector grammar:
/// - Simple: `"source.swift"` — matches any scope containing `source.swift`
/// - Descendant: `"source.swift string"` — matches `string` nested in `source.swift`
/// - Child: `"source.swift > meta.function"` — matches direct child only
/// - Anchored: `"^source.swift"` (BOL) or `"source.swift$"` (EOL)
/// - Boolean: `"source.swift | source.objc"`, `"source - string"`, `"source & meta"`
/// - Filter: `"L:source"` (left), `"R:source"` (right), `"B:source"` (both)
/// - Grouped: `"(source.swift | source.objc) & string"`
/// - Wildcard: `"source.*"` matches any `source.X`
public struct ScopeSelector: Sendable {
	private let data: SelectorData?

	/// Creates a selector from a selector string.
	public init(_ string: String) {
		guard !string.isEmpty else {
			data = nil
			return
		}
		var parser = SelectorParser(string)
		var selector = SelectorData()
		if parser.parseSelector(&selector) {
			data = selector
		} else {
			data = nil
		}
	}

	/// Creates an empty selector that matches everything with rank 0.
	public init() {
		data = nil
	}

	/// Tests whether this selector matches the given scope context.
	///
	/// Returns the match rank (higher = more specific) if matched, or `nil` if
	/// not matched. An empty selector always matches with rank 0.
	public func doesMatch(_ context: ScopeContext) -> Double? {
		guard let data else { return 0 }

		// Wildcard: "x-any" on either side always matches
		let wildcard = Scope("x-any")
		if context.left == wildcard || context.right == wildcard {
			var rank: Double = 1
			_ = data.doesMatch(left: context.left, right: context.right, rank: &rank)
			return rank
		}

		var rank: Double = 0
		if data.doesMatch(left: context.left, right: context.right, rank: &rank) {
			return rank
		}
		return nil
	}

	/// Tests whether this selector matches the given scope.
	///
	/// Convenience that creates a context where left == right.
	public func doesMatch(_ scope: Scope) -> Double? {
		doesMatch(ScopeContext(scope))
	}
}

// MARK: - ExpressibleByStringLiteral

extension ScopeSelector: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self.init(value)
	}
}
