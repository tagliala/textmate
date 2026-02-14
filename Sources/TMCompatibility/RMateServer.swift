import Foundation
#if canImport(Network)
import Network

/// NWListener-based rmate server for remote file editing.
///
/// Replaces the C++ `rmate_server_t` in
/// `Applications/TextMate/src/RMateServer.mm`.
///
/// The rmate protocol is a simple text-based TCP protocol:
/// 1. Server sends a welcome line: `220 hostname RMATE TextMate (OS)\n`
/// 2. Client sends commands (one per connection):
///    - `open\r\n` followed by key-value arguments
///    - `set-mark\r\n` / `clear-mark\r\n`
///    - A blank line separates records
///    - `.` or `quit` terminates the session
/// 3. Server may respond with `save\r\n` or `close\r\n` callbacks.
@MainActor
public final class RMateServer {
	/// Default rmate port (matching the C++ default).
	public static let defaultPort: UInt16 = 52698

	/// Current listening port.
	public private(set) var port: UInt16

	/// Whether to accept connections from remote hosts (vs loopback only).
	public private(set) var listenForRemoteClients: Bool

	/// The NWListener instance.
	private var listener: NWListener?

	/// Active connections.
	private var connections: [ObjectIdentifier: RMateConnection] = [:]

	/// Delegate receiving open/mark requests.
	public weak var delegate: RMateServerDelegate?

	// MARK: - Initialization

	public init(
		port: UInt16 = RMateServer.defaultPort,
		listenForRemoteClients: Bool = false,
	) {
		self.port = port
		self.listenForRemoteClients = listenForRemoteClients
	}

	// MARK: - Start / Stop

	/// Start listening for connections.
	public func start() throws {
		stop()

		let params = NWParameters.tcp
		if !listenForRemoteClients {
			// Restrict to loopback
			params.requiredInterfaceType = .loopback
		}

		let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
		nwListener.stateUpdateHandler = { [weak self] state in
			Task { @MainActor [weak self] in
				self?.handleStateUpdate(state)
			}
		}
		nwListener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor [weak self] in
				self?.handleNewConnection(connection)
			}
		}
		nwListener.start(queue: .main)
		listener = nwListener
	}

	/// Stop listening and close all connections.
	public func stop() {
		listener?.cancel()
		listener = nil
		connections.removeAll()
	}

	/// Reconfigure the server (restart if settings changed).
	public func reconfigure(
		enabled: Bool,
		port: UInt16,
		listenForRemoteClients: Bool,
	) throws {
		if !enabled {
			stop()
			return
		}

		if port != self.port || listenForRemoteClients != self.listenForRemoteClients {
			self.port = port
			self.listenForRemoteClients = listenForRemoteClients
			try start()
		} else if listener == nil {
			try start()
		}
	}

	/// Whether the server is currently listening.
	public var isListening: Bool {
		listener != nil
	}

	// MARK: - Connection Handling

	private func handleStateUpdate(_ state: NWListener.State) {
		switch state {
		case .ready:
			break
		case let .failed(error):
			NSLog("RMateServer: listener failed: %@", error.localizedDescription)
			listener = nil
		case .cancelled:
			listener = nil
		default:
			break
		}
	}

	private func handleNewConnection(_ nwConnection: NWConnection) {
		let connection = RMateConnection(
			connection: nwConnection,
			delegate: self,
		)
		let id = ObjectIdentifier(connection)
		connections[id] = connection
		connection.start()
	}

	fileprivate func connectionDidFinish(_ connection: RMateConnection) {
		let id = ObjectIdentifier(connection)
		connections.removeValue(forKey: id)
	}

	fileprivate func connectionDidReceiveRecords(
		_: RMateConnection,
		records: [RMateRecord],
	) {
		for record in records {
			switch record.command {
			case "open", "":
				delegate?.rmateServer(self, didReceiveOpenRequest: RMateOpenRequest(record: record))
			case "set-mark":
				delegate?.rmateServer(self, didReceiveSetMark: record.arguments)
			case "clear-mark":
				delegate?.rmateServer(self, didReceiveClearMark: record.arguments)
			default:
				NSLog("RMateServer: unknown command '%@'", record.command)
			}
		}
	}

	/// Generate the welcome message matching the C++ format.
	static func welcomeMessage() -> String {
		var sysname = ""
		var release = ""
		var nodename = ""
		var info = utsname()
		if uname(&info) == 0 {
			sysname = withUnsafePointer(to: &info.sysname) {
				$0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
			}
			release = withUnsafePointer(to: &info.release) {
				$0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
			}
			nodename = withUnsafePointer(to: &info.nodename) {
				$0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
			}
		}
		return "220 \(nodename) RMATE TextMate (\(sysname) \(release))\n"
	}
}

