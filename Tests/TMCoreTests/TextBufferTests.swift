import Testing
@testable import TMCore

@Suite("TextBuffer — Piece Table")
struct TextBufferTests {
	// MARK: - Init & Basic Properties

	@Test func emptyBuffer() {
		let buf = TextBuffer()
		#expect(buf.size == 0)
		#expect(buf.isEmpty)
		#expect(buf.lines == 1)
		#expect(buf.string == "")
		#expect(buf.revision == 0)
	}

	@Test func initWithString() {
		let buf = TextBuffer("Hello, world!")
		#expect(buf.size == 13)
		#expect(!buf.isEmpty)
		#expect(buf.lines == 1)
		#expect(buf.string == "Hello, world!")
	}

	@Test func initWithMultilineString() {
		let buf = TextBuffer("line1\nline2\nline3")
		#expect(buf.size == 17)
		#expect(buf.lines == 3)
	}

	@Test func initWithTrailingNewline() {
		let buf = TextBuffer("line1\nline2\n")
		#expect(buf.lines == 3) // 2 newlines → 3 lines (last line is empty)
	}

	// MARK: - Subscript

	@Test func subscriptAccess() {
		let buf = TextBuffer("abc")
		#expect(buf[0] == UInt8(ascii: "a"))
		#expect(buf[1] == UInt8(ascii: "b"))
		#expect(buf[2] == UInt8(ascii: "c"))
	}

	// MARK: - Substring

	@Test func substringFullRange() {
		let buf = TextBuffer("Hello, world!")
		#expect(buf.substring(from: 0, to: 13) == "Hello, world!")
	}

	@Test func substringPartial() {
		let buf = TextBuffer("Hello, world!")
		#expect(buf.substring(from: 0, to: 5) == "Hello")
		#expect(buf.substring(from: 7, to: 12) == "world")
	}

	@Test func substringEmpty() {
		let buf = TextBuffer("Hello")
		#expect(buf.substring(from: 3, to: 3) == "")
	}

	// MARK: - Insert

	@Test func insertAtBeginning() {
		let buf = TextBuffer("world")
		buf.insert(at: 0, string: "Hello, ")
		#expect(buf.string == "Hello, world")
		#expect(buf.size == 12)
	}

	@Test func insertAtEnd() {
		let buf = TextBuffer("Hello")
		buf.insert(at: 5, string: ", world!")
		#expect(buf.string == "Hello, world!")
	}

	@Test func insertInMiddle() {
		let buf = TextBuffer("Helo")
		buf.insert(at: 2, string: "l")
		#expect(buf.string == "Hello")
	}

	@Test func insertIntoEmptyBuffer() {
		let buf = TextBuffer()
		buf.insert(at: 0, string: "abc")
		#expect(buf.string == "abc")
		#expect(buf.size == 3)
	}

	@Test func multipleInserts() {
		let buf = TextBuffer()
		buf.insert(at: 0, string: "C")
		buf.insert(at: 0, string: "A")
		buf.insert(at: 1, string: "B")
		#expect(buf.string == "ABC")
	}

	// MARK: - Erase

	@Test func eraseFromBeginning() {
		let buf = TextBuffer("Hello, world!")
		buf.erase(from: 0, to: 7)
		#expect(buf.string == "world!")
	}

	@Test func eraseFromEnd() {
		let buf = TextBuffer("Hello, world!")
		buf.erase(from: 5, to: 13)
		#expect(buf.string == "Hello")
	}

	@Test func eraseFromMiddle() {
		let buf = TextBuffer("Hello, world!")
		buf.erase(from: 5, to: 7)
		#expect(buf.string == "Helloworld!")
	}

	@Test func eraseAll() {
		let buf = TextBuffer("Hello")
		buf.erase(from: 0, to: 5)
		#expect(buf.string == "")
		#expect(buf.isEmpty)
		#expect(buf.lines == 1)
	}

	// MARK: - Replace

	@Test func replaceRange() {
		let buf = TextBuffer("Hello, world!")
		buf.replace(from: 7, to: 12, with: "Swift")
		#expect(buf.string == "Hello, Swift!")
	}

	@Test func replaceWithShorterText() {
		let buf = TextBuffer("Hello, world!")
		buf.replace(from: 0, to: 13, with: "Hi")
		#expect(buf.string == "Hi")
	}

	@Test func replaceWithLongerText() {
		let buf = TextBuffer("Hi")
		buf.replace(from: 0, to: 2, with: "Hello, world!")
		#expect(buf.string == "Hello, world!")
	}

	@Test func replaceEmpty() {
		// Replacing empty range = pure insert
		let buf = TextBuffer("abc")
		buf.replace(from: 1, to: 1, with: "X")
		#expect(buf.string == "aXbc")
	}

	// MARK: - Line Operations

	@Test func lineStartAndEnd() {
		let buf = TextBuffer("aaa\nbbb\nccc")
		// Line 0: "aaa"
		#expect(buf.lineStart(0) == 0)
		#expect(buf.lineEnd(0) == 3)
		// Line 1: "bbb"
		#expect(buf.lineStart(1) == 4)
		#expect(buf.lineEnd(1) == 7)
		// Line 2: "ccc"
		#expect(buf.lineStart(2) == 8)
		#expect(buf.lineEnd(2) == 11) // end of buffer
	}

