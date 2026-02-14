import Foundation

/// Builds the `TM_*` environment variables that TextMate exposes to bundle
/// commands, snippets, and other subprocess invocations.
///
/// Counterpart of the C++ `editor_t::editor_variables()` in
/// `Frameworks/editor/src/editor.cc` and the window-level variable
/// merging in `DocumentWindowController.mm`.
public struct EnvironmentBuilder: Sendable {
	// MARK: - Editor Context

	/// Per-document / per-editor state used to populate `TM_*` variables.
	public struct EditorContext: Sendable {
		/// Tab size in spaces.
		public var tabSize: Int
		/// Whether soft tabs are enabled.
		public var softTabs: Bool
		/// The serialized selection string (e.g., "1:5-1:10").
		public var selectionString: String
		/// The scope at the current caret position (e.g., "source.swift").
		public var scope: String
		/// The scope to the left of the caret (for scope-based commands).
		public var scopeLeft: String?
		/// Current line index (0-based).
		public var lineIndex: Int?
		/// Current line number (1-based).
		public var lineNumber: Int?
		/// Current column number (1-based, visual).
		public var columnNumber: Int?
		/// Text of the current line.
		public var currentLine: String?
		/// Word at the caret position.
		public var currentWord: String?
		/// Selected text (nil when caret is empty).
		public var selectedText: String?

		public init(
			tabSize: Int = 4,
			softTabs: Bool = false,
			selectionString: String = "",
			scope: String = "",
			scopeLeft: String? = nil,
			lineIndex: Int? = nil,
			lineNumber: Int? = nil,
			columnNumber: Int? = nil,
			currentLine: String? = nil,
			currentWord: String? = nil,
			selectedText: String? = nil,
		) {
			self.tabSize = tabSize
			self.softTabs = softTabs
			self.selectionString = selectionString
			self.scope = scope
			self.scopeLeft = scopeLeft
			self.lineIndex = lineIndex
			self.lineNumber = lineNumber
			self.columnNumber = columnNumber
			self.currentLine = currentLine
			self.currentWord = currentWord
			self.selectedText = selectedText
		}
	}

	// MARK: - Document Context

	/// Per-document metadata.
	public struct DocumentContext: Sendable {
		/// Absolute path of the document file (nil for untitled).
		public var filePath: String?
		/// Display name of the document.
		public var displayName: String?
		/// The document's directory.
		public var directory: String?

		public init(
			filePath: String? = nil,
			displayName: String? = nil,
			directory: String? = nil,
		) {
			self.filePath = filePath
			self.displayName = displayName
			self.directory = directory
		}
	}

	// MARK: - Project Context

	/// Project-level metadata.
	public struct ProjectContext: Sendable {
		/// Project root directory.
		public var projectDirectory: String?
		/// Project UUID.
		public var projectUUID: String?
		/// SCM name (e.g., "git", "svn").
		public var scmName: String?
		/// SCM branch (if available).
		public var scmBranch: String?

		public init(
			projectDirectory: String? = nil,
			projectUUID: String? = nil,
			scmName: String? = nil,
			scmBranch: String? = nil,
		) {
			self.projectDirectory = projectDirectory
			self.projectUUID = projectUUID
			self.scmName = scmName
			self.scmBranch = scmBranch
		}
	}

	// MARK: - Application Context

	/// Application-level variables (set once at startup).
	public struct AppContext: Sendable {
		/// Path to the TextMate application bundle.
		public var appPath: String?
		/// PID of the TextMate process.
		public var pid: Int32?
		/// Path to the TextMate support folder.
		public var supportPath: String?

		public init(
			appPath: String? = nil,
			pid: Int32? = nil,
			supportPath: String? = nil,
		) {
			self.appPath = appPath
			self.pid = pid
			self.supportPath = supportPath
		}
	}

	// MARK: - Builder

