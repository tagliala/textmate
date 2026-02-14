/// Parser state stack, equivalent to C++ `parse::stack_t`.
///
/// Each frame represents an active grammar rule context, holding the
/// current scope, active end/while patterns, and a reference to the
/// parent frame. Frames are shared (class-based) for efficient copying
/// between parse states.
public final class ParserState: @unchecked Sendable, Equatable {
	/// The parent state (or `nil` for the root).
	public let parent: ParserState?

	/// The grammar rule that created this frame.
	public let rule: GrammarRule

	/// The accumulated scope at this point.
	public var scope: Scope

	/// The expanded scope string (with format-string captures applied).
	public var scopeString: String?

	/// The expanded content scope string.
	public var contentScopeString: String?

	/// The active while pattern (may be expanded from back references).
	public var whilePattern: OnigmoPattern?

	/// The active end pattern (may be expanded from back references).
	public var endPattern: OnigmoPattern?

	/// Byte offset of the anchor position for `\G`.
	public var anchor: Int = Int.max

	/// Whether the begin pattern was zero-width.
	public var zwBeginMatch: Bool = false

	/// Whether to apply end pattern last (giving child patterns priority).
	public var applyEndLast: Bool = false

	/// Creates a root parser state with the given rule and scope.
	public init(rule: GrammarRule, scope: String) {
		self.parent = nil
		self.rule = rule
		self.scope = Scope(scope)
	}

	/// Creates a child parser state.
	public init(rule: GrammarRule, scope: Scope, parent: ParserState) {
		self.parent = parent
		self.rule = rule
		self.scope = scope
	}

	// MARK: - Equatable

	public static func == (lhs: ParserState, rhs: ParserState) -> Bool {
		if lhs === rhs { return true }

		guard lhs.rule === rhs.rule, lhs.scope == rhs.scope else { return false }

		// Compare patterns by their string representation
		let lhsWhile = lhs.whilePattern?.patternString
		let rhsWhile = rhs.whilePattern?.patternString
		guard lhsWhile == rhsWhile else { return false }

		let lhsEnd = lhs.endPattern?.patternString
		let rhsEnd = rhs.endPattern?.patternString
		guard lhsEnd == rhsEnd else { return false }

		// Compare parent chains
		if let lp = lhs.parent, let rp = rhs.parent {
			return lp == rp
		}
		return lhs.parent == nil && rhs.parent == nil
	}
}
