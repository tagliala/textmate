import Foundation

// Types that define the command execution pipeline, matching the C++
// enumerations in `Frameworks/command/src/parser.h`.

// MARK: - Pre-Execution Actions

/// Action to perform before running a command.
public enum PreExecAction: String, Sendable, Codable {
	/// Do nothing before executing.
	case nop
	/// Save the current document.
	case saveDocument
	/// Save all documents in the project.
	case saveProject
}

// MARK: - Input Source

/// Where a command reads its input from.
public enum CommandInput: String, Sendable, Codable {
	/// The current selection.
	case selection
	/// The entire document.
	case entireDocument = "document"
	/// The current scope.
	case scope
	/// The current line.
	case line
	/// The current word.
	case word
	/// A single character.
	case character
	/// No input.
	case nothing = "none"

	/// Parse from the plist string representation.
	public init(plistString: String) {
		switch plistString.lowercased() {
		case "selection": self = .selection
		case "document", "entire document": self = .entireDocument
		case "scope": self = .scope
		case "line": self = .line
		case "word": self = .word
		case "character": self = .character
		case "none", "nothing": self = .nothing
		default: self = .selection
		}
	}
}

// MARK: - Input Format

/// Format of the input data sent to a command.
public enum CommandInputFormat: String, Sendable, Codable {
	/// Plain text.
	case text
	/// XML representation.
	case xml
}

// MARK: - Output Destination

/// Where a command's output is placed.
public enum CommandOutput: String, Sendable, Codable {
	/// Replace the input (selection or fallback unit).
	case replaceInput = "replaceSelectedText"
	/// Replace the entire document.
	case replaceDocument
	/// Insert at the caret position.
	case atCaret = "insertAsText"
	/// Insert after the input.
	case afterInput = "afterSelectedText"
	/// Open in a new window (HTML output).
	case newWindow = "openAsNewDocument"
	/// Show as a tooltip.
	case toolTip = "showAsTooltip"
	/// Discard the output.
	case discard
	/// Replace the selection (alias for replaceInput).
	case replaceSelection

	/// Parse from the plist string representation.
	public init(plistString: String) {
		switch plistString.lowercased() {
		case "replaceselectedtext", "replaceinput", "replacecurrentword":
			self = .replaceInput
		case "replacedocument":
			self = .replaceDocument
		case "insertastext", "atcaret":
			self = .atCaret
		case "afterselectedtext", "afterinput":
			self = .afterInput
		case "openasnewdocument", "newwindow":
			self = .newWindow
		case "showastooltip", "tooltip":
			self = .toolTip
		case "discard":
			self = .discard
		case "replaceselection":
			self = .replaceSelection
		default:
			self = .replaceInput
		}
	}
}

// MARK: - Output Format

/// Format of the command's output.
public enum CommandOutputFormat: String, Sendable, Codable {
	/// Plain text.
	case text
	/// Snippet with tab stops.
	case snippet
	/// HTML (displayed in HTML output window).
	case html
	/// Completion list (presented as autocomplete popup).
	case completionList
	/// Snippet without auto-indent.
	case snippetNoAutoIndent
}

// MARK: - Output Caret Placement

/// Where the caret is placed after inserting command output.
public enum CommandOutputCaret: String, Sendable, Codable {
	/// After the inserted output.
	case afterOutput
	/// Select all inserted output.
	case selectOutput
	/// Interpolate caret position character-by-character.
	case interpolateByChar
	/// Interpolate caret position line-by-line.
	case interpolateByLine
	/// Heuristic placement (intelligent guess).
	case heuristic
}

// MARK: - Output Reuse

/// How the HTML output window is reused.
public enum CommandOutputReuse: String, Sendable, Codable {
	/// Reuse any available window.
	case reuseAvailable
	/// Always create a new window.
	case reuseNone
	/// Reuse a busy window.
	case reuseBusy
	/// Abort the running command and reuse its window.
	case abortAndReuseBusy
}

// MARK: - Auto-Refresh

