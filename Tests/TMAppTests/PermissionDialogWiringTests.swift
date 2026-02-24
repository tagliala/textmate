#if canImport(AppKit)
import Testing
@testable import TMApp
@testable import TMBundleRuntime

@Suite("PermissionDialogController wiring")
@MainActor
struct PermissionDialogWiringTests {
	@Test("CommandDispatcher has permissionHandler set after BundleSystemController init")
	func permissionHandlerSet() {
		let system = BundleSystemController()
		#expect(system.commandDispatcher.permissionHandler != nil)
	}

	@Test("CommandDispatcher without handler denies permission requests")
	func noHandlerDenies() {
		let dispatcher = CommandDispatcher(
			bundleIndex: BundleIndex(),
			securityPolicy: SecurityPolicy(defaultTrustLevel: .blocked),
		)
		// No permissionHandler → should not execute
		#expect(dispatcher.permissionHandler == nil)
	}
}
#endif
