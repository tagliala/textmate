import AppKit
import Testing
@testable import TMPreferences

@Suite("CommitWindowController — Status Colors")
struct CommitStatusColorsTests {
	// MARK: - Helper

	/// Compare two colors by converting to sRGB and checking components.
	private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
		guard let ac = a.usingColorSpace(.sRGB),
		      let bc = b.usingColorSpace(.sRGB)
		else { return false }
		return abs(ac.redComponent - bc.redComponent) < 0.02
			&& abs(ac.greenComponent - bc.greenComponent) < 0.02
			&& abs(ac.blueComponent - bc.blueComponent) < 0.02
	}

	@Test("modified/merged status returns orange-ish color")
	@MainActor func modifiedMergedColor() {
		let expected = NSColor(red: 0.92, green: 0.39, blue: 0.0, alpha: 1.0)
		for s in ["M", "G"] {
			let (fg, _) = CommitWindowController.statusColors(for: s)
			#expect(colorsMatch(fg, expected), "'\(s)' foreground should be orange")
		}
	}

	@Test("added status returns green color")
	@MainActor func addedColor() {
		let expected = NSColor(red: 0.0, green: 0.67, blue: 0.0, alpha: 1.0)
		let (fg, _) = CommitWindowController.statusColors(for: "A")
		#expect(colorsMatch(fg, expected))
	}

	@Test("deleted/replaced status returns red color")
	@MainActor func deletedReplacedColor() {
		for s in ["D", "R"] {
			let (fg, _) = CommitWindowController.statusColors(for: s)
			#expect(colorsMatch(fg, .red), "'\(s)' foreground should be red")
		}
	}

	@Test("conflicted/unversioned status returns teal color")
	@MainActor func conflictedUnversionedColor() {
		let expected = NSColor(red: 0.0, green: 0.50, blue: 0.50, alpha: 1.0)
		for s in ["C", "?"] {
			let (fg, _) = CommitWindowController.statusColors(for: s)
			#expect(colorsMatch(fg, expected), "'\(s)' foreground should be teal")
		}
	}

	@Test("external status returns white on black")
	@MainActor func externalColor() {
		let (fg, bg) = CommitWindowController.statusColors(for: "X")
		#expect(colorsMatch(fg, .white))
		#expect(colorsMatch(bg, .black))
	}

	@Test("ignored status returns purple color")
	@MainActor func ignoredColor() {
		let expected = NSColor(red: 0.50, green: 0.0, blue: 0.50, alpha: 1.0)
		let (fg, _) = CommitWindowController.statusColors(for: "I")
		#expect(colorsMatch(fg, expected))
	}

	@Test("unknown status returns labelColor")
	@MainActor func unknownColor() {
		let (fg, bg) = CommitWindowController.statusColors(for: "Z")
		#expect(fg == .labelColor)
		#expect(bg == .clear)
	}

	@Test("all known statuses return non-nil foreground")
	@MainActor func allStatusesHaveColors() {
		for status in ["M", "G", "A", "D", "R", "C", "?", "X", "I"] {
			let (fg, _) = CommitWindowController.statusColors(for: status)
			#expect(fg.alphaComponent > 0, "Foreground for '\(status)' should have alpha > 0")
		}
	}

	@Test("attributedStatus creates styled string")
	@MainActor func attributedStatusString() {
		let attr = CommitWindowController.attributedStatus("M")
		#expect(attr.string == " M ")
		let attrs = attr.attributes(at: 1, effectiveRange: nil)
		#expect(attrs[.foregroundColor] as? NSColor != nil)
		#expect(attrs[.backgroundColor] as? NSColor != nil)
		#expect(attrs[.font] as? NSFont != nil)
	}
}
