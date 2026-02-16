import Testing
@testable import TMPreferences

@Suite("CommitActionCommand")
struct CommitActionCommandTests {
	// MARK: - Parsing

	@Test("parse valid revert command")
	func parseRevert() {
		let cmd = CommitActionCommand.parse("M,A,D:Revert,/usr/bin/svn,revert")
		#expect(cmd != nil)
		#expect(cmd?.name == "Revert")
		#expect(cmd?.command == ["/usr/bin/svn", "revert"])
		#expect(cmd?.targetStatuses == Set(["M", "A", "D"]))
	}

	@Test("parse command with single status")
	func parseSingleStatus() {
		let cmd = CommitActionCommand.parse("M:Diff,/usr/bin/svn,diff")
		#expect(cmd != nil)
		#expect(cmd?.targetStatuses == Set(["M"]))
		#expect(cmd?.name == "Diff")
		#expect(cmd?.command == ["/usr/bin/svn", "diff"])
	}

	@Test("parse command with single command component")
	func parseSingleComponent() {
		let cmd = CommitActionCommand.parse("A:Add,/usr/bin/git")
		#expect(cmd != nil)
		#expect(cmd?.name == "Add")
		#expect(cmd?.command == ["/usr/bin/git"])
	}

	@Test("parse returns nil for empty string")
	func parseEmpty() {
		let cmd = CommitActionCommand.parse("")
		#expect(cmd == nil)
	}

	@Test("parse returns nil for string without colon separator")
	func parseNoColon() {
		let cmd = CommitActionCommand.parse("M,A,D-Revert,/usr/bin/svn,revert")
		#expect(cmd == nil)
	}

	@Test("parse returns nil for string with only statuses")
	func parseStatusesOnly() {
		let cmd = CommitActionCommand.parse("M,A:")
		#expect(cmd == nil)
	}

	// MARK: - Properties

	@Test("command name is first after colon")
	func commandName() {
		let cmd = CommitActionCommand.parse("?:Add to VCS,/usr/bin/git,add")
		#expect(cmd?.name == "Add to VCS")
	}

	@Test("target statuses preserves all entries")
	func allStatuses() {
		let cmd = CommitActionCommand.parse("M,A,D,C,?:Action,/bin/cmd")
		#expect(cmd?.targetStatuses.count == 5)
		#expect(cmd?.targetStatuses.contains("M") == true)
		#expect(cmd?.targetStatuses.contains("?") == true)
		#expect(cmd?.targetStatuses.contains("C") == true)
	}
}
