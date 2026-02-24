#if canImport(AppKit)
import AppKit
import TMBundleRuntime

// MARK: - Bundle Editor Entry

/// A node in the bundle editor's sidebar tree.
public enum BundleEditorEntry: Identifiable, Equatable {
	/// Root node listing all bundles.
	case root
	/// A single bundle.
	case bundle(uuid: String, name: String)
	/// A group within a bundle (e.g. "Commands", "Snippets").
	case group(bundleUUID: String, kind: BundleItemKind, title: String)
	/// A single bundle item.
	case item(uuid: String, name: String, kind: BundleItemKind)
	/// A separator.
	case separator

	public var id: String {
		switch self {
		case .root: "root"
		case let .bundle(uuid, _): "bundle-\(uuid)"
		case let .group(bundleUUID, kind, _): "group-\(bundleUUID)-\(kind.rawValue)"
		case let .item(uuid, _, _): "item-\(uuid)"
		case .separator: "separator-\(UUID().uuidString)"
		}
	}

	public static func == (lhs: BundleEditorEntry, rhs: BundleEditorEntry) -> Bool {
		lhs.id == rhs.id
	}

	/// The display name for this entry.
	public var name: String {
		switch self {
		case .root: "Bundles"
		case let .bundle(_, name): name
		case let .group(_, _, title): title
		case let .item(_, name, _): name
		case .separator: "—"
		}
	}
}

// MARK: - Bundle Editor Tree Builder

/// Builds the sidebar tree structure for the bundle editor.
public struct BundleEditorTreeBuilder {
	private let bundleIndex: BundleIndex

	public init(bundleIndex: BundleIndex) {
		self.bundleIndex = bundleIndex
	}

	/// Returns children of the given entry.
	public func children(of entry: BundleEditorEntry) -> [BundleEditorEntry] {
		switch entry {
		case .root:
			bundleIndex.allBundles
				.filter(\.isEnabled)
				.sorted {
					$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
				}
				.map { .bundle(uuid: $0.uuid, name: $0.name) }

		case let .bundle(uuid, _):
			groupsForBundle(uuid: uuid)

		case let .group(bundleUUID, kind, _):
			bundleIndex.items(inBundle: bundleUUID)
				.filter { $0.kind.intersection(kind) != [] && !$0.isDisabled }
				.sorted {
					$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
				}
				.map { .item(uuid: $0.uuid, name: $0.name, kind: $0.kind) }

		case .item, .separator:
			[]
		}
	}

	/// Returns whether an entry has children.
	public func hasChildren(_ entry: BundleEditorEntry) -> Bool {
		switch entry {
		case .root: !bundleIndex.allBundles.isEmpty
		case let .bundle(uuid, _): !bundleIndex.items(inBundle: uuid).isEmpty
		case let .group(bundleUUID, kind, _):
			bundleIndex.items(inBundle: bundleUUID)
				.contains { $0.kind.intersection(kind) != [] }
		case .item, .separator: false
		}
	}

	/// Standard groups for a bundle.
	private func groupsForBundle(uuid: String) -> [BundleEditorEntry] {
		let items = bundleIndex.items(inBundle: uuid)
		var groups: [BundleEditorEntry] = []

		let groupDefinitions: [(BundleItemKind, String)] = [
			(.command, "Commands"),
			(.dragCommand, "Drag Commands"),
			(.grammar, "Language Grammars"),
			(.macro, "Macros"),
			(.settings, "Settings"),
			(.snippet, "Snippets"),
			(.theme, "Themes"),
		]

		for (kind, title) in groupDefinitions {
			if items.contains(where: { $0.kind.intersection(kind) != [] }) {
				groups.append(.group(bundleUUID: uuid, kind: kind, title: title))
			}
		}

		return groups
	}
}

// MARK: - Unsaved Changes Tracking

/// Tracks modifications to bundle items that haven't been saved yet.
@MainActor
public final class BundleEditorChangeTracker {
	/// Modified plists, keyed by item UUID.
	private var changes: [String: [String: Any]] = [:]