/// When to automatically re-run the command.
public struct AutoRefresh: OptionSet, Sendable, Codable {
	public let rawValue: Int

	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let never = AutoRefresh([])
	public static let onDocumentChange = AutoRefresh(rawValue: 1 << 0)
	public static let onDocumentSave = AutoRefresh(rawValue: 1 << 1)
	public static let onDocumentClose = AutoRefresh(rawValue: 1 << 2)
}

// MARK: - Bundle Command

/// A fully parsed bundle command ready for execution.
///
/// Counterpart of the C++ `bundle_command_t` struct in
/// `Frameworks/command/src/parser.h`.
public struct BundleCommand: Sendable {
	/// Display name of the command.
	public var name: String
	/// UUID of the originating bundle item.
	public var uuid: String
	/// Scope selector that determines when the command is available.
	public var scopeSelector: String
	/// The command script to execute.
	public var command: String

	/// Action to take before execution.
	public var preExec: PreExecAction
	/// Where to read input from.
	public var input: CommandInput
	/// Fallback input source if the primary is empty.
	public var inputFallback: CommandInput
	/// Format of the input.
	public var inputFormat: CommandInputFormat
	/// Where to place the output.
	public var output: CommandOutput
	/// Format of the output.
	public var outputFormat: CommandOutputFormat
	/// Where to place the caret after output.
	public var outputCaret: CommandOutputCaret
	/// How to reuse the output window.
	public var outputReuse: CommandOutputReuse
	/// When to auto-refresh.
	public var autoRefresh: AutoRefresh

	/// Whether to auto-scroll HTML output.
	public var autoScrollOutput: Bool
	/// Whether to disable auto-indent for output.
	public var disableOutputAutoIndent: Bool
	/// Whether to disable the JavaScript API in HTML output.
	public var disableJavaScriptAPI: Bool

	public init(
		name: String = "",
		uuid: String = "",
		scopeSelector: String = "",
		command: String = "",
		preExec: PreExecAction = .nop,
		input: CommandInput = .selection,
		inputFallback: CommandInput = .entireDocument,
		inputFormat: CommandInputFormat = .text,
		output: CommandOutput = .replaceInput,
		outputFormat: CommandOutputFormat = .text,
		outputCaret: CommandOutputCaret = .afterOutput,
		outputReuse: CommandOutputReuse = .reuseAvailable,
		autoRefresh: AutoRefresh = .never,
		autoScrollOutput: Bool = false,
		disableOutputAutoIndent: Bool = false,
		disableJavaScriptAPI: Bool = false,
	) {
		self.name = name
		self.uuid = uuid
		self.scopeSelector = scopeSelector
		self.command = command
		self.preExec = preExec
		self.input = input
		self.inputFallback = inputFallback
		self.inputFormat = inputFormat
		self.output = output
		self.outputFormat = outputFormat
		self.outputCaret = outputCaret
		self.outputReuse = outputReuse
		self.autoRefresh = autoRefresh
		self.autoScrollOutput = autoScrollOutput
		self.disableOutputAutoIndent = disableOutputAutoIndent
		self.disableJavaScriptAPI = disableJavaScriptAPI
	}
}

// MARK: - Shebang Handling

public extension BundleCommand {
	/// Ensure the command starts with a shebang line.
	///
	/// If no shebang is present, prepends `#!/bin/bash` and optionally sources
	/// the TextMate bash init script (matching C++ `fix_shebang()`).
	mutating func fixShebang(supportPath: String? = nil) {
		guard !command.hasPrefix("#!") else { return }
		var preamble = "#!/bin/bash\n"
		if let supportPath {
			preamble +=
				"[[ -f \"\(supportPath)/lib/bash_init.sh\" ]] && source \"\(supportPath)/lib/bash_init.sh\"\n"
		} else {
			preamble +=
				"[[ -f \"${TM_SUPPORT_PATH}/lib/bash_init.sh\" ]] && . \"${TM_SUPPORT_PATH}/lib/bash_init.sh\"\n"
		}
		command = preamble + "\n" + command
	}
}
