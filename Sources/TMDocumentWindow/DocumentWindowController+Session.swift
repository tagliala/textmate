import AppKit
import TMDocumentManager

// MARK: - Session Management

/// Extension implementing session save/restore, mirroring the C++
/// `sessionInfoIncludingUntitledDocuments:`, `restoreSession`, and
/// `saveSessionIncludingUntitledDocuments:` class methods.
///
/// TextMate persists its window state as a plist containing an array
/// of "project" dictionaries, each describing one document window.
public extension DocumentWindowController {
	// MARK: - Session Data Types

	/// Serialised form of a single window controller's state.
	///
	/// Mirrors the C++ `sessionInfoIncludingUntitledDocuments:` dictionary.
	struct SessionWindowInfo: Codable, Sendable {
		public var projectPath: String?
		public var windowFrame: String?
		public var isMiniaturized: Bool = false
		public var isFullScreen: Bool = false
		public var isZoomed: Bool = false
		public var fileBrowserVisible: Bool = false
		public var fileBrowserWidth: CGFloat = 250
		public var fileBrowserState: Data?
		public var selectedTabIndex: Int = 0
		public var documents: [SessionDocumentInfo] = []
	}

	/// Serialised form of a single document within a session.
	struct SessionDocumentInfo: Codable, Sendable {
		public var identifier: String?
		public var path: String?
		public var fileType: String?
		public var displayName: String?
		public var isSelected: Bool = false
		public var isSticky: Bool = false
		public var selection: String?
		public var scrollPosition: [CGFloat]?
	}

	/// Top-level session container.
	struct SessionInfo: Codable, Sendable {
		public var projects: [SessionWindowInfo] = []
	}

	// MARK: - Session Path

	/// Path where the session plist is stored.
	static var sessionPath: String {
		let appSupport = NSSearchPathForDirectoriesInDomains(
			.applicationSupportDirectory, .userDomainMask, true,
		).first ?? NSTemporaryDirectory()
		let dir = (appSupport as NSString).appendingPathComponent("TextMate/Session")
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		return (dir as NSString).appendingPathComponent("Info.plist")
	}

	// MARK: - Serialize

	/// Serialize this window's state into a `SessionWindowInfo`.
	///
	/// - Parameter includeUntitled: If `false`, untitled documents without
	///   a path are excluded.
	/// - Returns: The serialised window info.
	func sessionInfo(includeUntitled: Bool) -> SessionWindowInfo {
		var info = SessionWindowInfo()
		info.projectPath = defaultProjectPath

		if let window {
			let style = window.styleMask
			if style.contains(.fullScreen) {
				info.isFullScreen = true
			} else if window.isZoomed {
				info.isZoomed = true
			} else {
				info.windowFrame = window.frameDescriptor
			}
			info.isMiniaturized = window.isMiniaturized
		}

		info.fileBrowserVisible = isFileBrowserVisible
		info.fileBrowserWidth = fileBrowserWidth
		info.fileBrowserState = try? PropertyListSerialization.data(
			fromPropertyList: fileBrowserController.sessionState,
			format: .binary,
			options: 0,
		)
		info.selectedTabIndex = selectedTabIndex

		for (i, doc) in documents.enumerated() {
			if !includeUntitled, doc.path == nil {
				continue
			}

			var docInfo = SessionDocumentInfo()
			docInfo.identifier = doc.id.uuidString
			docInfo.path = doc.path
			docInfo.fileType = doc.fileType

			if let name = doc.customName ?? doc.path.map({ ($0 as NSString).lastPathComponent }) {
				docInfo.displayName = name
			}

			docInfo.isSelected = (i == selectedTabIndex)
			docInfo.isSticky = stickyDocumentIdentifiers.contains(doc.id)
			docInfo.selection = doc.selection
			if i == selectedTabIndex {
				let origin = scrollView.contentView.bounds.origin
				docInfo.scrollPosition = [origin.x, origin.y]
			}
			info.documents.append(docInfo)
		}

		return info
	}

	// MARK: - Save Session

	/// Debounce timer for session backup.
	private nonisolated(unsafe) static var sessionBackupTimer: Timer?

	/// Whether session saving is currently disabled.
	private nonisolated(unsafe) static var disableSessionSaveCount: Int = 0

	/// Temporarily disable session saving.
	static func disableSessionSave() {
		disableSessionSaveCount += 1
	}

	/// Re-enable session saving.
	static func enableSessionSave() {
		disableSessionSaveCount -= 1
	}

