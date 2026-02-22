import Foundation

// MARK: - Document Controller

/// Central registry of all documents within the application.
///
/// Matches the C++ `OakDocumentController` design:
/// - Deduplicates by path and UUID
/// - Tracks untitled document sequence numbers
/// - Provides LRU ordering for recently accessed documents
/// - Manages the lifecycle of documents (factory, retrieve, forget)
@MainActor
public final class TMDocumentController {
	/// Shared singleton instance.
	public static let shared = TMDocumentController()

	// MARK: - Storage

	/// Primary storage: UUID → document.
	private var documentsByUUID: [UUID: TMDocument] = [:]

	/// Path-based index for deduplication.
	private var documentsByPath: [String: UUID] = [:]

	/// Ordered list for LRU access tracking.
	private var lruOrder: [UUID] = []

	/// The next sequence number for untitled documents.
	private var untitledSequence: Int = 1

	/// Maximum number of documents to keep in the LRU list.
	public var maxLRUCount: Int = 25

	// MARK: - Callbacks

	/// Called when a document is added to the registry.
	public var onDocumentAdded: ((TMDocument) -> Void)?

	// MARK: - Init

	private init() {}

	// MARK: - Factory

	/// Returns an existing document for the path, or creates a new one.
	///
	/// This is the primary entry point for opening files. If a document
	/// already exists for the given path, it is returned. Otherwise,
	/// a new document is created and registered.
	public func documentForPath(_ path: String, fileType: String? = nil) -> TMDocument {
		// Resolve to canonical path
		let canonical = canonicalize(path)

		// Check for existing document
		if let uuid = documentsByPath[canonical],
		   let existing = documentsByUUID[uuid]
		{
			touchLRU(uuid)
			return existing
		}

		// Create new document
		let doc = TMDocument(path: canonical, fileType: fileType)
		register(doc)
		return doc
	}

	/// Returns an existing document for the UUID, or nil.
	public func documentForUUID(_ uuid: UUID) -> TMDocument? {
		documentsByUUID[uuid]
	}

	/// Creates a new untitled document.
	public func createUntitledDocument(fileType: String? = nil) -> TMDocument {
		let doc = TMDocument(fileType: fileType)
		doc.customName = untitledName()
		register(doc)
		return doc
	}

	// MARK: - Registration

	/// Registers a document in the controller.
	public func register(_ document: TMDocument) {
		documentsByUUID[document.id] = document
		if let path = document.path {
			documentsByPath[canonicalize(path)] = document.id
		}
		touchLRU(document.id)
		onDocumentAdded?(document)
		NotificationCenter.default.post(
			name: .documentControllerDidAddDocument,
			object: self,
			userInfo: ["document": document],
		)
	}

	/// Removes a document from the controller.
	public func forget(_ document: TMDocument) {
		documentsByUUID.removeValue(forKey: document.id)
		if let path = document.path {
			documentsByPath.removeValue(forKey: canonicalize(path))
		}
		lruOrder.removeAll { $0 == document.id }
		NotificationCenter.default.post(
			name: .documentControllerDidRemoveDocument,
			object: self,
			userInfo: ["document": document],
		)
	}

	// MARK: - Path Updates

	/// Called when a document's path changes (e.g., after Save As or rename).
	public func documentDidChangePath(
		_ document: TMDocument,
		from oldPath: String?,
		to newPath: String?,
	) {
		if let old = oldPath {
			documentsByPath.removeValue(forKey: canonicalize(old))
		}
		if let new = newPath {
			documentsByPath[canonicalize(new)] = document.id
		}
	}

	// MARK: - Querying

	/// All registered documents.
	public var documents: [TMDocument] {
		Array(documentsByUUID.values)
	}

	/// The number of registered documents.
	public var count: Int {
		documentsByUUID.count
	}

	/// All open documents (those with at least one viewer).
	public var openDocuments: [TMDocument] {
		documentsByUUID.values.filter(\.isOpen)
	}

	/// All modified documents.
	public var modifiedDocuments: [TMDocument] {
		documentsByUUID.values.filter(\.isModified)
	}

	/// Documents in LRU order (most recently accessed first).
	public var recentlyUsed: [TMDocument] {
		lruOrder.compactMap { documentsByUUID[$0] }
	}

	/// Whether any document has unsaved changes.
	public var hasModifiedDocuments: Bool {
		documentsByUUID.values.contains { $0.isModified }
	}

	/// Finds a document by exact path.
	public func findByPath(_ path: String) -> TMDocument? {
		let canonical = canonicalize(path)
		guard let uuid = documentsByPath[canonical] else { return nil }
		return documentsByUUID[uuid]
	}

	/// Finds documents matching a predicate.
	public func find(where predicate: (TMDocument) -> Bool) -> [TMDocument] {
		documentsByUUID.values.filter(predicate)
	}

	// MARK: - LRU Tracking

	/// Marks a document as recently accessed.
	public func touchLRU(_ uuid: UUID) {
		lruOrder.removeAll { $0 == uuid }
		lruOrder.insert(uuid, at: 0)
		trimLRU()
	}

	private func trimLRU() {
		// Only trim entries for documents that are no longer open
		while lruOrder.count > maxLRUCount {
			let uuid = lruOrder.last!
			if let doc = documentsByUUID[uuid], !doc.isOpen {
				lruOrder.removeLast()
				forget(doc)
			} else {
				break
			}
		}
	}

	// MARK: - Untitled Documents

	private func untitledName() -> String {
		let name = untitledSequence == 1 ? "Untitled" : "Untitled \(untitledSequence)"
		untitledSequence += 1
		return name
	}

	/// Resets the untitled document sequence counter. Useful for testing.
	public func resetUntitledSequence() {
		untitledSequence = 1
	}

	// MARK: - Cleanup

	/// Removes all documents from the registry. Useful for testing.
	public func removeAll() {
		let docs = Array(documentsByUUID.values)
		for doc in docs {
			forget(doc)
		}
		untitledSequence = 1
	}

	/// Removes closed, unmodified documents that are not in any window.
	public func pruneUnusedDocuments() {
		let candidates = documentsByUUID.values.filter { !$0.isOpen && !$0.isModified }
		for doc in candidates {
			forget(doc)
		}
	}

	// MARK: - Path Canonicalization

	/// Resolves symlinks and standardizes a path for deduplication.
	private func canonicalize(_ path: String) -> String {
		let nsPath = (path as NSString).standardizingPath
		let url = URL(fileURLWithPath: nsPath)
		return url.resolvingSymlinksInPath().path
	}
}

// MARK: - Open Documents Summary

public extension TMDocumentController {
	/// A summary of the current controller state for debugging.
	var debugSummary: String {
		let total = documentsByUUID.count
		let open = openDocuments.count
		let modified = modifiedDocuments.count
		return "TMDocumentController: \(total) total, \(open) open, \(modified) modified"
	}
}

// MARK: - Notification Names

public extension Notification.Name {
	/// Posted when a document is registered with TMDocumentController.
	/// `userInfo["document"]` contains the `TMDocument`.
	static let documentControllerDidAddDocument = Notification.Name(
		"TMDocumentControllerDidAddDocument",
	)

	/// Posted when a document is removed from TMDocumentController.
	/// `userInfo["document"]` contains the `TMDocument`.
	static let documentControllerDidRemoveDocument = Notification.Name(
		"TMDocumentControllerDidRemoveDocument",
	)
}
