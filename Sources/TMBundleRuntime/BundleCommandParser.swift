import Foundation
import TMCompatibility

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
		return CommandInput(plistString: value)
	}

	private func parseInputFallback(_ plist: [String: Any]) -> CommandInput {
		// v2 format: inputFormat is separate.
		if let value = plist["inputFallback"] as? String {
			return CommandInput(plistString: value)
		}
		// v1 format: fallbackInput key.
		if let value = plist["fallbackInput"] as? String {
			return CommandInput(plistString: value)
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
		return CommandOutput(plistString: value)
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