	/// Schedule a debounced session backup (0.5s delay).
	///
	/// Mirrors the C++ `scheduleSessionBackup:`.
	static func scheduleSessionBackup() {
		sessionBackupTimer?.invalidate()
		sessionBackupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
			Task { @MainActor in
				_ = saveSession(includeUntitled: true)
			}
		}
	}

	/// Save the full session to disk.
	///
	/// - Parameter includeUntitled: Whether to include untitled documents.
	/// - Returns: `true` if the save succeeded.
	@discardableResult
	static func saveSession(includeUntitled: Bool) -> Bool {
		guard disableSessionSaveCount <= 0 else { return false }

		let controllers = sortedControllers

		// Single disposable window → don't save.
		if controllers.count == 1 {
			let ctrl = controllers[0]
			if ctrl.projectPath == nil, !ctrl.isFileBrowserVisible,
			   ctrl.documents.count == 1, let doc = ctrl.documents.first,
			   doc.path == nil, !doc.isModified, (doc.content ?? "").isEmpty
			{
				// Delete existing session file.
				try? FileManager.default.removeItem(atPath: sessionPath)
				return true
			}
		}

		var session = SessionInfo()
		for controller in controllers.reversed() {
			session.projects.append(controller.sessionInfo(includeUntitled: includeUntitled))
		}

		do {
			let data = try JSONEncoder().encode(session)
			try data.write(to: URL(fileURLWithPath: sessionPath), options: .atomic)
			return true
		} catch {
			return false
		}
	}

	// MARK: - Restore Session

	/// Restore the session from disk.
	///
	/// Creates `DocumentWindowController` instances for each saved project.
	///
	/// - Returns: `true` if at least one window was restored.
	@discardableResult
	static func restoreSession() -> Bool {
		disableSessionSave()
		defer { enableSessionSave() }

		let url = URL(fileURLWithPath: sessionPath)
		guard let data = try? Data(contentsOf: url),
		      let session = try? JSONDecoder().decode(SessionInfo.self, from: data)
		else {
			return false
		}

		var restored = false
		var lastWindow: NSWindow?

		for project in session.projects {
			let controller = DocumentWindowController()

			// Restore project path.
			controller.defaultProjectPath = project.projectPath
			controller.projectPath = project.projectPath

			// Restore documents.
			var docs: [TMDocument] = []
			var selectedScrollPos: [CGFloat]?
			for docInfo in project.documents {
				let doc = if let path = docInfo.path {
					TMDocument(path: path, fileType: docInfo.fileType)
				} else {
					TMDocument(fileType: docInfo.fileType)
				}
				doc.selection = docInfo.selection
				if docInfo.isSticky {
					controller.setDocument(doc, sticky: true)
				}
				if docInfo.isSelected {
					selectedScrollPos = docInfo.scrollPosition
				}
				docs.append(doc)
			}

			if docs.isEmpty {
				docs.append(TMDocument())
			}

			controller.documents = docs
			controller.selectedTabIndex = min(
				project.selectedTabIndex,
				max(docs.count - 1, 0),
			)

			// Restore window frame.
			if let frame = project.windowFrame {
				controller.window?.setFrame(from: NSWindow.PersistableFrameDescriptor(frame))
			}

			if project.isMiniaturized {
				controller.window?.miniaturize(nil)
			} else {
				controller.showWindow(nil)
				lastWindow = controller.window
			}

			if project.isFullScreen {
				controller.window?.toggleFullScreen(nil)
			} else if project.isZoomed {
				controller.window?.zoom(nil)
			}

			// Restore file browser state.
			if let stateData = project.fileBrowserState,
			   let plist = try? PropertyListSerialization.propertyList(
			   	from: stateData, format: nil,
			   ) as? [String: Any]
			{
				controller.fileBrowserController.setupView(withState: plist)
			}

			controller.isFileBrowserVisible = project.fileBrowserVisible
			controller.fileBrowserWidth = project.fileBrowserWidth
			if !project.fileBrowserVisible {
				controller.projectLayoutView.fileBrowserView = nil
			}

			// Open the selected document.
			controller.openAndSelectDocument(docs[controller.selectedTabIndex], activate: true)

			// Restore selection and scroll position for the selected document.
			if let sel = docs[controller.selectedTabIndex].selection {
				controller.navigateToSelectionString(sel)
			}
			if let pos = selectedScrollPos, pos.count == 2 {
				let point = NSPoint(x: pos[0], y: pos[1])
				controller.scrollView.contentView.scroll(to: point)
				controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)
			}

			restored = true
		}

		lastWindow?.makeKey()

		return restored
	}

	// MARK: - Project State

	/// Save per-project state (file browser, documents) for restore.
	func saveProjectState() {
		guard treatAsProjectWindow, let path = projectPath else { return }
		let info = sessionInfo(includeUntitled: false)
		do {
			let data = try JSONEncoder().encode(info)
			let key = "ProjectState:\(path)"
			UserDefaults.standard.set(data, forKey: key)
		} catch {
			// Silently ignore encode failures.
		}
	}

	/// Restore per-project state.
	///
	/// - Parameter path: The project path to restore state for.
	/// - Returns: The restored `SessionWindowInfo`, or `nil`.
	static func loadProjectState(for path: String) -> SessionWindowInfo? {
		let key = "ProjectState:\(path)"
		guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
		return try? JSONDecoder().decode(SessionWindowInfo.self, from: data)
	}

	/// Restore documents/tabs from saved project state for the current project path.
	///
	/// Call after ``setProjectRoot(_:)`` so that ``projectPath`` is set.
	/// - Returns: `true` if project state was found and documents were restored.
	@discardableResult
	func restoreProjectState() -> Bool {
		guard let path = projectPath,
		      let state = Self.loadProjectState(for: path)
		else { return false }

		var docs: [TMDocument] = []
		for docInfo in state.documents {
			let doc = if let path = docInfo.path {
				TMDocument(path: path, fileType: docInfo.fileType)
			} else {
				TMDocument(fileType: docInfo.fileType)
			}
			doc.selection = docInfo.selection
			docs.append(doc)
		}
		guard !docs.isEmpty else { return false }

		documents = docs
		selectedTabIndex = min(
			state.selectedTabIndex,
			max(docs.count - 1, 0),
		)
		openAndSelectDocument(docs[selectedTabIndex], activate: true)
		return true
	}
}
