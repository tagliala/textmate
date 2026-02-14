import Foundation

/// Handles placement of command output into the editor based on the
/// command's output settings.
///
/// This mirrors the routing logic from the C++ `runner_delegate_t::accept_result()`
/// in `Frameworks/command/src/runner.mm`.
public struct CommandOutputHandler: Sendable {
	/// Output placement computed from a `CommandResult`.
	public enum OutputAction: Sendable, Equatable {
		/// Discard – nothing to do.
		case discard

		/// Replace the original selection.
		case replaceSelection(String)

		/// Replace the entire document text.
		case replaceDocument(String)

		/// Insert text at the caret.
		case insertAtCaret(String)

		/// Insert text after the input range.
		case insertAfterInput(String)

		/// Insert as a snippet (with placeholder expansion).
		case insertSnippet(String)

		/// Show the output as an HTML page (new window / output panel).
		case showHTML(String)

		/// Show the output as a tooltip near the caret.
		case showToolTip(String)

		/// Show HTML in an existing (re-used) output window.
		case showHTMLReuse(String, CommandOutputReuse)

		/// Show completion list (output must be a property list).
		case showCompletions(String)
	}

	/// Determine the action for a finished command, respecting exit-code
	/// overrides as defined by TextMate's conventions.
	///
	/// - Parameter result: The finished command result.
	/// - Returns: The output action to apply.
	public static func action(for result: CommandResult) -> OutputAction {
		let text = result.stdoutString

		// Exit codes 200-206 override the bundle command's output setting.
		if result.exitCode >= 200, result.exitCode <= 206 {
			return actionForExitCode(result.exitCode, text: text)
		}

		// Non-zero exit codes (except the special range) → show as tooltip
		// (matching C++ behaviour of showing errors in a tooltip).
		if result.exitCode != 0 {
			let errorText = result.stderrString.isEmpty
				? text
				: result.stderrString
			return .showToolTip(errorText)
		}

		// Exit code 0 → use the command's declared output setting.
		return actionForOutput(
			result.command.output,
			format: result.command.outputFormat,
			reuse: result.command.outputReuse,
			text: text,
		)
	}

	/// Map exit-code overrides to actions.
	private static func actionForExitCode(_ code: Int32, text: String) -> OutputAction {
		switch code {
		case 200: .discard
		case 201: .replaceSelection(text)
		case 202: .replaceDocument(text)
		case 203: .insertSnippet(text)
		case 204: .showHTML(text)
		case 205: .showToolTip(text)
		case 206: .insertAtCaret(text)
		default: .discard
		}
	}

	/// Map declared output mode + format to an action.
	private static func actionForOutput(
		_ output: CommandOutput,
		format: CommandOutputFormat,
		reuse: CommandOutputReuse,
		text: String,
	) -> OutputAction {
		// Handle output format first for snippet/html/completions
		switch format {
		case .snippet, .snippetNoAutoIndent:
			return .insertSnippet(text)
		case .html:
			return .showHTML(text)
		case .completionList:
			return .showCompletions(text)
		case .text:
			break
		}

		switch output {
		case .replaceInput:
			return .replaceSelection(text)
		case .replaceDocument:
			return .replaceDocument(text)
		case .atCaret:
			return .insertAtCaret(text)
		case .afterInput:
			return .insertAfterInput(text)
		case .newWindow:
			return .showHTMLReuse(text, reuse)
		case .toolTip:
			return .showToolTip(text)
		case .discard:
			return .discard
		case .replaceSelection:
			return .replaceSelection(text)
		}
	}

	// MARK: - Caret Placement

	/// Describes how the caret should be positioned after text insertion.
	public enum CaretPlacement: Sendable, Equatable {
		/// Place caret after the inserted text.
		case afterOutput
		/// Select the entire inserted text.
		case selectOutput
		/// Interpolate character-by-character (for animated typing).
		case interpolateByChar
		/// Interpolate line-by-line (for animated output).
		case interpolateByLine
		/// Editor chooses the best position heuristically.
		case heuristic
	}

	/// Convert a `CommandOutputCaret` into a `CaretPlacement`.
	public static func caretPlacement(for caret: CommandOutputCaret) -> CaretPlacement {
		switch caret {
		case .afterOutput: .afterOutput
		case .selectOutput: .selectOutput
		case .interpolateByChar: .interpolateByChar
		case .interpolateByLine: .interpolateByLine
		case .heuristic: .heuristic
		}
	}
}