	public init() {}

	/// Records a modification to a bundle item.
	public func recordChange(itemUUID: String, plist: [String: Any]) {
		changes[itemUUID] = plist
	}

	/// Returns the modified plist for an item, or `nil` if unmodified.
	public func modifiedPlist(forItem uuid: String) -> [String: Any]? {
		changes[uuid]
	}

	/// Whether there are any unsaved changes.
	public var hasChanges: Bool {
		!changes.isEmpty
	}

	/// The UUIDs of all modified items.
	public var modifiedItemUUIDs: [String] {
		Array(changes.keys)
	}

	/// Clears the change for a specific item (after saving).
	public func clearChange(forItem uuid: String) {
		changes.removeValue(forKey: uuid)
	}

	/// Clears all changes.
	public func clearAll() {
		changes.removeAll()
	}

	/// Total number of unsaved changes.
	public var changeCount: Int {
		changes.count
	}
}

// MARK: - Bundle Item Properties

/// The editable properties of a bundle item, shown in the properties panel.
public struct BundleItemProperties: Sendable, Equatable {
	public var name: String
	public var scopeSelector: String
	public var keyEquivalent: String
	public var tabTrigger: String
	public var semanticClass: String
	public var uuid: String

	/// The main content key in the plist (varies by item type).
	public let contentKey: String

	/// The grammar scope for syntax-highlighting the content editor.
	public let editorGrammar: String

	public init(
		name: String = "",
		scopeSelector: String = "",
		keyEquivalent: String = "",
		tabTrigger: String = "",
		semanticClass: String = "",
		uuid: String = "",
		contentKey: String = "command",
		editorGrammar: String = "source.shell",
	) {
		self.name = name
		self.scopeSelector = scopeSelector
		self.keyEquivalent = keyEquivalent
		self.tabTrigger = tabTrigger
		self.semanticClass = semanticClass
		self.uuid = uuid
		self.contentKey = contentKey
		self.editorGrammar = editorGrammar
	}

	/// Creates properties from a `BundleItem`.
	public init(item: BundleItem) {
		name = item.name
		scopeSelector = item.scopeSelector
		keyEquivalent = item.keyEquivalent ?? ""
		tabTrigger = item.tabTrigger ?? ""
		semanticClass = item.semanticClass ?? ""
		uuid = item.uuid
		(contentKey, editorGrammar) = Self.contentInfo(for: item.kind)
	}

	/// Maps item kind to content plist key and editor grammar.
	static func contentInfo(for kind: BundleItemKind) -> (
		contentKey: String,
		editorGrammar: String,
	) {
		if kind.contains(.command) {
			("command", "source.shell")
		} else if kind.contains(.snippet) {
			("content", "text.tm-snippet")
		} else if kind.contains(.grammar) {
			("patterns", "source.json.tm-grammar")
		} else if kind.contains(.macro) {
			("commands", "source.json")
		} else if kind.contains(.settings) {
			("settings", "source.json")
		} else if kind.contains(.theme) {
			("settings", "source.json.tm-theme")
		} else if kind.contains(.dragCommand) {
			("command", "source.shell")
		} else {
			("content", "text.plain")
		}
	}
}

// MARK: - Bundle Editor Controller

/// Window controller for the bundle editor — displays and edits bundle items.
///
/// Layout mirrors the C++ BundleEditor:
/// - Left sidebar: NSOutlineView with bundle hierarchy
/// - Right top: Content editor (text area for command/snippet body)
/// - Right bottom: Properties panel (name, scope, key equivalent, tab trigger)
@MainActor
public final class BundleEditorController: NSWindowController {
	/// The bundle index.
	public let bundleIndex: BundleIndex

	/// The tree builder.
	public let treeBuilder: BundleEditorTreeBuilder

	/// Change tracker for unsaved modifications.
	public let changeTracker = BundleEditorChangeTracker()

	/// The currently selected item.
	public private(set) var selectedItem: BundleItem?

	/// Current properties being edited.
	public private(set) var currentProperties: BundleItemProperties?

