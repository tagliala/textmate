import Foundation
import Testing
@testable import TMCore

@Suite("ProcessExecution — Pipe & Spawn")
struct ProcessExecutionTests {
	@Test("createPipe returns valid file descriptors")
	func createPipe() {
		let pipe = ProcessExecution.createPipe()
		#expect(pipe != nil)
		if let (rd, wr) = pipe {
			#expect(rd >= 0)
			#expect(wr >= 0)
			close(rd)
			close(wr)
		}
	}

	@Test("exec runs simple echo command")
	func execEcho() {
		let result = ProcessExecution.exec(["/bin/echo", "hello"])
		#expect(result != nil)
		#expect(result?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
	}

	@Test("exec returns nil on non-zero exit")
	func execFailure() {
		let result = ProcessExecution.exec(["/bin/sh", "-c", "exit 42"])
		#expect(result == nil)
	}

	@Test("exec with environment variables")
	func execWithEnv() {
		let result = ProcessExecution.exec(
			["/bin/sh", "-c", "echo $MY_TEST_VAR"],
			environment: ["MY_TEST_VAR": "hello42"],
		)
		#expect(result != nil)
		#expect(result?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello42")
	}

	@Test("exec captures multiline output")
	func execMultiline() throws {
		let result = ProcessExecution.exec(["/bin/sh", "-c", "echo line1; echo line2"])
		#expect(result != nil)
		let lines = try #require(result?.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n"))
		#expect(lines == ["line1", "line2"])
	}

	@Test("spawn creates a process with valid pid")
	func spawn() {
		let proc = ProcessExecution.spawn(["/bin/sleep", "0"])
		#expect(proc != nil)
		if let p = proc {
			#expect(p.pid > 0)
			close(p.stdin)
			close(p.stdout)
			close(p.stderr)
			var status: Int32 = 0
			waitpid(p.pid, &status, 0)
		}
	}

	@Test("spawn reads stdout from child process")
	func spawnAndRead() {
		let proc = ProcessExecution.spawn(["/bin/echo", "hello spawn"])
		#expect(proc != nil)
		if let p = proc {
			close(p.stdin)
			let output = ProcessExecution.exhaustFD(p.stdout)
			close(p.stderr)
			var status: Int32 = 0
			waitpid(p.pid, &status, 0)
			#expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello spawn")
		}
	}

	@Test("basicEnvironment includes standard variables")
	func basicEnvironment() {
		let env = ProcessExecution.basicEnvironment()
		#expect(env["HOME"] != nil)
		#expect(env["PATH"] != nil)
		#expect(env["LOGNAME"] != nil || env["USER"] != nil)
	}
}
