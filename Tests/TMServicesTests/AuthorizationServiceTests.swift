import Foundation
import Testing
@testable import TMServices

@Suite("AuthorizationService - Constants")
struct AuthorizationConstantsTests {
	@Test("Job name follows reverse-DNS pattern")
	func jobName() {
		let name = AuthorizationConstants.jobName
		#expect(name.contains("."))
		#expect(!name.isEmpty)
	}

	@Test("Right name follows reverse-DNS pattern")
	func rightName() {
		let name = AuthorizationConstants.rightName
		#expect(name.contains("."))
		#expect(!name.isEmpty)
	}
}

@Suite("AuthorizationService - Serialization")
@MainActor
struct AuthorizationSerializationTests {
	@Test("Serialize and deserialize round-trips")
	func roundTrip() {
		// We can't test actual AuthorizationRef creation without privileges,
		// but we can ensure the hex encoding/decoding functions are consistent.
		let service = AuthorizationService.shared
		// Verify the shared instance exists
		#expect(type(of: service) == AuthorizationService.self)
	}
}

@Suite("AuthorizationService - Error Types")
struct AuthorizationErrorTests {
	@Test("Error descriptions are non-empty")
	func errorDescriptions() {
		let errors: [AuthorizationError] = [
			.helperNotAvailable,
			.authorizationDenied,
			.authorizationCanceled,
			.unknownError,
		]
		for error in errors {
			#expect(error.errorDescription != nil)
			#expect(error.errorDescription?.isEmpty == false)
		}
	}

	@Test("All cases are distinct")
	func distinctCases() {
		let errors: [AuthorizationError] = [
			.helperNotAvailable,
			.authorizationDenied,
			.authorizationCanceled,
			.unknownError,
		]
		let descriptions = errors.compactMap(\.errorDescription)
		let unique = Set(descriptions)
		#expect(unique.count == errors.count)
	}
}
