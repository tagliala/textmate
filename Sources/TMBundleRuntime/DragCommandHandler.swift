import Foundation
import TMCompatibility

// MARK: - Drag Command

/// A parsed drag command ready for execution.
public struct DragCommand: Sendable {
	public let uuid: String
	public let name: String
	public let scopeSelector: String
	public let command: String
	public let extensions: [String]
	public let draggedFileExtensions: [String]

	public init(
		uuid: String,
		name: String,
		scopeSelector: String = "",
		command: String,
		extensions: [String] = [],
		draggedFileExtensions: [String] = [],
	) {
		self.uuid = uuid
		self.name = name
		self.scopeSelector = scopeSelector
		self.command = command
		self.extensions = extensions
		self.draggedFileExtensions = draggedFileExtensions
	}
}

// MARK: - Drag Command Handler

/// Finds and executes drag commands that match dropped file types.
///
/// When files are dragged into the editor, this handler:
/// 1. Examines the file extensions of the dropped files
/// 2. Queries the bundle index for drag commands matching the current scope
/// 3. Filters to commands whose `extensions` include the dropped file type
/// 4. Executes the matching command (or presents a disambiguation menu)
@MainActor
public final class DragCommandHandler {
	private let bundleIndex: BundleIndex
	private let parser = BundleCommandParser()

	public init(bundleIndex: BundleIndex) {
		self.bundleIndex = bundleIndex
	}

	/// Finds drag commands that can handle files with the given extensions
	/// in the current scope.
	public func findCommands(
		forFileExtensions extensions: [String],
		scope: String,
	) -> [DragCommand] {
		let items = bundleIndex.query(BundleQuery(
			kinds: .dragCommand,
			includeDisabled: false,
		))

		return items.compactMap { item -> DragCommand? in
			guard let plist = item.plist else { return nil }

			// Check scope match (simplified — full scope selector matching
			// would use TMGrammar's ScopeSelector).
			if !item.scopeSelector.isEmpty && !scope.hasPrefix(item.scopeSelector) {
				return nil
			}

			// Check extension match.
			let commandExtensions = plist["draggedFileExtensions"] as? [String] ?? []
			let hasMatch = commandExtensions.isEmpty || extensions.contains(where: { ext in
				commandExtensions.contains(ext.lowercased())
			})
			guard hasMatch else { return nil }

			guard let command = plist["command"] as? String else { return nil }

			return DragCommand(
				uuid: item.uuid,
				name: item.name,
				scopeSelector: item.scopeSelector,
				command: command,
				extensions: commandExtensions,
				draggedFileExtensions: extensions,
			)
		}
	}

	/// Builds a `BundleCommand` from a `DragCommand` with drag-specific
	/// environment variables set.
	public func buildBundleCommand(
		from dragCommand: DragCommand,
		droppedFiles _: [String],
	) -> BundleCommand {
		var cmd = BundleCommand(
			name: dragCommand.name,
			uuid: dragCommand.uuid,
			scopeSelector: dragCommand.scopeSelector,
			command: dragCommand.command,
			input: .nothing,
			output: .atCaret,
			outputFormat: .snippet,
		)
		cmd.fixShebang()
		return cmd
	}

	/// Returns additional environment variables for drag command execution.
	public func dragEnvironment(droppedFiles: [String]) -> [String: String] {
		var env: [String: String] = [:]
		env["TM_DROPPED_FILE"] = droppedFiles.first ?? ""
		env["TM_DROPPED_FILEPATH"] = droppedFiles.first ?? ""

		if droppedFiles.count > 1 {
			env["TM_DROPPED_FILEPATHS"] = droppedFiles.joined(separator: "\n")
		}

		// Modifier keys are set at runtime by the UI layer.
		env["TM_MODIFIER_FLAGS"] = ""

		return env
	}
}
