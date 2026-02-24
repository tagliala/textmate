import Foundation
import Testing
@testable import TMServices

@Suite("SoftwareUpdateEngine")
struct SoftwareUpdateEngineTests {
	// MARK: - DefaultsKey Constants

	@Test("DefaultsKey constants match C++ originals")
	func defaultsKeyConstants() {
		#expect(SoftwareUpdateEngine.DefaultsKey.lastCheck == "SoftwareUpdateLastPoll")
		#expect(SoftwareUpdateEngine.DefaultsKey.suspendUntil == "SoftwareUpdateSuspendUntil")
		#expect(SoftwareUpdateEngine.DefaultsKey.disablePolling == "SoftwareUpdateDisablePolling")
		#expect(SoftwareUpdateEngine.DefaultsKey.askBeforeUpdating == "SoftwareUpdateAskBeforeUpdating")
		#expect(SoftwareUpdateEngine.DefaultsKey.channel == "SoftwareUpdateChannel")
		#expect(SoftwareUpdateEngine.DefaultsKey
			.disableReadOnlyWarning == "SoftwareUpdateDisableReadOnlyFileSystemWarningKey")
	}

	// MARK: - Channel Constants

	@Test("Channel constants match C++ originals")
	func channelConstants() {
		#expect(SoftwareUpdateEngine.Channel.release == "release")
		#expect(SoftwareUpdateEngine.Channel.prerelease == "beta")
		#expect(SoftwareUpdateEngine.Channel.canary == "nightly")
	}

	// MARK: - Error Descriptions

	@Test("UpdateError descriptions are descriptive")
	func errorDescriptions() {
		let errors: [SoftwareUpdateEngine.UpdateError] = [
			.noChannelConfigured,
			.unknownChannel("test"),
			.incompleteServerResponse,
			.malformedServerResponse,
			.missingContentType,
			.readOnlyFileSystem,
			.installationFailed("failed"),
			.integrityCheckFailed,
		]
		for error in errors {
			#expect(!error.description.isEmpty)
		}
	}

	// MARK: - Properties

	@Test("Engine initial state")
	@MainActor func initialState() {
		let engine = SoftwareUpdateEngine()
		#expect(!engine.isChecking)
		#expect(engine.errorString == nil)
		#expect(engine.channels.isEmpty)
		#expect(engine.publicKeys.isEmpty)
		#expect(engine.checkInterval == 3600)
	}

	// MARK: - Check For Update

	@Test("Check for update with no channels throws")
	@MainActor func checkNoChannels() async {
		let engine = SoftwareUpdateEngine()
		engine.channels = [:]

		do {
			_ = try await engine.checkForUpdate()
			Issue.record("Should have thrown")
		} catch {
			// Expected
			#expect(error is SoftwareUpdateEngine.UpdateError)
		}
	}

	@Test("Check for update with unknown channel throws")
	@MainActor func checkUnknownChannel() async throws {
		let engine = SoftwareUpdateEngine()
		engine.channels = try ["release": #require(URL(string: "https://example.com"))]

		// Set channel to something else
		UserDefaults.standard.set("custom", forKey: SoftwareUpdateEngine.DefaultsKey.channel)
		defer { UserDefaults.standard.removeObject(forKey: SoftwareUpdateEngine.DefaultsKey.channel) }

		do {
			_ = try await engine.checkForUpdate()
			Issue.record("Should have thrown")
		} catch {
			#expect(error is SoftwareUpdateEngine.UpdateError)
		}
	}

	// MARK: - Suspend Checks

	@Test("Suspend checks sets date")
	@MainActor func suspendChecks() throws {
		let engine = SoftwareUpdateEngine()
		engine.suspendChecks(for: 3600)

		let date = UserDefaults.standard.object(forKey: SoftwareUpdateEngine.DefaultsKey.suspendUntil) as? Date
		#expect(date != nil)
		#expect(try #require(date?.timeIntervalSinceNow) > 3500)

		// Clean up
		UserDefaults.standard.removeObject(forKey: SoftwareUpdateEngine.DefaultsKey.suspendUntil)
	}

	// MARK: - Read-only FS

	@Test("Application is not on read-only filesystem in test env")
	@MainActor func readOnlyFS() {
		let engine = SoftwareUpdateEngine()
		// In normal test environment, the app is not on a read-only FS
		#expect(!engine.isApplicationOnReadOnlyFileSystem())
	}

	// MARK: - Version Check Result

	@Test("VersionCheckResult enum cases")
	func versionCheckResult() throws {
		let r1: SoftwareUpdateEngine.VersionCheckResult = try .updateAvailable(
			url: #require(URL(string: "https://example.com")),
			version: "2.1",
		)
		let r2: SoftwareUpdateEngine.VersionCheckResult = .upToDate(version: "2.0")
		let r3: SoftwareUpdateEngine.VersionCheckResult = .prerelease(localVersion: "2.1", remoteVersion: "2.0")

		if case let .updateAvailable(_, version) = r1 {
			#expect(version == "2.1")
		} else {
			Issue.record("Expected updateAvailable")
		}

		if case let .upToDate(version) = r2 {
			#expect(version == "2.0")
		} else {
			Issue.record("Expected upToDate")
		}

		if case let .prerelease(local, remote) = r3 {
			#expect(local == "2.1")
			#expect(remote == "2.0")
		} else {
			Issue.record("Expected prerelease")
		}
	}
}