	/// The sidebar outline view.
	private let outlineView = NSOutlineView()

	/// The content text view.
	private let contentView = NSTextView()

	/// Properties fields.
	private let nameField = NSTextField()
	private let scopeField = NSTextField()
	private let keyEquivField = NSTextField()
	private let tabTriggerField = NSTextField()

	public init(bundleIndex: BundleIndex) {
		self.bundleIndex = bundleIndex
		treeBuilder = BundleEditorTreeBuilder(bundleIndex: bundleIndex)

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false,
		)
		window.title = "Bundle Editor"
		window.center()

		super.init(window: window)
		setupUI()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not implemented")
	}

	// MARK: - UI Setup

	private func setupUI() {
		guard let contentView = window?.contentView else { return }

		let splitView = NSSplitView()
		splitView.isVertical = true
		splitView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(splitView)

		// Sidebar.
		let sidebarScroll = NSScrollView()
		sidebarScroll.documentView = outlineView
		sidebarScroll.hasVerticalScroller = true

		let nameColumn = NSTableColumn(identifier: .init("name"))
		nameColumn.title = "Bundles"
		outlineView.addTableColumn(nameColumn)
		outlineView.outlineTableColumn = nameColumn
		outlineView.headerView = nil
		outlineView.dataSource = self
		outlineView.delegate = self

		splitView.addSubview(sidebarScroll)

		// Right side: content + properties.
		let rightSplit = NSSplitView()
		rightSplit.isVertical = false

		let contentScroll = NSScrollView()
		self.contentView.isEditable = true
		self.contentView.isRichText = false
		self.contentView.font = NSFont.monospacedSystemFont(
			ofSize: 12,
			weight: .regular,
		)
		contentScroll.documentView = self.contentView
		contentScroll.hasVerticalScroller = true
		rightSplit.addSubview(contentScroll)

		// Properties panel.
		let propertiesView = createPropertiesPanel()
		rightSplit.addSubview(propertiesView)

		splitView.addSubview(rightSplit)

		NSLayoutConstraint.activate([
			splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
			splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])
	}

	private func createPropertiesPanel() -> NSView {
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false

		let labels = ["Name:", "Scope:", "Key Equiv:", "Tab Trigger:"]
		let fields = [nameField, scopeField, keyEquivField, tabTriggerField]

		var previousField: NSTextField?
		for (index, (label, field)) in zip(labels, fields).enumerated() {
			let labelView = NSTextField(labelWithString: label)
			labelView.translatesAutoresizingMaskIntoConstraints = false
			field.translatesAutoresizingMaskIntoConstraints = false
			field.isEditable = true

			container.addSubview(labelView)
			container.addSubview(field)

			let topAnchor = previousField?.bottomAnchor ?? container.topAnchor
			let topOffset: CGFloat = index == 0 ? 8 : 4

			NSLayoutConstraint.activate([
				labelView.leadingAnchor.constraint(
					equalTo: container.leadingAnchor,
					constant: 8,
				),
				labelView.topAnchor.constraint(equalTo: topAnchor, constant: topOffset),
				labelView.widthAnchor.constraint(equalToConstant: 80),

				field.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 4),
				field.trailingAnchor.constraint(
					equalTo: container.trailingAnchor,
					constant: -8,
				),
				field.centerYAnchor.constraint(equalTo: labelView.centerYAnchor),
			])

			previousField = field
		}

		return container
	}

	// MARK: - Selection

	/// Selects a bundle item by UUID and loads it into the editor.
	public func selectItem(uuid: String) {
		guard let item = bundleIndex.lookup(uuid: uuid) else { return }
		selectedItem = item
		currentProperties = BundleItemProperties(item: item)

		// Load content from plist.
		if let plist = item.plist,
		   let properties = currentProperties
		{
			let content = plist[properties.contentKey] as? String ?? ""
			contentView.string = content
		}

		// Update properties fields.
		if let props = currentProperties {
			nameField.stringValue = props.name
			scopeField.stringValue = props.scopeSelector
			keyEquivField.stringValue = props.keyEquivalent
			tabTriggerField.stringValue = props.tabTrigger
		}
	}

	// MARK: - Save

	/// Saves all unsaved changes.
	public func saveAll() {
		// Commit current editing state.
		commitCurrentEditing()

		for uuid in changeTracker.modifiedItemUUIDs {
			guard let plist = changeTracker.modifiedPlist(forItem: uuid),
			      let item = bundleIndex.lookup(uuid: uuid)
			else { continue }

			// Write plist back to the first path.
			if let path = item.paths.first {
				let data = try? PropertyListSerialization.data(
					fromPropertyList: plist,
					format: .xml,
					options: 0,
				)
				if let data {
					try? data.write(to: URL(fileURLWithPath: path))
				}
			}

			changeTracker.clearChange(forItem: uuid)
		}
	}

	/// Commits the current editor state to the change tracker.
	private func commitCurrentEditing() {
		guard let item = selectedItem,
		      let props = currentProperties
		else { return }
		var plist = item.plist ?? [:]

		plist["name"] = nameField.stringValue
		plist["scope"] = scopeField.stringValue
		plist["keyEquivalent"] = keyEquivField.stringValue
		plist["tabTrigger"] = tabTriggerField.stringValue
		plist[props.contentKey] = contentView.string

		changeTracker.recordChange(itemUUID: item.uuid, plist: plist)
	}

	// MARK: - Item Creation

	/// Creates a new bundle item of the given kind in the specified bundle.
	public func createItem(
		kind: BundleItemKind,
		inBundle bundleUUID: String,
		name: String = "Untitled",
	) -> BundleItem {
		let uuid = UUID().uuidString
		let (contentKey, _) = BundleItemProperties.contentInfo(for: kind)

		let plist: [String: Any] = [
			"uuid": uuid,
			"name": name,
			contentKey: "",
		]

		let item = BundleItem(
			uuid: uuid,
			name: name,
			kind: kind,
			bundleUUID: bundleUUID,
			plist: plist,
		)

		bundleIndex.addItems([item])
		changeTracker.recordChange(itemUUID: uuid, plist: plist)
		selectItem(uuid: uuid)

		return item
	}

	/// Deletes a bundle item by UUID.
	public func deleteItem(uuid: String) {
		guard let item = bundleIndex.lookup(uuid: uuid) else { return }

		// Move to trash instead of permanent delete.
		for path in item.paths {
			let url = URL(fileURLWithPath: path)
			try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
		}

		bundleIndex.removeItem(uuid: uuid)
		changeTracker.clearChange(forItem: uuid)

		if selectedItem?.uuid == uuid {
			selectedItem = nil
			currentProperties = nil
			contentView.string = ""
		}
	}
}

