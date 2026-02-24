import AppKit
import Testing
@testable import TMEditorUI

@Suite("LayoutLine")
struct LayoutLineTests {
	// MARK: - StyleRun

	@Test("StyleRun properties")
	func styleRunProperties() {
		let run = StyleRun(
			start: 5,
			length: 10,
			foreground: .red,
			background: .blue,
			isBold: true,
			isItalic: false,
			isUnderline: true,
			isStrikethrough: false,
		)

		#expect(run.start == 5)
		#expect(run.length == 10)
		#expect(run.foreground == .red)
		#expect(run.background == .blue)
		#expect(run.isBold == true)
		#expect(run.isItalic == false)
		#expect(run.isUnderline == true)
		#expect(run.isStrikethrough == false)
	}

	@Test("StyleRun default values")
	func styleRunDefaults() {
		let run = StyleRun(
			start: 0,
			length: 5,
			foreground: .white,
		)

		#expect(run.background == nil)
		#expect(run.isBold == false)
		#expect(run.isItalic == false)
		#expect(run.isUnderline == false)
		#expect(run.isStrikethrough == false)
	}

	// MARK: - LayoutLine Creation

	@Test("LayoutLine stores line index and text")
	@MainActor
	func layoutLineProperties() {
		let manager = EditorLayoutManager()
		manager.setText("Hello, world!")
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 500))

		#expect(lines.count == 1)
		#expect(lines[0].lineIndex == 0)
		#expect(lines[0].text == "Hello, world!")
	}

	@Test("LayoutLine offset for index returns positive value for non-zero index")
	@MainActor
	func offsetForIndex() {
		let manager = EditorLayoutManager()
		manager.setText("ABCDEF")
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 500))

		guard let line = lines.first else {
			Issue.record("No lines laid out")
			return
		}

		let offset0 = line.offset(forIndex: 0)
		let offset3 = line.offset(forIndex: 3)
		#expect(offset0 == 0 || offset0 >= 0)
		#expect(offset3 > offset0)
	}

	@Test("LayoutLine index for offset round-trips")
	@MainActor
	func indexForOffsetRoundTrip() {
		let manager = EditorLayoutManager()
		manager.setText("Hello, world!")
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 500))

		guard let line = lines.first else {
			Issue.record("No lines laid out")
			return
		}

		// Get the offset for character 5, then map back
		let xOffset = line.offset(forIndex: 5)
		let roundTripped = line.index(forOffset: xOffset)
		#expect(roundTripped == 5)
	}

	// MARK: - Tab and Space Tracking

	@Test("LayoutLine tracks tab locations")
	@MainActor
	func tabLocations() {
		let manager = EditorLayoutManager()
		manager.setText("\tHello\tWorld")
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 800, height: 500))

		guard let line = lines.first else {
			Issue.record("No lines laid out")
			return
		}

		#expect(line.tabLocations.contains(0))
		#expect(line.tabLocations.contains(6))
	}

	@Test("LayoutLine tracks space locations")
	@MainActor
	func spaceLocations() {
		let manager = EditorLayoutManager()
		manager.setText("a b c")
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 800, height: 500))

		guard let line = lines.first else {
			Issue.record("No lines laid out")
			return
		}

		#expect(line.spaceLocations.contains(1))
		#expect(line.spaceLocations.contains(3))
	}
}
