import Foundation

// MARK: - Bundle Command Parser

/// Parses raw plist dictionaries (from `.tmCommand` files) into
/// `BundleCommand` structs ready for execution.
///
/// Handles both v1 and v2 command formats, mapping legacy keys
/// to the modern command structure.
public struct BundleCommandParser: Sendable {
	public init() {}

	/// Parses a bundle item's plist into a `BundleCommand`.
	/// Returns `nil` if the plist does not represent a valid command.
	public func parse(
		plist: [String: Any],
		name: String? = nil,
		uuid: String? = nil,
	) -> BundleCommand? {
		guard let command = plist["command"] as? String else { return nil }

		let resolvedName = name ?? plist["name"] as? String ?? "Untitled"
		let resolvedUUID = uuid ?? plist["uuid"] as? String ?? UUID().uuidString

		return BundleCommand(
			name: resolvedName,
			uuid: resolvedUUID,
			scopeSelector: plist["scope"] as? String ?? "",
			command: command,
			preExec: parsePreExec(plist),
			input: parseInput(plist),
			inputFallback: parseInputFallback(plist),
			inputFormat: parseInputFormat(plist),
			output: parseOutput(plist),
			outputFormat: parseOutputFormat(plist),
			outputCaret: parseOutputCaret(plist),
			outputReuse: parseOutputReuse(plist),
			autoRefresh: parseAutoRefresh(plist),
			autoScrollOutput: plist["autoScrollOutput"] as? Bool ?? false,
			disableOutputAutoIndent: plist["disableOutputAutoIndent"] as? Bool ?? false,
			disableJavaScriptAPI: plist["disableJavaScriptAPI"] as? Bool ?? false,
		)
	}

	/// Parses a `BundleItem`'s plist into a `BundleCommand`.
	public func parse(item: BundleItem) -> BundleCommand? {
		guard let plist = item.plist else { return nil }
		return parse(plist: plist, name: item.name, uuid: item.uuid)
	}

	// MARK: - Field Parsers

	private func parsePreExec(_ plist: [String: Any]) -> PreExecAction {
		guard let value = plist["beforeRunningCommand"] as? String else {
			return .nop
		}
		switch value {
		case "saveActiveFile": return .saveDocument
		case "saveModifiedFiles": return .saveProject
		case "nop": return .nop
		default: return .nop
		}
	}

	private func parseInput(_ plist: [String: Any]) -> CommandInput {
		guard let value = plist["input"] as? String else {
			return .selection
		}
		return CommandInput(plistString: value) ?? .selection
	}

	private func parseInputFallback(_ plist: [String: Any]) -> CommandInput {
		// v2 format: inputFormat is separate.
		if let value = plist["inputFallback"] as? String {
			return CommandInput(plistString: value) ?? .entireDocument
		}
		// v1 format: fallbackInput key.
		if let value = plist["fallbackInput"] as? String {
			return CommandInput(plistString: value) ?? .entireDocument
		}
		return .entireDocument
	}

	private func parseInputFormat(_ plist: [String: Any]) -> CommandInputFormat {
		guard let value = plist["inputFormat"] as? String else {
			return .text
		}
		switch value {
		case "xml": return .xml
		default: return .text
		}
	}

	private func parseOutput(_ plist: [String: Any]) -> CommandOutput {
		guard let value = plist["output"] as? String else {
			return .replaceInput
		}
		return CommandOutput(plistString: value) ?? .replaceInput
	}

	private func parseOutputFormat(_ plist: [String: Any]) -> CommandOutputFormat {
		guard let value = plist["outputFormat"] as? String else {
			return .text
		}
		switch value {
		case "snippet": return .snippet
		case "html": return .html
		case "completionList": return .completionList
		case "snippetNoAutoIndent": return .snippetNoAutoIndent
		default: return .text
		}
	}

	private func parseOutputCaret(_ plist: [String: Any]) -> CommandOutputCaret {
		guard let value = plist["outputCaret"] as? String else {
			return .afterOutput
		}
		switch value {
		case "afterOutput": return .afterOutput
		case "selectOutput": return .selectOutput
		case "interpolateByChar": return .interpolateByChar
		case "interpolateByLine": return .interpolateByLine
		case "heuristic": return .heuristic
		default: return .afterOutput
		}
	}

