import Foundation
import TMCompatibility

// MARK: - Refresh Trigger

/// Events that can trigger an auto-refresh.
enum RefreshTrigger: Sendable, Equatable {
	case documentChange
	case documentSave
	case documentClose
}

// MARK: - Scheduled Command

/// A command registered for auto-refresh execution.
struct ScheduledCommand: Sendable {
	let command: BundleCommand
	let triggers: AutoRefresh
	let bundleName: String
}

// MARK: - Auto-Refresh Scheduler

/// Monitors document events and re-executes commands that have auto-refresh enabled.
///
/// When a bundle command declares `autoRefresh` with one or more triggers
/// (onDocumentChange, onDocumentSave, onDocumentClose), this scheduler
/// re-executes the command when those events occur.
@MainActor
public final class AutoRefreshScheduler {
	/// The command dispatcher used to re-execute commands.
	private weak var dispatcher: CommandDispatcher?

	/// Registered auto-refresh commands, keyed by command UUID.
	private var registeredCommands: [String: ScheduledCommand] = [:]

	/// Debounce timer for document changes (100ms).
	private var changeDebounceTimer: Timer?

	/// The debounce interval for document change events.
	public var changeDebounceInterval: TimeInterval = 0.1

	public init(dispatcher: CommandDispatcher) {
		self.dispatcher = dispatcher
	}

	// MARK: - Registration

	/// Registers a command for auto-refresh if it has any triggers configured.
	public func register(command: BundleCommand, bundleName: String = "") {
		guard command.autoRefresh != .never else { return }
		registeredCommands[command.uuid] = ScheduledCommand(
			command: command,
			triggers: command.autoRefresh,
			bundleName: bundleName,
		)
	}

	/// Unregisters a command from auto-refresh.
	public func unregister(commandUUID: String) {
		registeredCommands.removeValue(forKey: commandUUID)
	}

	/// Unregisters all commands.
	public func unregisterAll() {
		registeredCommands.removeAll()
		changeDebounceTimer?.invalidate()
		changeDebounceTimer = nil
	}

	/// Returns the UUIDs of all registered commands.
	public var registeredCommandUUIDs: [String] {
		Array(registeredCommands.keys)
	}

	// MARK: - Event Dispatch

	/// Called when a document change event occurs.
	public func documentDidChange() {
		// Debounce rapid change events.
		changeDebounceTimer?.invalidate()
		changeDebounceTimer = Timer.scheduledTimer(
			withTimeInterval: changeDebounceInterval,
			repeats: false,
		) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.fireTrigger(.documentChange)
			}
		}
	}

	/// Called when a document is saved.
	public func documentDidSave() {
		fireTrigger(.documentSave)
	}

	/// Called when a document is closed.
	public func documentDidClose() {
		fireTrigger(.documentClose)
	}

	/// Fires all commands matching the given trigger.
	private func fireTrigger(_ trigger: RefreshTrigger) {
		guard let dispatcher else { return }

		let matching = registeredCommands.values.filter { scheduled in
			switch trigger {
			case .documentChange: scheduled.triggers.contains(.onDocumentChange)
			case .documentSave: scheduled.triggers.contains(.onDocumentSave)
			case .documentClose: scheduled.triggers.contains(.onDocumentClose)
			}
		}

		for scheduled in matching {
			Task {
				await dispatcher.execute(
					command: scheduled.command,
					bundleName: scheduled.bundleName,
				)
			}
		}
	}

	/// Returns the number of registered commands.
	public var registeredCount: Int {
		registeredCommands.count
	}
}
