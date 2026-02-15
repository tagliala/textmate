import Foundation
import Testing
@testable import TMBundleRuntime
@testable import TMBundleUI

// MARK: - Bundle Editor Entry Tests

@Suite("BundleEditorEntry")
struct BundleEditorEntryTests {
	@Test("Root entry has stable ID")
	func rootID() {
		let root = BundleEditorEntry.root
		#expect(root.id == "root")
		#expect(root.name == "Bundles")
	}

	@Test("Bundle entry ID contains UUID")
	func bundleEntryID() {
		let entry = BundleEditorEntry.bundle(uuid: "b1", name: "TestBundle")
		#expect(entry.id == "bundle-b1")
		#expect(entry.name == "TestBundle")
	}

	@Test("Group entry ID contains bundle UUID and kind")
	func groupEntryID() {
		let entry = BundleEditorEntry.group(
			bundleUUID: "b1",
			kind: .command,
			title: "Commands",
		)
		#expect(entry.id.contains("group-b1-"))
		#expect(entry.name == "Commands")
	}

	@Test("Item entry ID contains UUID")
	func itemEntryID() {
		let entry = BundleEditorEntry.item(
			uuid: "i1",
			name: "Run",
			kind: .command,
		)
		#expect(entry.id == "item-i1")
		#expect(entry.name == "Run")
	}

	@Test("Separator entry name is dash")
	func separatorName() {
		let entry = BundleEditorEntry.separator
		#expect(entry.name == "—")
	}

	@Test("Equality based on ID")
	func equality() {
		let a = BundleEditorEntry.bundle(uuid: "b1", name: "A")
		let b = BundleEditorEntry.bundle(uuid: "b1", name: "B")
		let c = BundleEditorEntry.bundle(uuid: "b2", name: "A")
		#expect(a == b) // Same UUID → equal
		#expect(a != c)
	}
}

// MARK: - Bundle Editor Tree Builder Tests

@Suite("BundleEditorTreeBuilder")
struct BundleEditorTreeBuilderTests {
	@Test("Root children are all enabled bundles")
	func rootChildren() {
		let index = BundleIndex()
		let b1 = BundleDescriptor(uuid: "b1", name: "Alpha")
		let b2 = BundleDescriptor(uuid: "b2", name: "Beta")
		index.setIndex(items: [], bundles: [b1, b2])

		let builder = BundleEditorTreeBuilder(bundleIndex: index)
		let children = builder.children(of: .root)
		#expect(children.count == 2)
		// Should be sorted alphabetically.
		#expect(children[0].name == "Alpha")
		#expect(children[1].name == "Beta")
	}

	@Test("Bundle children are groups for present kinds")
	func bundleChildren() {
		let index = BundleIndex()
		let cmd = BundleItem(
			uuid: "c1",
			name: "Cmd",
			kind: .command,
			bundleUUID: "b1",
		)
		let snip = BundleItem(
			uuid: "s1",
			name: "Snip",
			kind: .snippet,
			bundleUUID: "b1",
		)
		index.setIndex(
			items: [cmd, snip],
			bundles: [BundleDescriptor(uuid: "b1", name: "Bundle")],
		)

		let builder = BundleEditorTreeBuilder(bundleIndex: index)
		let groups = builder.children(of: .bundle(uuid: "b1", name: "Bundle"))
		#expect(groups.count == 2) // Commands + Snippets
	}

	@Test("Group children are items of matching kind")
	func groupChildren() {
		let index = BundleIndex()
		let cmd = BundleItem(
			uuid: "c1",
			name: "Run",
			kind: .command,
			bundleUUID: "b1",
		)
		let snip = BundleItem(
			uuid: "s1",
			name: "Snip",
			kind: .snippet,
			bundleUUID: "b1",
		)
		index.setIndex(items: [cmd, snip], bundles: [])

		let builder = BundleEditorTreeBuilder(bundleIndex: index)
		let items = builder.children(of: .group(
			bundleUUID: "b1",
			kind: .command,
			title: "Commands",
		))
		#expect(items.count == 1)
		#expect(items[0].name == "Run")
	}

