/// A scope stack representing nested TextMate scopes.
///
/// Scopes are space-separated identifiers like `"source.swift meta.function"`.
/// The stack is immutable and built by pushing/popping scope atoms.
/// Internally uses a singly-linked list of nodes for efficient sharing
/// between parser states (equivalent to C++ `scope::scope_t`).
public struct Scope: Sendable, Hashable {
	/// The linked-list node backing the scope stack.
	/// Uses reference counting via `ManagedBuffer` for shared ownership.
	final class Node: @unchecked Sendable {
		let atoms: String
		let parent: Node?
		let depth: Int
		let cachedHash: Int

		init(atoms: String, parent: Node?) {
			self.atoms = atoms
			self.parent = parent
			depth = (parent?.depth ?? 0) + 1
			// Hash combining atoms with parent hash (mirrors C++ implementation)
			var hasher = Hasher()
			hasher.combine(atoms)
			hasher.combine(parent?.cachedHash ?? 0)
			cachedHash = hasher.finalize()
		}

		/// Whether this is an auxiliary scope (attr.* or dyn.*).
		var isAuxiliary: Bool {
			atoms.hasPrefix("attr.") || atoms.hasPrefix("dyn.")
		}

		/// Number of dot-separated atoms in this scope component.
		var numberOfAtoms: Int {
			atoms.reduce(1) { $0 + ($1 == "." ? 1 : 0) }
		}
	}

	private var node: Node?

	/// Creates an empty scope.
	public init() {
		node = nil
	}

	/// Creates a scope from a space-delimited string.
	///
	/// Example: `"source.swift meta.function.definition"` produces a
	/// stack with `"source.swift"` at the bottom and
	/// `"meta.function.definition"` at the top.
	public init(_ string: String) {
		for component in string.split(separator: " ") where !component.isEmpty {
			pushScope(String(component))
		}
	}

	/// Pushes a scope atom onto the stack.
	public mutating func pushScope(_ atom: String) {
		node = Node(atoms: atom, parent: node)
	}

	/// Pops the top-most scope atom from the stack.
	public mutating func popScope() {
		precondition(node != nil, "Cannot pop from an empty scope")
		node = node?.parent
	}

	/// The top-most scope atom, or `nil` if empty.
	public var back: String? {
		node?.atoms
	}

	/// The number of scope levels in the stack.
	public var size: Int {
		node?.depth ?? 0
	}

	/// Whether the scope stack is empty.
	public var isEmpty: Bool {
		node == nil
	}

	/// Whether `self` has `prefix` as a prefix
	/// (i.e. the bottom N nodes match).
	public func hasPrefix(_ prefix: Scope) -> Bool {
		var lhs = self
		let diff = lhs.size - prefix.size
		guard diff >= 0 else { return false }
		for _ in 0 ..< diff {
			lhs.popScope()
		}
		return lhs == prefix
	}

	/// Returns the scope as a space-separated string.
	public func toString() -> String {
		var parts: [String] = []
		var n = node
		while let current = n {
			parts.append(current.atoms)
			n = current.parent
		}
		return parts.reversed().joined(separator: " ")
	}

	// MARK: - Internal Access

	/// Exposes the internal node for scope selector matching.
	var currentNode: Node? {
		node
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(node?.cachedHash ?? 0)
	}

	// MARK: - Equatable

	public static func == (lhs: Scope, rhs: Scope) -> Bool {
		var n1 = lhs.node
		var n2 = rhs.node
		while n1 !== n2 {
			guard let a = n1, let b = n2, a.atoms == b.atoms else {
				return n1 == nil && n2 == nil
			}
			n1 = a.parent
			n2 = b.parent
		}
		return true
	}
}

// MARK: - Comparable

extension Scope: Comparable {
	public static func < (lhs: Scope, rhs: Scope) -> Bool {
		var n1 = lhs.node
		var n2 = rhs.node
		while n1 !== n2, let a = n1, let b = n2, a.atoms == b.atoms {
			n1 = a.parent
			n2 = b.parent
		}
		if let a = n1, let b = n2 {
			return a.atoms < b.atoms
		}
		return n1 == nil && n2 != nil
	}
}

