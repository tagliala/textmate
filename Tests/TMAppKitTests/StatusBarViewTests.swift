import AppKit
import Testing
@testable import TMAppKit

// MARK: - Selection String Formatting

@Suite("StatusBarView — Selection String Formatting")
@MainActor
struct SelectionStringFormattingTests {
	@Test func singleCursorPosition() {
		let bar = StatusBarView()
		bar.setSelectionString("5:12")
		#expect(bar.selectionStringValue == "5:12")
	}

	@Test func multiCursorSeparator() {
		let bar = StatusBarView()
		bar.setSelectionString("1:1&2:3")
		#expect(bar.selectionStringValue == "1:1, 2:3")
	}

	@Test func multiCursorMultiple() {
		let bar = StatusBarView()
		bar.setSelectionString("1:1&2:3&4:5")
		#expect(bar.selectionStringValue == "1:1, 2:3, 4:5")
	}

	@Test func selectionDimensions() {
		let bar = StatusBarView()
		bar.setSelectionString("3x10")
		#expect(bar.selectionStringValue == "3×10")
	}

	@Test func mixedMultiCursorAndDimensions() {
		let bar = StatusBarView()
		bar.setSelectionString("3x10&5:1")
		#expect(bar.selectionStringValue == "3×10, 5:1")
	}

	@Test func emptyStringFallback() {
		let bar = StatusBarView()
		bar.setSelectionString("")
		#expect(bar.selectionStringValue == "1:1")
	}

	@Test func lineColumnConvenience() {
		let bar = StatusBarView()
		bar.setLineColumn(line: 42, column: 7)
		#expect(bar.selectionStringValue == "42:7")
	}
}

// MARK: - Grammar Display

@Suite("StatusBarView — Grammar Display")
@MainActor
struct GrammarDisplayTests {
	@Test func defaultGrammar() {
		let bar = StatusBarView()
		// The initial title should be "Plain Text"
		#expect(bar.grammarTitle == "Plain Text")
	}

	@Test func setGrammar() {
		let bar = StatusBarView()
		bar.setGrammar("Ruby")
		#expect(bar.grammarTitle == "Ruby")
	}

	@Test func emptyGrammarFallback() {
		let bar = StatusBarView()
		bar.setGrammar("")
		#expect(bar.grammarTitle == "(no grammar)")
	}
}

// MARK: - Tab Settings

@Suite("StatusBarView — Tab Settings")
@MainActor
struct TabSettingsTests {
	@Test func softTabs() {
		let bar = StatusBarView()
		bar.setTabSettings(useSoftTabs: true, tabSize: 4)
		#expect(bar.tabSettingsTitle.contains("Soft Tabs"))
		#expect(bar.tabSettingsTitle.contains("4"))
	}

	@Test func hardTabs() {
		let bar = StatusBarView()
		bar.setTabSettings(useSoftTabs: false, tabSize: 8)
		#expect(bar.tabSettingsTitle.contains("Tab Size"))
		#expect(bar.tabSettingsTitle.contains("8"))
	}
}

// MARK: - Symbol Display

@Suite("StatusBarView — Symbol Display")
@MainActor
struct SymbolDisplayTests {
	@Test func defaultSymbolTitle() {
		let bar = StatusBarView()
		#expect(bar.symbolTitle == "Symbols")
	}

	@Test func setSymbolName() {
		let bar = StatusBarView()
		bar.setSymbolName("viewDidLoad")
		#expect(bar.symbolTitle == "viewDidLoad")
	}

	@Test func nilSymbolFallback() {
		let bar = StatusBarView()
		bar.setSymbolName(nil)
		#expect(bar.symbolTitle == "Symbols")
	}
}

// MARK: - Macro Recording

@Suite("StatusBarView — Macro Recording")
@MainActor
struct MacroRecordingTests {
	@Test func initialState() {
		let bar = StatusBarView()
		#expect(!bar.isRecordingMacro)
	}

	@Test func startRecording() {
		let bar = StatusBarView()
		bar.isRecordingMacro = true
		#expect(bar.isRecordingMacro)
	}

	@Test func stopRecording() {
		let bar = StatusBarView()
		bar.isRecordingMacro = true
		bar.isRecordingMacro = false
		#expect(!bar.isRecordingMacro)
	}
}

// MARK: - Delegate

@Suite("StatusBarView — Delegate Protocol")
@MainActor
struct DelegateTests {
	/// Mock delegate that records delegate calls.
	final class MockDelegate: StatusBarViewDelegate, @unchecked Sendable {
		var selectedTabSize: Int?
		var selectedSoftTabs: Bool?
		var macroToggled = false
		var grammarMenuShown = false
		var symbolMenuShown = false
		var bundleItemsMenuShown = false

		func statusBarView(_: StatusBarView, didSelectTabSize size: Int) {
			selectedTabSize = size
		}

		func statusBarView(_: StatusBarView, didSelectUseSoftTabs useSoftTabs: Bool) {
			selectedSoftTabs = useSoftTabs
		}

		func statusBarViewDidToggleMacroRecording(_: StatusBarView) {
			macroToggled = true
		}

		func statusBarViewWillShowGrammarMenu(_: StatusBarView, popup _: NSPopUpButton) {
			grammarMenuShown = true
		}

		func statusBarViewWillShowSymbolMenu(_: StatusBarView, popup _: NSPopUpButton) {
			symbolMenuShown = true
		}

		func statusBarViewWillShowBundleItemsMenu(_: StatusBarView, popup _: NSPopUpButton) {
			bundleItemsMenuShown = true
		}
	}

	@Test func delegateAssigned() {
		let bar = StatusBarView()
		let mock = MockDelegate()
		bar.delegate = mock
		#expect(bar.delegate !== nil)
	}

	@Test func defaultDelegateMethodsDoNotCrash() {
		// Ensure default no-op implementations work
		let bar = StatusBarView()
		let mock = MockDelegate()
		mock.statusBarView(bar, didSelectGrammar: "Swift")
		mock.statusBarView(bar, didSelectTabSettings: true, tabSize: 4)
		mock.statusBarView(bar, didSelectEncoding: "UTF-8")
	}
}

// MARK: - StatusBarView Height

@Suite("StatusBarView — Layout")
@MainActor
struct LayoutTests {
	@Test func defaultHeight() {
		let bar = StatusBarView()
		#expect(bar.statusBarHeight == 24)
	}

	@Test func isFlipped() {
		let bar = StatusBarView()
		#expect(bar.isFlipped)
	}
}