// MARK: - NSOutlineViewDataSource

extension BundleEditorController: NSOutlineViewDataSource {
	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		let entry = item as? BundleEditorEntry ?? .root
		return treeBuilder.children(of: entry).count
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let entry = item as? BundleEditorEntry ?? .root
		return treeBuilder.children(of: entry)[index]
	}

	public func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let entry = item as? BundleEditorEntry else { return false }
		return treeBuilder.hasChildren(entry)
	}
}

// MARK: - NSOutlineViewDelegate

extension BundleEditorController: NSOutlineViewDelegate {
	public func outlineView(
		_: NSOutlineView,
		viewFor _: NSTableColumn?,
		item: Any,
	) -> NSView? {
		guard let entry = item as? BundleEditorEntry else { return nil }
		let cell = NSTextField(labelWithString: entry.name)
		cell.isEditable = false
		return cell
	}

	public func outlineViewSelectionDidChange(_ notification: Notification) {
		guard let outlineView = notification.object as? NSOutlineView else { return }
		let row = outlineView.selectedRow
		guard row >= 0,
		      let entry = outlineView.item(atRow: row) as? BundleEditorEntry
		else { return }

		if case let .item(uuid, _, _) = entry {
			// Save current editing before switching.
			commitCurrentEditing()
			selectItem(uuid: uuid)
		}
	}
}
#endif
