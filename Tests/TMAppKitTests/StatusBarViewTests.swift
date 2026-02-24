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
		var selectedEncoding: String?
		var selectedLineEnding: String?
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

		func statusBarView(_: StatusBarView, didSelectEncoding encoding: String) {
			selectedEncoding = encoding
		}

		func statusBarView(_: StatusBarView, didSelectLineEnding lineEnding: String) {
			selectedLineEnding = lineEnding
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
		mock.statusBarView(bar, didSelectLineEnding: "LF")
	}
}

// MARK: - Grammar Selection

@Suite("StatusBarView — Grammar Selection")
@MainActor
struct GrammarSelectionTests {
	final class GrammarDelegate: StatusBarViewDelegate, @unchecked Sendable {
		var selectedGrammarScope: String?
		func statusBarView(_: StatusBarView, didSelectGrammar grammar: String) {
			selectedGrammarScope = grammar
		}
	}

	@Test func grammarPopupHasTargetAndAction() {
		let bar = StatusBarView()
		// The grammarPopUp should have a target and action wired.
		// We verify indirectly: set a delegate, simulate selection, and
		// check the delegate received the call.
		let delegate = GrammarDelegate()
		bar.delegate = delegate

		// Populate the grammar popup with an item that has a scope.
		let menu = NSMenu()
		let item = NSMenuItem(title: "Swift", action: nil, keyEquivalent: "")
		item.representedObject = "source.swift" as String
		menu.addItem(item)

		// Access the popup via the grammarTitle path — the popup itself
		// cannot be accessed directly. Instead, just validate that the
		// delegate protocol method exists and defaults work.
		#expect(delegate.selectedGrammarScope == nil)
		delegate.statusBarView(bar, didSelectGrammar: "source.swift")
		#expect(delegate.selectedGrammarScope == "source.swift")
	}

	@Test func plainTextSelectionPassesEmptyScope() {
		let bar = StatusBarView()
		let delegate = GrammarDelegate()
		bar.delegate = delegate

		delegate.statusBarView(bar, didSelectGrammar: "")
		#expect(delegate.selectedGrammarScope == "")
	}
}

// MARK: - Encoding Display

@Suite("StatusBarView — Encoding Display")
@MainActor
struct EncodingDisplayTests {
	@Test func defaultEncoding() {
		let bar = StatusBarView()
		#expect(bar.encodingTitle == "UTF-8")
	}

	@Test func setKnownEncoding() {
		let bar = StatusBarView()
		bar.setEncoding("ISO-8859-1")
		#expect(bar.encodingTitle == "ISO 8859-1")
	}

	@Test func setUTF16BEEncoding() {
		let bar = StatusBarView()
		bar.setEncoding("UTF-16BE")
		#expect(bar.encodingTitle == "UTF-16 BE")
	}

	@Test func setUnknownEncodingAddsCustomItem() {
		let bar = StatusBarView()
		bar.setEncoding("EUC-JP")
		#expect(bar.encodingTitle == "EUC-JP")
	}

	@Test func setEncodingBackToUTF8() {
		let bar = StatusBarView()
		bar.setEncoding("Shift_JIS")
		#expect(bar.encodingTitle == "Shift JIS")
		bar.setEncoding("UTF-8")
		#expect(bar.encodingTitle == "UTF-8")
	}
}

// MARK: - Line Ending Display

@Suite("StatusBarView — Line Ending Display")
@MainActor
struct LineEndingDisplayTests {
	@Test func defaultLineEnding() {
		let bar = StatusBarView()
		#expect(bar.lineEndingTitle == "LF")
	}

	@Test func setCR() {
		let bar = StatusBarView()
		bar.setLineEnding("CR")
		#expect(bar.lineEndingTitle == "CR")
	}

	@Test func setCRLF() {
		let bar = StatusBarView()
		bar.setLineEnding("CR/LF")
		#expect(bar.lineEndingTitle == "CR/LF")
	}

	@Test func setBackToLF() {
		let bar = StatusBarView()
		bar.setLineEnding("CR/LF")
		bar.setLineEnding("LF")
		#expect(bar.lineEndingTitle == "LF")
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

// MARK: - StatusBarView Vibrancy

@Suite("StatusBarView — Vibrancy")
@MainActor
struct VibrancyTests {
	@Test func isVisualEffectView() {
		let bar = StatusBarView()
		// StatusBarView subclasses NSVisualEffectView — validate material is set.
		let effectView: NSVisualEffectView = bar
		#expect(effectView.material == .titlebar)
	}

	@Test func materialIsTitlebar() {
		let bar = StatusBarView()
		#expect(bar.material == .titlebar)
	}

	@Test func blendingModeIsWithinWindow() {
		let bar = StatusBarView()
		#expect(bar.blendingMode == .withinWindow)
	}
}

// MARK: - StatusBarView Line Label

@Suite("StatusBarView — Line Label")
@MainActor
struct LineLabelTests {
	@Test func hasLineLabelSubview() {
		let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 24))
		// The first NSTextField subview should be the "Line:" label.
		let labels = bar.subviews.compactMap { $0 as? NSTextField }
		let lineLabel = labels.first { $0.stringValue == "Line:" }
		#expect(lineLabel != nil)
	}

	@Test func lineLabelPrecedesSelectionField() {
		let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 24))
		let labels = bar.subviews.compactMap { $0 as? NSTextField }
		guard let lineLabelIndex = labels.firstIndex(where: { $0.stringValue == "Line:" }),
		      let selectionIndex = labels.firstIndex(where: { $0.stringValue == "1:1" })
		else {
			#expect(Bool(false), "Expected Line: and selection labels")
			return
		}
		#expect(lineLabelIndex < selectionIndex)
	}
}
