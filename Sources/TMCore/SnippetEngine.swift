import Foundation

// MARK: - Snippet Position & Range

/// A position within a snippet's text, combining a byte offset with a rank
/// for ordering fields at the same offset.
///
/// Ports the C++ `snippet::pos_t`.
public struct SnippetPosition: Sendable, Comparable, Equatable {
	/// Byte offset within the snippet text.
	public var offset: Int
	/// Ordering rank (higher rank = later in sequence at the same offset).
	public var rank: Int

	public init(offset: Int = 0, rank: Int = 0) {
		self.offset = offset
		self.rank = rank
	}

	public static func < (lhs: SnippetPosition, rhs: SnippetPosition) -> Bool {
		lhs.offset < rhs.offset || (lhs.offset == rhs.offset && lhs.rank < rhs.rank)
	}

	public static func + (lhs: SnippetPosition, rhs: Int) -> SnippetPosition {
		SnippetPosition(offset: lhs.offset + rhs, rank: lhs.rank)
	}

	public static func - (lhs: SnippetPosition, rhs: Int) -> SnippetPosition {
		SnippetPosition(offset: lhs.offset - rhs, rank: lhs.rank)
	}
}

/// A range within a snippet's text, defined by two positions.
///
/// Ports the C++ `snippet::range_t`.
public struct SnippetRange: Sendable, Comparable, Equatable {
	public var from: SnippetPosition
	public var to: SnippetPosition

	public init(from: SnippetPosition, to: SnippetPosition) {
		self.from = from
		self.to = to
	}

	/// Whether `pos` is strictly inside this range.
	public func contains(_ pos: SnippetPosition) -> Bool {
		from < pos && pos < to
	}

	/// Whether `other` is strictly inside this range.
	public func contains(_ other: SnippetRange) -> Bool {
		from < other.from && other.to < to
	}

	/// Length in bytes.
	public var size: Int {
		to.offset - from.offset
	}

	/// Extracts the substring from `str`.
	public func substring(of str: String) -> String {
		let start = str.utf8.index(str.utf8.startIndex, offsetBy: from.offset)
		let end = str.utf8.index(str.utf8.startIndex, offsetBy: to.offset)
		return String(str[start ..< end])
	}

	public static func < (lhs: SnippetRange, rhs: SnippetRange) -> Bool {
		lhs.from < rhs.from || (lhs.from == rhs.from && lhs.to < rhs.to)
	}

	public static func + (lhs: SnippetRange, rhs: Int) -> SnippetRange {
		SnippetRange(from: lhs.from + rhs, to: lhs.to + rhs)
	}

	public static func - (lhs: SnippetRange, rhs: Int) -> SnippetRange {
		SnippetRange(from: lhs.from - rhs, to: lhs.to - rhs)
	}
}

// MARK: - Snippet Field

/// Information for a regex transform on a snippet mirror.
public struct SnippetTransformInfo: Sendable {
	/// The regex pattern string.
	public let pattern: String
	/// The format string AST for the replacement.
	public let format: [FormatStringNode]
	/// Regexp options (global, case-insensitive, etc.).
	public let options: RegexpOptions

	public init(pattern: String, format: [FormatStringNode], options: RegexpOptions) {
		self.pattern = pattern
		self.format = format
		self.options = options
	}
}

/// A snippet field (tab stop, mirror, or transform).
///
/// Ports the C++ `snippet::placeholder_t` / `transform_t` / `choice_t`.
public struct SnippetField: Sendable {
	/// The tab stop index.
	public let index: Int
	/// The range this field occupies in the snippet text.
	public var range: SnippetRange
	/// Regex transform for mirror fields.
	public var transform: SnippetTransformInfo?
	/// Available choices for choice tab stops.
	public var choices: [String]

	public init(
		index: Int,
		range: SnippetRange,
		transform: SnippetTransformInfo? = nil,
		choices: [String] = [],
	) {
		self.index = index
		self.range = range
		self.transform = transform
		self.choices = choices
	}

