#if canImport(AppKit)
import Testing
@testable import TMApp

@Suite("BundleSystemController — Async Loading")
@MainActor
struct BundleSystemAsyncLoadingTests {
	@Test("loadBundlesAsync sets hasLoadedBundles")
	func asyncLoadSetsFlag() async {
		let controller = BundleSystemController()
		#expect(controller.hasLoadedBundles == false)

		await controller.loadBundlesAsync()
		#expect(controller.hasLoadedBundles == true)
	}

	@Test("synchronous loadBundles still works")
	func syncLoadSetsFlag() {
		let controller = BundleSystemController()
		#expect(controller.hasLoadedBundles == false)

		controller.loadBundles()
		#expect(controller.hasLoadedBundles == true)
	}

	@Test("loadBundles from empty paths succeeds")
	func loadFromEmptyPaths() {
		let controller = BundleSystemController()
		controller.loadBundles(from: ["/nonexistent-path"])
		#expect(controller.hasLoadedBundles == true)
	}
}
#endif