	private func parseOutputReuse(_ plist: [String: Any]) -> CommandOutputReuse {
		guard let value = plist["outputReuse"] as? String else {
			return .reuseAvailable
		}
		switch value {
		case "reuseAvailable": return .reuseAvailable
		case "reuseNone": return .reuseNone
		case "reuseBusy": return .reuseBusy
		case "abortAndReuseBusy": return .abortAndReuseBusy
		default: return .reuseAvailable
		}
	}

	private func parseAutoRefresh(_ plist: [String: Any]) -> AutoRefresh {
		if let value = plist["autoRefresh"] as? Int {
			return AutoRefresh(rawValue: value)
		}
		if let dict = plist["autoRefresh"] as? [String: Bool] {
			var result = AutoRefresh.never
			if dict["onDocumentChange"] == true { result.insert(.onDocumentChange) }
			if dict["onDocumentSave"] == true { result.insert(.onDocumentSave) }
			if dict["onDocumentClose"] == true { result.insert(.onDocumentClose) }
			return result
		}
		return .never
	}
}

// MARK: - BundleCommand Types (re-exported from TMCompatibility conceptually)

/// Pre-execution action before running a command.
public enum PreExecAction: String, Sendable, Codable {
	case nop
	case saveDocument
	case saveProject
}

/// Input source for a command.
public enum CommandInput: String, Sendable, Codable {
	case selection
	case entireDocument
	case scope
	case line
	case word
	case character
	case nothing

	public init?(plistString: String) {
		switch plistString {
		case "selection": self = .selection
		case "document", "entireDocument": self = .entireDocument
		case "scope": self = .scope
		case "line": self = .line
		case "word": self = .word
		case "character": self = .character
		case "none", "nothing": self = .nothing
		default: return nil
		}
	}
}

/// Input format for a command.
public enum CommandInputFormat: String, Sendable, Codable {
	case text
	case xml
}

/// Output destination for a command.
public enum CommandOutput: String, Sendable, Codable {
	case replaceInput
	case replaceDocument
	case atCaret
	case afterInput
	case newWindow
	case toolTip
	case discard
	case replaceSelection

	public init?(plistString: String) {
		switch plistString {
		case "replaceInput", "replaceSelectedText": self = .replaceInput
		case "replaceDocument": self = .replaceDocument
		case "atCaret", "insertAtCaret", "insertAsText": self = .atCaret
		case "afterInput", "afterSelectedText": self = .afterInput
		case "newWindow", "openAsNewDocument": self = .newWindow
		case "toolTip", "showAsTooltip": self = .toolTip
		case "discard": self = .discard
		case "replaceSelection": self = .replaceSelection
		default: return nil
		}
	}
}

/// Output format for a command.
public enum CommandOutputFormat: String, Sendable, Codable {
	case text
	case snippet
	case html
	case completionList
	case snippetNoAutoIndent
}

/// Caret placement after output.
public enum CommandOutputCaret: String, Sendable, Codable {
	case afterOutput
	case selectOutput
	case interpolateByChar
	case interpolateByLine
	case heuristic
}

/// HTML output window reuse strategy.
public enum CommandOutputReuse: String, Sendable, Codable {
	case reuseAvailable
	case reuseNone
	case reuseBusy
	case abortAndReuseBusy
}

/// Auto-refresh trigger bitmask.
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

/// A fully parsed bundle command ready for execution.
public struct BundleCommand: Sendable {
	public let name: String
	public let uuid: String
	public let scopeSelector: String
	public var command: String

	public let preExec: PreExecAction
	public let input: CommandInput
	public let inputFallback: CommandInput
	public let inputFormat: CommandInputFormat
	public let output: CommandOutput
	public let outputFormat: CommandOutputFormat
	public let outputCaret: CommandOutputCaret
	public let outputReuse: CommandOutputReuse
	public let autoRefresh: AutoRefresh

	public let autoScrollOutput: Bool
	public let disableOutputAutoIndent: Bool
	public let disableJavaScriptAPI: Bool

	public init(
		name: String,
		uuid: String,
		scopeSelector: String = "",
		command: String,
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

	/// Prepends `#!/bin/bash` and support script sourcing if no shebang present.
	public mutating func fixShebang(supportPath: String? = nil) {
		guard !command.hasPrefix("#!") else { return }
		var preamble = "#!/bin/bash\n"
		if let supportPath {
			preamble += "[[ -f \"\(supportPath)/lib/bash_init.sh\" ]] && source \"\(supportPath)/lib/bash_init.sh\"\n"
		}
		command = preamble + command
	}
}