	/// Applies this field's transform (if any) to the source text.
	public func applyTransform(_ src: String, variables: [String: String] = [:]) -> String {
		guard let transform else { return src }

		var regexOptions: NSRegularExpression.Options = []
		if transform.options.contains(.ignoreCase) { regexOptions.insert(.caseInsensitive) }
		if transform.options.contains(.singleLine) { regexOptions.insert(.dotMatchesLineSeparators) }
		if transform.options.contains(.multiline) { regexOptions.insert(.anchorsMatchLines) }
		if transform.options.contains(.extended) { regexOptions.insert(.allowCommentsAndWhitespace) }

		guard let regex = try? NSRegularExpression(pattern: transform.pattern, options: regexOptions) else {
			return src
		}

		let expander = FormatStringExpander { name in variables[name] }
		expander.replace(
			source: src,
			pattern: regex,
			format: transform.format,
			repeat: transform.options.contains(.global),
		)
		expander.handleCaseChanges()
		return expander.result
	}
}

// MARK: - Snippet Engine

/// The runtime state of a parsed snippet, managing fields, mirrors, and text
/// replacement with cascading mirror updates.
///
/// Ports the C++ `snippet::snippet_t`.
public final class SnippetState: @unchecked Sendable {
	/// The current text of the snippet.
	public private(set) var text: String
	/// Primary fields indexed by tab stop number.
	public private(set) var fields: [Int: SnippetField]
	/// Mirror fields (multiple mirrors per tab stop index).
	public private(set) var mirrors: [(Int, SnippetField)]
	/// Variables used during expansion.
	public let variables: [String: String]
	/// Indentation to prepend to each line.
	public let indentString: String
	/// The currently active tab stop index.
	public var currentField: Int

	/// Replacement pair: range and new text.
	public typealias Replacement = (range: SnippetRange, text: String)

	/// Creates a snippet state from parsed data.
	public init(
		text: String,
		fields: [Int: SnippetField],
		mirrors: [(Int, SnippetField)],
		variables: [String: String],
		indentString: String,
	) {
		self.text = text
		self.fields = fields
		self.mirrors = mirrors
		self.variables = variables
		self.indentString = indentString
		currentField = 0
		setup()
	}

	/// Parses a snippet string and creates the runtime state.
	public static func parse(
		_ snippet: String,
		variables: [String: String] = [:],
		indentString: String = "",
		commandRunner: ((String) -> String)? = nil,
	) -> SnippetState {
		let nodes = FormatStringParser.parseSnippet(snippet)

		let expander = FormatStringExpander(
			variable: { name in variables[name] },
			commandRunner: commandRunner,
		)
		expander.traverse(nodes)
		expander.handleCaseChanges()

		// Resolve ambiguous fields: if no primary field exists for an index, promote from ambiguous
		var fields = expander.fields
		var mirrors = expander.mirrors
		for (idx, field) in expander.ambiguous {
			if fields[idx] == nil {
				fields[idx] = field
			} else {
				mirrors.append((idx, field))
			}
		}

		return SnippetState(
			text: expander.result,
			fields: fields,
			mirrors: mirrors,
			variables: variables,
			indentString: indentString,
		)
	}

	// MARK: - Setup

	private func setup() {
		// Promote mirrors that have no primary field
		let mirrorIndices = Set(mirrors.map(\.0))
		let fieldIndices = Set(fields.keys)
		let toPromote = mirrorIndices.subtracting(fieldIndices)
		for idx in toPromote {
			if let firstMirrorIdx = mirrors.firstIndex(where: { $0.0 == idx }) {
				fields[idx] = mirrors[firstMirrorIdx].1
				mirrors.remove(at: firstMirrorIdx)
			}
		}

		// Add $0 (exit tab stop) if missing
		if fields[0] == nil {
			let pos = SnippetPosition(offset: text.count, rank: Int.max - 2)
			let toPos = SnippetPosition(offset: text.count, rank: Int.max)
			fields[0] = SnippetField(index: 0, range: SnippetRange(from: pos, to: toPos))
		}

		// Apply indentation to all lines after the first
		if !indentString.isEmpty {
			applyIndent()
		}

		// Update mirrors
		updateMirrors()

		// Set current field to the first non-zero field, or 0
		let sortedFieldKeys = fields.keys.sorted()
		if sortedFieldKeys.count > 1 {
			currentField = sortedFieldKeys.first(where: { $0 != 0 }) ?? sortedFieldKeys[1]
		} else {
			currentField = 0
		}
	}