	@Test func lineStartEmptyLastLine() {
		let buf = TextBuffer("abc\n")
		#expect(buf.lines == 2)
		#expect(buf.lineStart(0) == 0)
		#expect(buf.lineStart(1) == 4)
		#expect(buf.lineEnd(1) == 4) // empty last line
	}

	@Test func lineCountAfterInsert() {
		let buf = TextBuffer("abc")
		#expect(buf.lines == 1)
		buf.insert(at: 3, string: "\ndef")
		#expect(buf.lines == 2)
		buf.insert(at: buf.size, string: "\nghi")
		#expect(buf.lines == 3)
	}

	@Test func lineCountAfterErase() {
		let buf = TextBuffer("abc\ndef\nghi")
		#expect(buf.lines == 3)
		buf.erase(from: 3, to: 4) // erase first \n
		#expect(buf.lines == 2)
		#expect(buf.string == "abcdef\nghi")
	}

	// MARK: - Offset ↔ Position Conversion

	@Test func convertOffsetToPosition() {
		let buf = TextBuffer("abc\ndef\nghi")
		let p0 = buf.convert(offset: 0)
		#expect(p0.line == 0)
		#expect(p0.column == 0)

		let p3 = buf.convert(offset: 3) // at the \n
		#expect(p3.line == 0)
		#expect(p3.column == 3)

		let p4 = buf.convert(offset: 4) // start of "def"
		#expect(p4.line == 1)
		#expect(p4.column == 0)

		let p10 = buf.convert(offset: 10) // at "i" in "ghi"
		#expect(p10.line == 2)
		#expect(p10.column == 2)
	}

	@Test func convertPositionToOffset() {
		let buf = TextBuffer("abc\ndef\nghi")
		#expect(buf.convert(position: TextPosition(line: 0, column: 0, offset: 0)) == 0)
		#expect(buf.convert(position: TextPosition(line: 1, column: 0, offset: 0)) == 4)
		#expect(buf.convert(position: TextPosition(line: 1, column: 2, offset: 0)) == 6)
		#expect(buf.convert(position: TextPosition(line: 2, column: 3, offset: 0)) == 11) // end of buffer
	}

	@Test func convertBeyondEndClamps() {
		let buf = TextBuffer("abc")
		let p = buf.convert(offset: 100)
		#expect(p.line == 0)
		#expect(p.column == 3)
		#expect(p.offset == 3)
	}

	// MARK: - Revision

	@Test func revisionBumps() {
		let buf = TextBuffer("abc")
		#expect(buf.revision == 0)
		buf.bumpRevision()
		#expect(buf.revision == 1)
		buf.bumpRevision()
		#expect(buf.revision == 2)
	}

	@Test func setRevision() {
		let buf = TextBuffer("abc")
		buf.setRevision(42)
		#expect(buf.revision == 42)
	}

	// MARK: - Equality

	@Test func equalityIdenticalContent() {
		let a = TextBuffer("Hello")
		let b = TextBuffer("Hello")
		#expect(a == b)
	}

	@Test func equalityAfterEdits() {
		let a = TextBuffer("Hello")
		let b = TextBuffer("Helo")
		b.insert(at: 2, string: "l")
		#expect(a == b)
	}

	@Test func inequalityDifferentContent() {
		let a = TextBuffer("Hello")
		let b = TextBuffer("World")
		#expect(a != b)
	}

	// MARK: - Unicode

	@Test func unicodeContent() {
		let buf = TextBuffer("café ☕️")
		let content = buf.string
		#expect(content == "café ☕️")
	}

	@Test func insertUnicode() {
		let buf = TextBuffer("hello ")
		buf.insert(at: buf.size, string: "🌍")
		#expect(buf.string == "hello 🌍")
	}

	// MARK: - Stress / Multi-edit Sequences

	@Test func manySmallInserts() {
		let buf = TextBuffer()
		for i in 0 ..< 100 {
			buf.insert(at: buf.size, string: "\(i)\n")
		}
		#expect(buf.lines == 101)
		#expect(buf.substring(from: 0, to: 2) == "0\n")
	}

	@Test func interleavedInsertAndDelete() {
		let buf = TextBuffer("abcdef")
		buf.erase(from: 2, to: 4) // "abef"
		buf.insert(at: 2, string: "XY") // "abXYef"
		buf.erase(from: 0, to: 2) // "XYef"
		buf.insert(at: 4, string: "GH") // "XYefGH"
		#expect(buf.string == "XYefGH")
	}

	@Test func replaceEntireContent() {
		let buf = TextBuffer("old content")
		buf.replace(from: 0, to: buf.size, with: "new content")
		#expect(buf.string == "new content")
	}

	// MARK: - Description

	@Test func description() {
		let buf = TextBuffer("abc\ndef")
		let desc = buf.description
		#expect(desc.contains("7 bytes"))
		#expect(desc.contains("2 lines"))
	}
}
