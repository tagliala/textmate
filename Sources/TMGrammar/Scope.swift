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