	// MARK: - Mirror Updates

	private func buildGraph() -> DependencyGraph {
		var graph = DependencyGraph()
		for (idx, field) in fields {
			graph.addNode(idx)
			for (otherIdx, otherField) in fields where field.range.contains(otherField.range) {
				graph.addEdge(from: idx, dependsOn: otherIdx)
			}
			for (mirrorIdx, mirror) in mirrors where field.range.contains(mirror.range) {
				graph.addEdge(from: idx, dependsOn: mirrorIdx)
			}
		}
		return graph
	}

	private func updateMirrors(forFields dirtyFields: Set<Int>? = nil) {
		let graph = buildGraph()
		for node in graph.topologicalOrder() {
			if let dirty = dirtyFields, !dirty.contains(node) { continue }
			guard let field = fields[node] else { continue }

			let src = field.range.substring(of: text)
			for i in mirrors.indices where mirrors[i].0 == node {
				var str = mirrors[i].1.applyTransform(src, variables: variables)

				// Add indent to continuation lines
				if !indentString.isEmpty {
					str = str.replacingOccurrences(
						of: "\n(?!$)",
						with: "\n" + NSRegularExpression.escapedPattern(for: indentString),
						options: .regularExpression,
					)
				}

				replaceRange(mirrors[i].1.range, with: str)
			}
		}
	}

	// MARK: - Text Replacement

	/// Replaces text in the given range and adjusts all field/mirror positions.
	private func replaceRange(_ range: SnippetRange, with str: String) {
		// Replace in the text buffer
		let startByte = text.utf8.index(text.utf8.startIndex, offsetBy: range.from.offset)
		let endByte = text.utf8.index(text.utf8.startIndex, offsetBy: range.to.offset)
		text.replaceSubrange(startByte ..< endByte, with: str)

		let oldSize = range.size
		let newSize = str.utf8.count

		// Adjust all positions
		adjustPositions(for: range, sizeDelta: newSize - oldSize)
	}

	private func adjustPositions(for range: SnippetRange, sizeDelta: Int) {
		for idx in fields.keys {
			adjustFieldPosition(&fields[idx]!, for: range, sizeDelta: sizeDelta)
		}
		for i in mirrors.indices {
			adjustFieldPosition(&mirrors[i].1, for: range, sizeDelta: sizeDelta)
		}
	}

	private func adjustFieldPosition(_ field: inout SnippetField, for range: SnippetRange, sizeDelta: Int) {
		if range.contains(field.range.from) {
			field.range.from.offset = range.from.offset
		} else if range.from < field.range.from {
			field.range.from.offset += sizeDelta
		}
		if range.contains(field.range.to) {
			field.range.to.offset = range.from.offset
		} else if range.from < field.range.to {
			field.range.to.offset += sizeDelta
		}
	}

	// MARK: - Public Edit API

	/// Replaces text within the current field's range and cascades to mirrors.
	///
	/// - Returns: Array of (range, newText) pairs for all affected mirrors.
	public func replace(range: SnippetRange, with str: String) -> [Replacement] {
		guard let currentFieldData = fields[currentField] else { return [] }

		let graph = buildGraph()
		let dirty = graph.touch(currentField)

		// Collect mirror ranges before replacement
		var updates: [Replacement] = []
		for node in graph.topologicalOrder() where dirty.contains(node) {
			for (mirrorIdx, mirror) in mirrors where mirrorIdx == node {
				updates.append((mirror.range, ""))
			}
		}

		// Remove mirrors inside the current field
		mirrors.removeAll { _, mirror in
			currentFieldData.range.contains(mirror.range)
		}

		// Perform the replacement
		replaceRange(range, with: str)

		// Update mirrors
		updateMirrors(forFields: dirty)

		// Collect updated mirror ranges
		var finalUpdates: [Replacement] = []
		for node in graph.topologicalOrder() where dirty.contains(node) {
			for (mirrorIdx, mirror) in mirrors where mirrorIdx == node {
				finalUpdates.append((mirror.range, mirror.range.substring(of: text)))
			}
		}

		return finalUpdates.sorted { $0.range < $1.range }
	}