// MARK: - Connection

/// Handles a single rmate TCP connection and parses the text protocol.
@MainActor
final class RMateConnection {
	private let connection: NWConnection
	private weak var server: RMateServer?

	private var records: [RMateRecord] = []
	private var buffer = Data()
	private var currentRecord: RMateRecord?
	private var bytesLeft: Int = 0

	private enum ParseState {
		case command
		case arguments
		case data
	}

	private var state: ParseState = .command

	init(connection: NWConnection, delegate: RMateServer) {
		self.connection = connection
		server = delegate
	}

	func start() {
		connection.stateUpdateHandler = { [weak self] state in
			Task { @MainActor [weak self] in
				if case .ready = state {
					self?.sendWelcome()
				}
			}
		}
		connection.start(queue: .main)
	}

	private func sendWelcome() {
		let welcome = RMateServer.welcomeMessage()
		connection.send(
			content: Data(welcome.utf8),
			completion: .contentProcessed { [weak self] _ in
				Task { @MainActor [weak self] in
					self?.readNextChunk()
				}
			},
		)
	}

	private func readNextChunk() {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
			[weak self] data, _, isComplete, error in
			Task { @MainActor [weak self] in
				guard let self else { return }
				if let data, !data.isEmpty {
					buffer.append(data)
					if parse() {
						// Done — deliver records
						server?.connectionDidReceiveRecords(self, records: records)
						server?.connectionDidFinish(self)
						return
					}
				}
				if isComplete || error != nil {
					server?.connectionDidFinish(self)
				} else {
					readNextChunk()
				}
			}
		}
	}

	/// Parse buffered data. Returns `true` when done (`.` or `quit` received).
	private func parse() -> Bool {
		// Handle data state first — consume binary data
		if state == .data {
			let available = min(buffer.count, bytesLeft)
			if available > 0 {
				let chunk = buffer.prefix(available)
				currentRecord?.acceptData(chunk)
				buffer.removeFirst(available)
				bytesLeft -= available
			}
			if bytesLeft == 0 {
				state = .arguments
			} else {
				return false // need more data
			}
		}

		// Process lines
		while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
			var lineEnd = newlineIndex
			if lineEnd > buffer.startIndex, buffer[buffer.index(before: lineEnd)] == UInt8(ascii: "\r") {
				lineEnd = buffer.index(before: lineEnd)
			}
			let lineData = buffer[buffer.startIndex ..< lineEnd]
			let line = String(data: Data(lineData), encoding: .utf8) ?? ""
			buffer.removeFirst(buffer.distance(from: buffer.startIndex, to: buffer.index(after: newlineIndex)))

			if line.isEmpty {
				// Blank line → end of current record, back to command state
				if let record = currentRecord {
					records.append(record)
					currentRecord = nil
				}
				state = .command
				continue
			}

			if line == "." || line.lowercased() == "quit" {
				if let record = currentRecord {
					records.append(record)
					currentRecord = nil
				}
				return true
			}

			switch state {
			case .command:
				currentRecord = RMateRecord(command: line)
				state = .arguments

			case .arguments:
				if let colonIdx = line.firstIndex(of: ":") {
					let key = String(line[line.startIndex ..< colonIdx])
					let valueStart = line.index(after: colonIdx)
					let value = if valueStart < line.endIndex, line[valueStart] == " " {
						String(line[line.index(after: valueStart)...])
					} else if valueStart < line.endIndex {
						String(line[valueStart...])
					} else {
						""
					}

					if key == "data" {
						bytesLeft = Int(value) ?? 0
						if bytesLeft > 0 {
							let available = min(buffer.count, bytesLeft)
							if available > 0 {
								currentRecord?.acceptData(buffer.prefix(available))
								buffer.removeFirst(available)
								bytesLeft -= available
							}
							if bytesLeft > 0 {
								state = .data
								return false
							}
						}
					} else {
						let unescaped = unescapeValue(value)
						currentRecord?.arguments[key] = unescaped
					}
				}

			case .data:
				break // handled above
			}
		}

		return false
	}

	/// Unescape backslash sequences in values (matching C++ parser).
	private func unescapeValue(_ value: String) -> String {
		guard value.contains("\\") else { return value }
		var result = ""
		var escape = false
		for ch in value {
			if escape {
				result.append(ch == "n" ? "\n" : ch)
				escape = false
			} else if ch == "\\" {
				escape = true
			} else {
				result.append(ch)
			}
		}
		return result
	}

	/// Write save/close callbacks back to the client.
	func sendSaveCallback(token: String?) {
		var msg = "save\r\n"
		if let token {
			msg += "token: \(token)\r\n"
		}
		msg += "\r\n"
		connection.send(content: Data(msg.utf8), completion: .idempotent)
	}

	func sendCloseCallback(token: String?) {
		var msg = "close\r\n"
		if let token {
			msg += "token: \(token)\r\n"
		}
		msg += "\r\n"
		connection.send(content: Data(msg.utf8), completion: .idempotent)
	}
}