// MARK: - CustomStringConvertible

extension Scope: CustomStringConvertible {
	public var description: String {
		toString()
	}
}

// MARK: - ExpressibleByStringLiteral

extension Scope: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self.init(value)
	}
}

// MARK: - Wildcard

extension Scope {
	/// The special wildcard scope `"x-any"` that matches everything.
	static let wildcard = Scope("x-any")
}

// MARK: - Scope Utilities

/// Returns the longest common prefix of two scopes.
///
/// Equalizes the depths by walking up the deeper scope, then walks
/// both scopes up together until their atoms match.
///
/// Example:
/// ```
/// sharedPrefix("foo bar quux", "foo bar baz qux")  // → "foo bar"
/// ```
func sharedPrefix(_ lhs: Scope, _ rhs: Scope) -> Scope {
	let lhsSize = lhs.size
	let rhsSize = rhs.size
	var n1 = lhs.currentNode
	var n2 = rhs.currentNode

	// Equalize depths
	if lhsSize > rhsSize {
		for _ in 0 ..< (lhsSize - rhsSize) {
			n1 = n1?.parent
		}
	} else if rhsSize > lhsSize {
		for _ in 0 ..< (rhsSize - lhsSize) {
			n2 = n2?.parent
		}
	}

	// Walk up until atoms match
	while let a = n1, let b = n2, a.atoms != b.atoms {
		n1 = a.parent
		n2 = b.parent
	}

	// Reconstruct the shared prefix scope from the matched node
	guard n1 != nil else { return Scope() }
	var parts: [String] = []
	var n = n1
	while let current = n {
		parts.append(current.atoms)
		n = current.parent
	}
	var result = Scope()
	for atom in parts.reversed() {
		result.pushScope(atom)
	}
	return result
}

/// Computes the XML-style difference between two scopes.
///
/// Returns a string of closing tags for scopes being left and opening tags
/// for scopes being entered, skipping the common prefix.
///
/// Example:
/// ```
/// xmlDifference(from: Scope("foo bar"), to: Scope("foo"))
/// // → "</bar>"
/// ```
func xmlDifference(
	from: Scope,
	to: Scope,
	open: String = "<",
	close: String = ">",
) -> String {
	// Collect scopes into arrays (bottom-to-top order)
	var fromScopes: [String] = []
	var toScopes: [String] = []
	var tmp = from
	while !tmp.isEmpty {
		if let back = tmp.back { fromScopes.append(back) }
		tmp.popScope()
	}
	tmp = to
	while !tmp.isEmpty {
		if let back = tmp.back { toScopes.append(back) }
		tmp.popScope()
	}

	// fromScopes/toScopes are in top-to-bottom order; reverse to bottom-to-top
	fromScopes.reverse()
	toScopes.reverse()

	// Skip common prefix
	var commonLen = 0
	while commonLen < fromScopes.count, commonLen < toScopes.count,
	      fromScopes[commonLen] == toScopes[commonLen]
	{
		commonLen += 1
	}

	// Close scopes being left (in top-to-bottom order)
	var result = ""
	for i in stride(from: fromScopes.count - 1, through: commonLen, by: -1) {
		result += "\(open)/\(fromScopes[i])\(close)"
	}

	// Open scopes being entered (in bottom-to-top order)
	for i in commonLen ..< toScopes.count {
		result += "\(open)\(toScopes[i])\(close)"
	}

	return result
}

// MARK: - ScopeContext

/// A context for scope selector matching, consisting of left and right scopes.
/// In most cases both sides are the same scope. The two-sided context is used
/// for scope selectors with L:/R:/B: prefixes (matching at caret position
/// between two adjacent scopes).
public struct ScopeContext: Sendable, Hashable {
	public let left: Scope
	public let right: Scope

	public init(_ scope: Scope) {
		left = scope
		right = scope
	}

	public init(left: Scope, right: Scope) {
		self.left = left
		self.right = right
	}

	public init(_ string: String) {
		let scope = Scope(string)
		left = scope
		right = scope
	}
}