	/// The range of the current field.
	public var currentRange: SnippetRange? {
		fields[currentField]?.range
	}

	/// The choices available at the current field, or empty.
	public var currentChoices: [String] {
		fields[currentField]?.choices ?? []
	}

	// MARK: - Indentation

	private func applyIndent() {
		// Find all newline positions and insert indent after each
		var positions = allPositionPointers()
		var newText = ""
		var offset = 0
		var isFirstLine = true

		for (i, ch) in text.enumerated() {
			newText.append(ch)
			offset += 1

			if ch == "\n", i < text.count - 1 {
				if !isFirstLine || true {
					newText += indentString
					// Adjust positions after this newline
					let insertOffset = offset
					for posIdx in positions.indices {
						if positions[posIdx] >= insertOffset {
							positions[posIdx] += indentString.count
						}
					}
					offset += indentString.count
				}
			}
			isFirstLine = false
		}

		// Apply adjusted positions back
		applyPositionPointers(positions)
		text = newText
	}

	private func allPositionPointers() -> [Int] {
		var offsets: [Int] = []
		for field in fields.values {
			offsets.append(field.range.from.offset)
			offsets.append(field.range.to.offset)
		}
		for (_, mirror) in mirrors {
			offsets.append(mirror.range.from.offset)
			offsets.append(mirror.range.to.offset)
		}
		return offsets
	}

	private func applyPositionPointers(_ offsets: [Int]) {
		var idx = 0
		for key in fields.keys {
			fields[key]!.range.from.offset = offsets[idx]
			fields[key]!.range.to.offset = offsets[idx + 1]
			idx += 2
		}
		for i in mirrors.indices {
			mirrors[i].1.range.from.offset = offsets[idx]
			mirrors[i].1.range.to.offset = offsets[idx + 1]
			idx += 2
		}
	}
}

// MARK: - Snippet Stack

/// Manages a stack of nested snippet sessions, supporting tab-stop navigation
/// across nested snippets.
///
/// Ports the C++ `snippet::stack_t`.
public final class SnippetStack: @unchecked Sendable {
	private struct Record {
		var snippet: SnippetState
		var caret: Int = 0
	}

	private var records: [Record] = []

	public init() {}

	/// Whether the stack is empty.
	public var isEmpty: Bool {
		records.isEmpty
	}

	/// Clears all snippet sessions.
	public func clear() {
		records.removeAll()
	}

	/// Pushes a new snippet onto the stack.
	public func push(_ snippet: SnippetState, range: SnippetRange) {
		if !records.isEmpty {
			records[records.count - 1].caret = range.from.offset - current.from.offset
		}
		records.append(Record(snippet: snippet))
	}

	/// The range of the currently active field across all nested snippets.
	public var current: SnippetRange {
		guard !records.isEmpty else {
			return SnippetRange(
				from: SnippetPosition(offset: 0, rank: 0),
				to: SnippetPosition(offset: 0, rank: 0),
			)
		}

		var offset = 0
		for i in 0 ..< records.count - 1 {
			let s = records[i].snippet
			if let field = s.fields[s.currentField] {
				offset += field.range.from.offset + records[i].caret
			}
		}

		let last = records[records.count - 1].snippet
		if let field = last.fields[last.currentField] {
			return field.range + offset
		}
		return SnippetRange(
			from: SnippetPosition(offset: offset, rank: 0),
			to: SnippetPosition(offset: offset, rank: 0),
		)
	}

	/// The choices available at the current tab stop.
	public var choices: [String] {
		records.last?.snippet.currentChoices ?? []
	}

	/// Whether the innermost snippet is at its last placeholder ($0).
	public var isAtLastPlaceholder: Bool {
		guard let last = records.last else { return true }
		return last.snippet.currentField == 0
	}