	@Test("Item and separator have no children")
	func leafNodes() {
		let index = BundleIndex()
		let builder = BundleEditorTreeBuilder(bundleIndex: index)
		#expect(
			builder.children(of: .item(uuid: "x", name: "X", kind: .command))
				.isEmpty,
		)
		#expect(builder.children(of: .separator).isEmpty)
	}

	@Test("hasChildren reflects content")
	func hasChildren() {
		let index = BundleIndex()
		let cmd = BundleItem(
			uuid: "c1",
			name: "Cmd",
			kind: .command,
			bundleUUID: "b1",
		)
		let b1 = BundleDescriptor(uuid: "b1", name: "Bundle")
		index.setIndex(items: [cmd], bundles: [b1])

		let builder = BundleEditorTreeBuilder(bundleIndex: index)
		#expect(builder.hasChildren(.root))
		#expect(builder.hasChildren(.bundle(uuid: "b1", name: "Bundle")))
		#expect(!builder.hasChildren(.item(uuid: "c1", name: "Cmd", kind: .command)))
		#expect(!builder.hasChildren(.separator))
	}
}

// MARK: - Bundle Editor Change Tracker Tests

@Suite("BundleEditorChangeTracker")
@MainActor
struct BundleEditorChangeTrackerTests {
	@Test("Initially empty")
	func initiallyEmpty() {
		let tracker = BundleEditorChangeTracker()
		#expect(!tracker.hasChanges)
		#expect(tracker.changeCount == 0)
		#expect(tracker.modifiedItemUUIDs.isEmpty)
	}

	@Test("Record and retrieve change")
	func recordAndRetrieve() {
		let tracker = BundleEditorChangeTracker()
		tracker.recordChange(
			itemUUID: "item-1",
			plist: ["name": "Modified", "command": "echo"],
		)
		#expect(tracker.hasChanges)
		#expect(tracker.changeCount == 1)
		#expect(tracker.modifiedItemUUIDs == ["item-1"])

		let plist = tracker.modifiedPlist(forItem: "item-1")
		#expect(plist?["name"] as? String == "Modified")
	}

	@Test("Unmodified item returns nil")
	func unmodifiedReturnsNil() {
		let tracker = BundleEditorChangeTracker()
		#expect(tracker.modifiedPlist(forItem: "nonexistent") == nil)
	}

	@Test("Clear single change")
	func clearSingle() {
		let tracker = BundleEditorChangeTracker()
		tracker.recordChange(itemUUID: "a", plist: [:])
		tracker.recordChange(itemUUID: "b", plist: [:])
		#expect(tracker.changeCount == 2)

		tracker.clearChange(forItem: "a")
		#expect(tracker.changeCount == 1)
		#expect(tracker.modifiedPlist(forItem: "a") == nil)
	}

	@Test("Clear all changes")
	func clearAll() {
		let tracker = BundleEditorChangeTracker()
		tracker.recordChange(itemUUID: "a", plist: [:])
		tracker.recordChange(itemUUID: "b", plist: [:])
		tracker.clearAll()
		#expect(!tracker.hasChanges)
		#expect(tracker.changeCount == 0)
	}

	@Test("Overwrites change for same UUID")
	func overwriteChange() {
		let tracker = BundleEditorChangeTracker()
		tracker.recordChange(itemUUID: "a", plist: ["v": 1])
		tracker.recordChange(itemUUID: "a", plist: ["v": 2])
		#expect(tracker.changeCount == 1)
		#expect(tracker.modifiedPlist(forItem: "a")?["v"] as? Int == 2)
	}
}

// MARK: - Bundle Item Properties Tests

@Suite("BundleItemProperties")
struct BundleItemPropertiesTests {
	@Test("Default initializer")
	func defaults() {
		let props = BundleItemProperties()
		#expect(props.name == "")
		#expect(props.scopeSelector == "")
		#expect(props.keyEquivalent == "")
		#expect(props.tabTrigger == "")
		#expect(props.semanticClass == "")
		#expect(props.contentKey == "command")
		#expect(props.editorGrammar == "source.shell")
	}