// MARK: - Protocol Types

/// A parsed rmate protocol record (one command with its arguments).
public struct RMateRecord: Sendable {
	/// The command name (e.g. "open", "set-mark", "clear-mark").
	public var command: String

	/// Key-value arguments.
	public var arguments: [String: String] = [:]

	/// File data (written to a temp file path stored in arguments["data"]).
	public var fileData: Data?

	public init(command: String) {
		self.command = command
	}

	mutating func acceptData(_ data: some Collection<UInt8>) {
		if fileData == nil {
			fileData = Data()
		}
		fileData?.append(contentsOf: data)
	}
}

/// Parsed open request from the rmate protocol.
public struct RMateOpenRequest: Sendable {
	public let path: String?
	public let uuid: String?
	public let realPath: String?
	public let token: String?
	public let displayName: String?
	public let selection: String?
	public let fileType: String?
	public let projectUUID: String?
	public let addToRecents: Bool
	public let reActivate: Bool
	public let wait: Bool
	public let dataOnSave: Bool
	public let dataOnClose: Bool
	public let fileData: Data?

	init(record: RMateRecord) {
		path = record.arguments["path"]
		uuid = record.arguments["uuid"]
		realPath = record.arguments["real-path"]
		token = record.arguments["token"]
		displayName = record.arguments["display-name"]
		selection = record.arguments["selection"]
		fileType = record.arguments["file-type"]
		projectUUID = record.arguments["project-uuid"]
		addToRecents = record.arguments["add-to-recents"] == "yes"
		reActivate = record.arguments["re-activate"] == "yes"
		wait = record.arguments["wait"] == "yes"
		dataOnSave = record.arguments["data-on-save"] == "yes"
		dataOnClose = record.arguments["data-on-close"] == "yes"
		fileData = record.fileData
	}
}

// MARK: - Server Delegate

/// Delegate for RMateServer events.
@MainActor
public protocol RMateServerDelegate: AnyObject {
	/// An `open` command was received.
	func rmateServer(_ server: RMateServer, didReceiveOpenRequest request: RMateOpenRequest)

	/// A `set-mark` command was received.
	func rmateServer(_ server: RMateServer, didReceiveSetMark arguments: [String: String])

	/// A `clear-mark` command was received.
	func rmateServer(_ server: RMateServer, didReceiveClearMark arguments: [String: String])
}

/// Default no-op implementations.
public extension RMateServerDelegate {
	func rmateServer(_: RMateServer, didReceiveOpenRequest _: RMateOpenRequest) {}
	func rmateServer(_: RMateServer, didReceiveSetMark _: [String: String]) {}
	func rmateServer(_: RMateServer, didReceiveClearMark _: [String: String]) {}
}
#endif