	/// Advances to the next tab stop.
	///
	/// - Returns: `true` if navigation succeeded, `false` if all snippets are done.
	@discardableResult
	public func next() -> Bool {
		while !records.isEmpty {
			let s = records[records.count - 1].snippet
			let n = s.currentField

			if n != 0 {
				let currentRange = s.fields[n]!.range
				let sortedKeys = s.fields.keys.sorted()
				if let idx = sortedKeys.firstIndex(of: n) {
					var nextIdx = sortedKeys.index(after: idx)
					if nextIdx >= sortedKeys.endIndex { nextIdx = sortedKeys.startIndex }

					while true {
						let nextField = s.fields[sortedKeys[nextIdx]]!
						if nextField.range != currentRange {
							s.currentField = sortedKeys[nextIdx]
							return true
						}
						if sortedKeys[nextIdx] == 0 { break }
						nextIdx = sortedKeys.index(after: nextIdx)
						if nextIdx >= sortedKeys.endIndex { nextIdx = sortedKeys.startIndex }
					}
				}
			}
			records.removeLast()
		}
		return false
	}

	/// Goes to the previous tab stop.
	///
	/// - Returns: `true` if navigation succeeded.
	@discardableResult
	public func previous() -> Bool {
		while !records.isEmpty {
			let s = records[records.count - 1].snippet
			if s.currentField == 0 {
				if s.fields.count > 1 {
					let sortedKeys = s.fields.keys.sorted()
					s.currentField = sortedKeys[sortedKeys.count - 1]
					if s.currentField == 0, sortedKeys.count > 1 {
						s.currentField = sortedKeys[sortedKeys.count - 2]
					}
					return true
				}
				records.removeLast()
				continue
			} else {
				let sortedKeys = s.fields.keys.sorted()
				if let idx = sortedKeys.firstIndex(of: s.currentField) {
					if idx > 0, sortedKeys[idx - 1] != 0 {
						s.currentField = sortedKeys[idx - 1]
						return true
					} else if records.count == 1 {
						return false
					}
				}
				records.removeLast()
			}
		}
		return false
	}

	/// Drops snippet sessions that don't contain the given position.
	public func dropForPosition(_ pos: SnippetPosition) {
		while !records.isEmpty {
			if records[records.count - 1].snippet.currentField == 0 {
				records.removeLast()
				continue
			}
			var adjustedPos = pos
			adjustedPos.rank = current.from.rank + 1
			if current.contains(adjustedPos) {
				return
			}
			records.removeLast()
		}
	}

	/// Replaces text within the current tab stop's range.
	///
	/// - Returns: Array of (range, newText) pairs for the replacement and all mirror updates.
	public func replace(range: SnippetRange, replacement: String) -> [SnippetState.Replacement] {
		var result: [SnippetState.Replacement] = [(range, replacement)]

		dropForPosition(range.from)
		dropForPosition(range.to)
		guard !records.isEmpty else { return result }

		// Process from innermost snippet outward
		var currentRange = range
		var currentReplacement = replacement

		for i in stride(from: records.count - 1, through: 0, by: -1) {
			let s = records[i].snippet
			let offset = computeOffset(upTo: i)
			let oldLen = s.text.count

			let local = currentRange - offset
			let updates = s.replace(range: local, with: currentReplacement)

			for update in updates {
				let adjusted = update.range + offset
				if adjusted.from < currentRange.from {
					result.insert((adjusted, update.text), at: 0)
				} else {
					result.append((adjusted, update.text))
				}
			}

			currentReplacement = s.text
			currentRange = SnippetRange(
				from: SnippetPosition(offset: offset, rank: 0),
				to: SnippetPosition(offset: offset + oldLen, rank: 0),
			)
		}

		return result
	}

	private func computeOffset(upTo recordIndex: Int) -> Int {
		var offset = 0
		for i in 0 ..< recordIndex {
			let s = records[i].snippet
			if let field = s.fields[s.currentField] {
				offset += field.range.from.offset + records[i].caret
			}
		}
		return offset
	}
}
