import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - mate CLI

// TextMate command-line interface — opens files in TextMate via the rmate
// protocol over TCP (localhost).
//
// Port of `Applications/mate/src/mate.mm` from the C++ codebase.
//
// Usage:
//   mate [options] [file ...]
//   mate -              (read from stdin)
//
// Options:
//   -l, --line LINE[:COL]   Open at line (and optional column)
//   -t, --type TYPE         Set the file type (grammar scope)
//   -n, --name NAME         Display name for untitled documents
//   -w, --wait              Wait for file to be closed
//   -r, --recent            Add to recent documents
//   -p, --port PORT         Server port (default: 52698 or RMATE_PORT)
//   -h, --help              Show this help
//   -v, --version           Show version

let version = "2.0.0-swift"

// MARK: - Option Parsing

struct Options {
	var line: String?
	var fileType: String?
	var displayName: String?
	var wait = false
	var addToRecents = true
	var port: UInt16 = 52698
	var files: [String] = []
	var readStdin = false
}

func printUsage() {
	let usage = """
	Usage: mate [options] [file ...]
	       mate -    (read from stdin)

	Options:
	  -l, --line LINE[:COL]  Open at line (and optional column)
	  -t, --type TYPE        Set the file type (grammar scope)
	  -n, --name NAME        Display name for untitled documents
	  -w, --wait             Wait for file to be closed
	  -r, --recent           Add to recent documents
	  -p, --port PORT        Server port (default: 52698 or RMATE_PORT)
	  -h, --help             Show this help
	  -v, --version          Show version
	"""
	FileHandle.standardError.write(Data(usage.utf8))
}

func parseArguments() -> Options {
	var opts = Options()

	// Read default port from environment.
	if let envPort = ProcessInfo.processInfo.environment["RMATE_PORT"],
	   let p = UInt16(envPort)
	{
		opts.port = p
	}

	// Parse MATEFLAGS environment variable.
	if let flags = ProcessInfo.processInfo.environment["MATEFLAGS"] {
		let parts = flags.split(separator: " ").map(String.init)
		parseFlagArray(parts, into: &opts)
	}

	// Parse command-line arguments.
	let args = Array(CommandLine.arguments.dropFirst())
	parseFlagArray(args, into: &opts)

	// Auto-enable wait when program name ends with _wait.
	let progName = (CommandLine.arguments[0] as NSString).lastPathComponent
	if progName.hasSuffix("_wait") {
		opts.wait = true
	}

	return opts
}

func parseFlagArray(_ args: [String], into opts: inout Options) {
	var i = 0
	while i < args.count {
		let arg = args[i]
		switch arg {
		case "-l", "--line":
			i += 1
			if i < args.count { opts.line = args[i] }
		case "-t", "--type":
			i += 1
			if i < args.count { opts.fileType = args[i] }
		case "-n", "--name":
			i += 1
			if i < args.count { opts.displayName = args[i] }
		case "-w", "--wait":
			opts.wait = true
		case "-r", "--recent":
			opts.addToRecents = true
		case "-p", "--port":
			i += 1
			if i < args.count, let p = UInt16(args[i]) { opts.port = p }
		case "-h", "--help":
			printUsage()
			exit(0)
		case "-v", "--version":
			print("mate \(version)")
			exit(0)
		case "-":
			opts.readStdin = true
		default:
			if arg.hasPrefix("-") {
				FileHandle.standardError.write(Data("Unknown option: \(arg)\n".utf8))
				printUsage()
				exit(1)
			}
			opts.files.append(arg)
		}
		i += 1
	}
}

// MARK: - RMate Protocol Client

/// Sends an rmate `open` command over a TCP socket.
func sendOpenCommand(
	to socket: FileHandle,
	path: String?,
	displayName: String?,
	selection: String?,
	fileType: String?,
	wait: Bool,
	addToRecents: Bool,
	data: Data?,
) {
	var msg = "open\r\n"

	if let path {
		msg += "path: \(path)\r\n"
		msg += "real-path: \(path)\r\n"
	}
	if let displayName {
		msg += "display-name: \(displayName)\r\n"
	}
	if let selection {
		msg += "selection: \(selection)\r\n"
	}
	if let fileType {
		msg += "file-type: \(fileType)\r\n"
	}
	if wait {
		msg += "wait: yes\r\n"
	}
	if addToRecents {
		msg += "add-to-recents: yes\r\n"
	}
	msg += "re-activate: yes\r\n"
	msg += "token: mate-\(ProcessInfo.processInfo.processIdentifier)\r\n"

	if let data {
		msg += "data: \(data.count)\r\n"
	}

	msg += "\r\n.\r\n"

	socket.write(Data(msg.utf8))

	// Write file data after the command if provided.
	if let data {
		socket.write(data)
	}
}

/// Reads lines from the server until a `close` command is received.
func waitForClose(socket: FileHandle) {
	// Read until we see "close\r\n" or the connection is closed.
	var buffer = Data()
	while true {
		let chunk = socket.availableData
		if chunk.isEmpty { break } // EOF
		buffer.append(chunk)
		if let str = String(data: buffer, encoding: .utf8),
		   str.contains("close")
		{
			break
		}
	}
}

// MARK: - TCP Connection

func connectToServer(port: UInt16) -> FileHandle? {
	let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
	guard fd >= 0 else { return nil }

	var addr = sockaddr_in()
	addr.sin_family = sa_family_t(AF_INET)
	addr.sin_port = port.bigEndian
	addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1

	let result = withUnsafePointer(to: &addr) {
		$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
			Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
		}
	}

	guard result == 0 else {
		Darwin.close(fd)
		return nil
	}

	return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

// MARK: - Main

let opts = parseArguments()

// If no files and no stdin, open an empty document.
if opts.files.isEmpty, !opts.readStdin {
	opts.files.isEmpty ? () : ()
}

guard let socket = connectToServer(port: opts.port) else {
	FileHandle.standardError.write(
		Data("mate: unable to connect to TextMate on port \(opts.port)\n".utf8),
	)
	FileHandle.standardError.write(
		Data("Make sure TextMate is running and the rmate server is enabled.\n".utf8),
	)
	exit(1)
}

if opts.readStdin {
	// Read all of stdin into memory.
	let data = FileHandle.standardInput.readDataToEndOfFile()
	sendOpenCommand(
		to: socket,
		path: nil,
		displayName: opts.displayName ?? "untitled (stdin)",
		selection: opts.line,
		fileType: opts.fileType,
		wait: opts.wait,
		addToRecents: opts.addToRecents,
		data: data,
	)
} else if opts.files.isEmpty {
	// Open an empty untitled document.
	sendOpenCommand(
		to: socket,
		path: nil,
		displayName: opts.displayName,
		selection: opts.line,
		fileType: opts.fileType,
		wait: opts.wait,
		addToRecents: opts.addToRecents,
		data: nil,
	)
} else {
	for file in opts.files {
		// Resolve to absolute path.
		let path: String
		if file.hasPrefix("/") {
			path = file
		} else {
			let cwd = FileManager.default.currentDirectoryPath
			path = (cwd as NSString).appendingPathComponent(file)
		}

		// Resolve symlinks.
		let resolved = (path as NSString).resolvingSymlinksInPath

		sendOpenCommand(
			to: socket,
			path: resolved,
			displayName: opts.displayName,
			selection: opts.line,
			fileType: opts.fileType,
			wait: opts.wait,
			addToRecents: opts.addToRecents,
			data: nil,
		)
	}
}

if opts.wait {
	waitForClose(socket: socket)
}

exit(0)
