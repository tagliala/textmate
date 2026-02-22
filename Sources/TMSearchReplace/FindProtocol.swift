import Foundation

// MARK: - Find Server Protocol

/// Protocol for the find panel acting as a server — equivalent to `OakFindServerProtocol`.
///
/// The find window implements this to provide the search/replace parameters,
/// and receives results back via the `didFind`/`didReplace` methods.
@MainActor
public protocol FindServer: AnyObject {
	/// The operation to perform.
	var findOperation: FindOperation { get }

	/// The string to search for.
	var findString: String { get }

	/// The string to replace with.
	var replaceString: String { get }

	/// The search options.
	var findOptions: FindOptions { get }

	/// Callback: matches were found.
	func didFind(
		count: Int,
		of searchString: String,
		atLine: Int,
		column: Int,
		wrapped: Bool,
	)

	/// Callback: replacements were made.
	func didReplace(
		count: Int,
		of searchString: String,
		with replacement: String,
	)
}

// MARK: - Find Client Protocol

/// Protocol for views that respond to find operations — equivalent to `OakFindClientProtocol`.
///
/// The text view (or any first responder) implements this to perform the actual
/// search within its content when the find panel sends an operation.
@MainActor
public protocol FindClient: AnyObject {
	/// Perform the find operation described by the server.
	func performFindOperation(_ server: FindServer)
}

// MARK: - Find Navigation Delegate

/// Delegate for navigating to search results in documents — equivalent to `FindDelegate`.
@MainActor
public protocol FindNavigationDelegate: AnyObject {
	/// Select the given range in the specified document.
	func selectRange(_ range: LineColumnRange, inDocumentWithID documentID: UUID)

	/// Bring the relevant window to the front.
	func bringToFront()
}

// MARK: - Document Match Reference

/// A reference to a match across documents for cross-file find next/previous — equivalent to `FindMatch` (ObjC).
public struct DocumentMatchReference: Sendable, Equatable {
	/// The document identifier.
	public var documentID: UUID

	/// The first match range in this document.
	public var firstRange: LineColumnRange

	/// The last match range in this document.
	public var lastRange: LineColumnRange

	public init(
		documentID: UUID,
		firstRange: LineColumnRange,
		lastRange: LineColumnRange,
	) {
		self.documentID = documentID
		self.firstRange = firstRange
		self.lastRange = lastRange
	}
}

// MARK: - Find State

/// Shared state for the find system — persisted across find panel show/hide.
@MainActor
public final class FindState: Observable {
	/// The current find string.
	public var findString: String = ""

	/// The current replace string.
	public var replaceString: String = ""

	/// Current search options.
	public var options: FindOptions = .default

	/// Current search scope.
	public var searchScope: SearchScope = .document

	/// Glob pattern for file filtering in project search.
	public var fileGlob: String = ""

	/// Whether the find panel is visible.
	public var isPanelVisible: Bool = false

	/// Find string history (most recent first).
	public var findHistory: [String] = []

	/// Replace string history (most recent first).
	public var replaceHistory: [String] = []

	/// Cross-file match references for Cmd-G cycling.
	public var matchReferences: [DocumentMatchReference] = []

	/// Maximum history entries.
	private let maxHistory = 30

	public init() {}

	/// Add the current find string to history.
	public func pushFindHistory() {
		guard !findString.isEmpty else { return }
		findHistory.removeAll { $0 == findString }
		findHistory.insert(findString, at: 0)
		if findHistory.count > maxHistory {
			findHistory.removeLast(findHistory.count - maxHistory)
		}
	}

	/// Add the current replace string to history.
	public func pushReplaceHistory() {
		guard !replaceString.isEmpty else { return }
		replaceHistory.removeAll { $0 == replaceString }
		replaceHistory.insert(replaceString, at: 0)
		if replaceHistory.count > maxHistory {
			replaceHistory.removeLast(replaceHistory.count - maxHistory)
		}
	}

	/// Persist state to UserDefaults.
	public func save() {
		let defaults = UserDefaults.standard
		defaults.set(options.rawValue, forKey: "TMFindOptions")
		defaults.set(searchScope.rawValue, forKey: "TMFindSearchScope")
		defaults.set(fileGlob, forKey: "TMFindFileGlob")
		defaults.set(findHistory, forKey: "TMFindHistory")
		defaults.set(replaceHistory, forKey: "TMReplaceHistory")
	}

	/// Restore state from UserDefaults.
	public func restore() {
		let defaults = UserDefaults.standard
		if let raw = defaults.object(forKey: "TMFindOptions") as? UInt32 {
			options = FindOptions(rawValue: raw)
		}
		if let raw = defaults.object(forKey: "TMFindSearchScope") as? Int,
		   let scope = SearchScope(rawValue: raw)
		{
			searchScope = scope
		}
		fileGlob = defaults.string(forKey: "TMFindFileGlob") ?? ""
		findHistory = defaults.stringArray(forKey: "TMFindHistory") ?? []
		replaceHistory = defaults.stringArray(forKey: "TMReplaceHistory") ?? []
	}
}
