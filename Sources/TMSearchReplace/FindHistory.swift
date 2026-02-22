import Foundation

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Find Pasteboard

/// Manages the shared find pasteboard and history — bridges between the find panel
/// and the system find pasteboard (NSPasteboard.find).
@MainActor
public final class FindPasteboard: Observable {
	/// Shared singleton.
	public static let shared = FindPasteboard()

	/// The current find string.
	public var findString: String = "" {
		didSet {
			if findString != oldValue {
				pushToSystemPasteboard()
				addToHistory(findString)
			}
		}
	}

	/// The current replace string.
	public var replaceString: String = "" {
		didSet {
			if replaceString != oldValue {
				addToReplaceHistory(replaceString)
			}
		}
	}

	/// Find string history (most recent first).
	public private(set) var findHistory: [String] = []

	/// Replace string history (most recent first).
	public private(set) var replaceHistory: [String] = []

	/// Options associated with the current find string.
	public var options: FindOptions = .default

	/// Maximum history entries.
	private let maxHistory = 30

	/// Last known system pasteboard change count.
	private var lastPasteboardChangeCount: Int = 0

	private init() {
		pullFromSystemPasteboard()
	}

	/// Sync the find string from the system find pasteboard.
	public func syncFromSystem() {
		pullFromSystemPasteboard()
	}

	/// Add a string to find history.
	private func addToHistory(_ string: String) {
		guard !string.isEmpty else { return }
		findHistory.removeAll { $0 == string }
		findHistory.insert(string, at: 0)
		if findHistory.count > maxHistory {
			findHistory.removeLast(findHistory.count - maxHistory)
		}
	}

	/// Add a string to replace history.
	private func addToReplaceHistory(_ string: String) {
		guard !string.isEmpty else { return }
		replaceHistory.removeAll { $0 == string }
		replaceHistory.insert(string, at: 0)
		if replaceHistory.count > maxHistory {
			replaceHistory.removeLast(replaceHistory.count - maxHistory)
		}
	}

	// MARK: - System Pasteboard

	private func pushToSystemPasteboard() {
		#if canImport(AppKit)
		let pb = NSPasteboard(name: .find)
		pb.clearContents()
		pb.setString(findString, forType: .string)
		#endif
	}

	private func pullFromSystemPasteboard() {
		#if canImport(AppKit)
		let pb = NSPasteboard(name: .find)
		guard pb.changeCount != lastPasteboardChangeCount else { return }
		lastPasteboardChangeCount = pb.changeCount
		if let string = pb.string(forType: .string), !string.isEmpty {
			// Update without triggering push back
			findHistory.removeAll { $0 == string }
			findHistory.insert(string, at: 0)
			if findHistory.count > maxHistory {
				findHistory.removeLast(findHistory.count - maxHistory)
			}
			findString = string
		}
		#endif
	}

	/// Save history to UserDefaults.
	public func saveHistory() {
		let defaults = UserDefaults.standard
		defaults.set(findHistory, forKey: "TMFindPasteboardHistory")
		defaults.set(replaceHistory, forKey: "TMReplacePasteboardHistory")
	}

	/// Restore history from UserDefaults.
	public func restoreHistory() {
		let defaults = UserDefaults.standard
		findHistory = defaults.stringArray(forKey: "TMFindPasteboardHistory") ?? []
		replaceHistory = defaults.stringArray(forKey: "TMReplacePasteboardHistory") ?? []
	}
}