	/// Build the complete `TM_*` environment dictionary from all contexts.
	///
	/// The returned dictionary follows TextMate's variable naming conventions:
	/// `TM_TAB_SIZE`, `TM_SOFT_TABS`, `TM_SELECTION`, `TM_SCOPE`, etc.
	///
	/// - Parameters:
	///   - editor: Editor-level context (tab size, selection, scope, etc.)
	///   - document: Document-level context (file path, directory)
	///   - project: Project-level context (project directory, SCM info)
	///   - app: Application-level context (app path, PID, support)
	///   - extra: Additional key-value pairs to merge (lower priority)
	/// - Returns: A dictionary suitable for passing to `Process.environment`.
	public static func build(
		editor: EditorContext = EditorContext(),
		document: DocumentContext = DocumentContext(),
		project: ProjectContext = ProjectContext(),
		app: AppContext = AppContext(),
		extra: [String: String] = [:],
	) -> [String: String] {
		var env = extra

		// Editor variables
		env["TM_TAB_SIZE"] = String(editor.tabSize)
		env["TM_SOFT_TABS"] = editor.softTabs ? "YES" : "NO"
		env["TM_SELECTION"] = editor.selectionString
		env["TM_SCOPE"] = editor.scope

		if let scopeLeft = editor.scopeLeft {
			env["TM_SCOPE_LEFT"] = scopeLeft
		}
		if let lineIndex = editor.lineIndex {
			env["TM_LINE_INDEX"] = String(lineIndex)
		}
		if let lineNumber = editor.lineNumber {
			env["TM_LINE_NUMBER"] = String(lineNumber)
		}
		if let columnNumber = editor.columnNumber {
			env["TM_COLUMN_NUMBER"] = String(columnNumber)
		}
		if let currentLine = editor.currentLine {
			env["TM_CURRENT_LINE"] = currentLine
		}
		if let currentWord = editor.currentWord {
			env["TM_CURRENT_WORD"] = currentWord
		}
		if let selectedText = editor.selectedText {
			env["TM_SELECTED_TEXT"] = selectedText
		}

		// Document variables
		if let filePath = document.filePath {
			env["TM_FILEPATH"] = filePath
			env["TM_FILENAME"] = (filePath as NSString).lastPathComponent
			env["TM_DIRECTORY"] = (filePath as NSString).deletingLastPathComponent
		}
		if let displayName = document.displayName {
			env["TM_DISPLAYNAME"] = displayName
		}

		// Project variables
		if let projectDir = project.projectDirectory {
			env["TM_PROJECT_DIRECTORY"] = projectDir
		}
		if let projectUUID = project.projectUUID {
			env["TM_PROJECT_UUID"] = projectUUID
		}
		if let scmName = project.scmName {
			env["TM_SCM_NAME"] = scmName
		}
		if let scmBranch = project.scmBranch {
			env["TM_SCM_BRANCH"] = scmBranch
		}

		// Application variables
		if let appPath = app.appPath {
			env["TM_APP_PATH"] = appPath
		}
		if let pid = app.pid {
			env["TM_PID"] = String(pid)
		}
		if let supportPath = app.supportPath {
			env["TM_SUPPORT_PATH"] = supportPath
		}

		return env
	}

	/// Build a full environment merging `TM_*` variables with the inherited
	/// process environment.
	///
	/// `TM_*` variables override any inherited values with the same key.
	public static func buildFull(
		editor: EditorContext = EditorContext(),
		document: DocumentContext = DocumentContext(),
		project: ProjectContext = ProjectContext(),
		app: AppContext = AppContext(),
		extra: [String: String] = [:],
	) -> [String: String] {
		var env = ProcessInfo.processInfo.environment
		let tmVars = build(
			editor: editor,
			document: document,
			project: project,
			app: app,
			extra: extra,
		)
		for (key, value) in tmVars {
			env[key] = value
		}
		return env
	}

	/// The set of all `TM_*` variable names that TextMate defines.
	///
	/// Useful for stripping TextMate variables from inherited environments.
	public static let allVariableNames: Set<String> = [
		"TM_TAB_SIZE",
		"TM_SOFT_TABS",
		"TM_SELECTION",
		"TM_SCOPE",
		"TM_SCOPE_LEFT",
		"TM_LINE_INDEX",
		"TM_LINE_NUMBER",
		"TM_COLUMN_NUMBER",
		"TM_CURRENT_LINE",
		"TM_CURRENT_WORD",
		"TM_SELECTED_TEXT",
		"TM_FILEPATH",
		"TM_FILENAME",
		"TM_DIRECTORY",
		"TM_DISPLAYNAME",
		"TM_PROJECT_DIRECTORY",
		"TM_PROJECT_UUID",
		"TM_SCM_NAME",
		"TM_SCM_BRANCH",
		"TM_APP_PATH",
		"TM_PID",
		"TM_SUPPORT_PATH",
		"TM_PROPERTIES_PATH",
		"TM_BUNDLE_SUPPORT",
		"TM_MATE",
	]
}