	@Test("Custom initializer")
	func custom() {
		let props = BundleItemProperties(
			name: "Run",
			scopeSelector: "source.ruby",
			keyEquivalent: "@r",
			tabTrigger: "run",
			contentKey: "snippet",
			editorGrammar: "text.tm-snippet",
		)
		#expect(props.name == "Run")
		#expect(props.scopeSelector == "source.ruby")
	}

	@Test("Init from BundleItem")
	func fromBundleItem() {
		let item = BundleItem(
			uuid: "i1",
			name: "Test",
			kind: .command,
			bundleUUID: "b1",
			tabTrigger: "hello",
			keyEquivalent: "@h",
		)
		let props = BundleItemProperties(item: item)
		#expect(props.name == "Test")
		#expect(props.uuid == "i1")
		#expect(props.tabTrigger == "hello")
		#expect(props.keyEquivalent == "@h")
		#expect(props.contentKey == "command")
		#expect(props.editorGrammar == "source.shell")
	}

	@Test("Content info for each kind")
	func contentInfo() {
		let (cmdKey, cmdGrammar) = BundleItemProperties.contentInfo(for: .command)
		#expect(cmdKey == "command")
		#expect(cmdGrammar == "source.shell")

		let (snipKey, snipGrammar) = BundleItemProperties.contentInfo(for: .snippet)
		#expect(snipKey == "content")
		#expect(snipGrammar == "text.tm-snippet")

		let (grammarKey, grammarGrammar) = BundleItemProperties.contentInfo(for: .grammar)
		#expect(grammarKey == "patterns")
		#expect(grammarGrammar == "source.json.tm-grammar")

		let (themeKey, themeGrammar) = BundleItemProperties.contentInfo(for: .theme)
		#expect(themeKey == "settings")
		#expect(themeGrammar == "source.json.tm-theme")

		let (dragKey, dragGrammar) = BundleItemProperties.contentInfo(for: .dragCommand)
		#expect(dragKey == "command")
		#expect(dragGrammar == "source.shell")
	}

	@Test("Equality works")
	func equality() {
		let a = BundleItemProperties(name: "A", scopeSelector: "source.c")
		let b = BundleItemProperties(name: "A", scopeSelector: "source.c")
		let c = BundleItemProperties(name: "B", scopeSelector: "source.c")
		#expect(a == b)
		#expect(a != c)
	}
}

// MARK: - Key Equivalent Parsing Tests

#if canImport(AppKit)
import AppKit

@Suite("KeyEquivalentParsing")
@MainActor
struct KeyEquivalentParsingTests {
	@Test("Parse command key")
	func parseCommand() {
		let index = BundleIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let (key, mods) = builder.parseKeyEquivalent("@r")
		#expect(key == "r")
		#expect(mods.contains(.command))
		#expect(!mods.contains(.shift))
	}

	@Test("Parse multiple modifiers")
	func parseMultiple() {
		let index = BundleIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let (key, mods) = builder.parseKeyEquivalent("^~$@f")
		#expect(key == "f")
		#expect(mods.contains(.control))
		#expect(mods.contains(.option))
		#expect(mods.contains(.shift))
		#expect(mods.contains(.command))
	}

	@Test("Parse no modifiers")
	func parseNoModifiers() {
		let index = BundleIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let (key, mods) = builder.parseKeyEquivalent("a")
		#expect(key == "a")
		#expect(mods.isEmpty)
	}

	@Test("Parse empty string")
	func parseEmpty() {
		let index = BundleIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let (key, mods) = builder.parseKeyEquivalent("")
		#expect(key == "")
		#expect(mods.isEmpty)
	}

	@Test("Parse shift only")
	func parseShift() {
		let index = BundleIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let (key, mods) = builder.parseKeyEquivalent("$a")
		#expect(key == "a")
		#expect(mods.contains(.shift))
		#expect(!mods.contains(.command))
	}
}
#endif
