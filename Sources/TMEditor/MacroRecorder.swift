import Foundation

/// Records and replays sequences of editor actions for macro support.
///
/// Modeled after TextMate's C++ macro dispatch system. The recorder captures
/// actions performed during a recording session and can replay them.
/// During replay, a temporary clipboard is used to isolate recorded
/// clipboard operations from the system clipboard.
public final class MacroRecorder: @unchecked Sendable {
	// MARK: - Types

	/// A single recorded action with optional payload.
	public struct RecordedAction: Sendable, Equatable {
		/// The editor action that was performed.
		public let action: EditorAction

		/// Optional text that was inserted (for `insertText`-like actions).
		public let text: String?

		/// Optional clipboard entry used by this action.
		public let clipboardEntry: ClipboardEntry?

		public init(action: EditorAction, text: String? = nil, clipboardEntry: ClipboardEntry? = nil) {
			self.action = action
			self.text = text
			self.clipboardEntry = clipboardEntry
		}
	}

	/// A complete recorded macro.
	public struct Macro: Sendable, Equatable {
		/// The sequence of actions in this macro.
		public let actions: [RecordedAction]

		/// A user-readable name for this macro.
		public var name: String

		public init(actions: [RecordedAction], name: String = "Untitled Macro") {
			self.actions = actions
			self.name = name
		}

		/// Whether the macro contains any recorded actions.
		public var isEmpty: Bool {
			actions.isEmpty
		}
	}

	// MARK: - State

	/// Whether we are currently recording.
	public private(set) var isRecording: Bool = false

	/// The actions recorded so far in the current session.
	private var recordedActions: [RecordedAction] = []

	/// The last completed macro (available for replay after recording stops).
	public private(set) var lastMacro: Macro?

	public init() {}

	// MARK: - Recording

	/// Starts recording actions. If already recording, this is a no-op.
	public func startRecording() {
		guard !isRecording else { return }
		isRecording = true
		recordedActions = []
	}

	/// Stops recording and stores the macro.
	///
	/// - Returns: The recorded macro, or `nil` if nothing was recorded.
	@discardableResult
	public func stopRecording() -> Macro? {
		guard isRecording else { return nil }
		isRecording = false

		let macro = Macro(actions: recordedActions)
		lastMacro = macro
		recordedActions = []
		return macro
	}

	/// Toggles recording on/off.
	///
	/// - Returns: The completed macro if recording was stopped, otherwise `nil`.
	@discardableResult
	public func toggleRecording() -> Macro? {
		if isRecording {
			return stopRecording()
		} else {
			startRecording()
			return nil
		}
	}

	/// Records an action. Only has effect when `isRecording` is true.
	///
	/// - Parameter action: The action to record.
	public func record(_ action: RecordedAction) {
		guard isRecording else { return }
		recordedActions.append(action)
	}

	/// Records a simple action with no payload.
	///
	/// - Parameter action: The editor action to record.
	public func record(action: EditorAction) {
		record(RecordedAction(action: action))
	}

	/// Records a text insertion.
	///
	/// - Parameters:
	///   - action: The editor action (e.g., `.insertTab`).
	///   - text: The text that was inserted.
	public func record(action: EditorAction, text: String) {
		record(RecordedAction(action: action, text: text))
	}

	// MARK: - Playback

	/// Replays a macro by calling the provided closure for each recorded action.
	///
	/// During playback, clipboard operations in the macro use an isolated
	/// temporary clipboard so they don't interfere with the system clipboard.
	///
	/// - Parameters:
	///   - macro: The macro to replay. If `nil`, replays `lastMacro`.
	///   - handler: A closure called for each action. Gets the action, any text
	///     payload, and a temporary clipboard for clipboard operations.
	/// - Returns: `true` if a macro was replayed, `false` if no macro was available.
	@discardableResult
	public func replay(
		macro: Macro? = nil,
		handler: (RecordedAction) -> Void,
	) -> Bool {
		guard let macroToPlay = macro ?? lastMacro else { return false }
		guard !macroToPlay.isEmpty else { return false }

		for action in macroToPlay.actions {
			handler(action)
		}

		return true
	}
}
