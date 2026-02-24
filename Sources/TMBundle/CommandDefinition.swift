import Foundation

/// A TextMate command definition loaded from a `.tmCommand` plist.
///
/// Commands execute shell scripts or other programs, receiving the
/// current document text (or selection) as input and producing output
/// that can replace the selection, insert as a snippet, show in a
/// tooltip, etc.
public struct CommandDefinition: Sendable {
	/// Display name.
	public let name: String

	/// UUID of the command bundle item.
	public let uuid: String?

	/// The shell command to execute.
	public let command: String

	/// Key equivalent for triggering this command.
	public let keyEquivalent: String?

	/// Tab trigger string.
	public let tabTrigger: String?

	/// Scope selector.
	public let scope: String?

	/// Where to get input for the command.
	public let input: InputSource

	/// Fallback input if the primary input is empty.
	public let inputFallback: InputSource?

	/// What to do with the command's output.
	public let output: OutputDestination

	/// Whether to save files before running the command.
	public let beforeRunning: BeforeRunAction

	/// Semantic class (e.g. "callback.document.save").
	public let semanticClass: String?

	/// Whether to disable output auto-indent.
	public let disableOutputAutoIndent: Bool

	/// Required shell commands (e.g. ["ruby", "python"]).
	public let requiredCommands: [String]?

	// MARK: - Enums

	/// Where the command gets its input text.
	public enum InputSource: String, Sendable {
		case none
		case selection
		case document
		case line
		case word
		case character
		case scope
	}

	/// What the command does with its output.
	public enum OutputDestination: String, Sendable {
		case replaceSelectedText
		case replaceDocument
		case afterSelectedText
		case insertAsSnippet
		case showAsHTML
		case showAsTooltip
		case createNewDocument
		case openAsNewDocument
		case discard
		case nop
	}

	/// Action to perform before running the command.
	public enum BeforeRunAction: String, Sendable {
		case nothing = "nop"
		case saveActiveFile
		case saveModifiedFiles
	}

	// MARK: - Parsing

	/// Loads a command from a `.tmCommand` plist file.
	public static func load(from url: URL) throws -> CommandDefinition {
		let dict = try BundlePlistParser.load(url: url)
		return try parse(dict)
	}

	/// Parses a command from a plist dictionary.
	public static func parse(_ dict: [String: Any]) throws -> CommandDefinition {
		let command = try BundlePlistParser.string(dict, key: "command")
		let name = BundlePlistParser.optionalString(dict, key: "name") ?? "Untitled"

		let inputStr = BundlePlistParser.optionalString(dict, key: "input") ?? "selection"
		let input = InputSource(rawValue: inputStr) ?? .selection

		let fallbackStr = BundlePlistParser.optionalString(dict, key: "fallbackInput")
		let inputFallback = fallbackStr.flatMap { InputSource(rawValue: $0) }

		let outputStr = BundlePlistParser.optionalString(dict, key: "output") ?? "replaceSelectedText"
		let output = OutputDestination(rawValue: outputStr) ?? .replaceSelectedText

		let beforeStr = BundlePlistParser.optionalString(dict, key: "beforeRunningCommand") ?? "nop"
		let before = BeforeRunAction(rawValue: beforeStr) ?? .nothing

		return CommandDefinition(
			name: name,
			uuid: BundlePlistParser.optionalString(dict, key: "uuid"),
			command: command,
			keyEquivalent: BundlePlistParser.optionalString(dict, key: "keyEquivalent"),
			tabTrigger: BundlePlistParser.optionalString(dict, key: "tabTrigger"),
			scope: BundlePlistParser.optionalString(dict, key: "scope"),
			input: input,
			inputFallback: inputFallback,
			output: output,
			beforeRunning: before,
			semanticClass: BundlePlistParser.optionalString(dict, key: "semanticClass"),
			disableOutputAutoIndent: BundlePlistParser.optionalBool(dict, key: "disableOutputAutoIndent") ?? false,
			requiredCommands: BundlePlistParser.optionalStringArray(dict, key: "requiredCommands"),
		)
	}
}
