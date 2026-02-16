import Foundation
import Testing
@testable import TMServices

@Suite("VersionComparison")
struct VersionComparisonTests {
	// MARK: - Basic Comparison

	@Test("Equal versions")
	func equal() {
		#expect(VersionComparison.compare("2.0", "2.0") == .orderedSame)
	}

	@Test("Less than")
	func lessThan() {
		#expect(VersionComparison.compare("1.0", "2.0") == .orderedAscending)
	}

	@Test("Greater than")
	func greaterThan() {
		#expect(VersionComparison.compare("3.0", "2.0") == .orderedDescending)
	}

	// MARK: - Multi-component

	@Test("Multi-component comparison")
	func multiComponent() {
		#expect(VersionComparison.compare("1.2.3", "1.2.4") == .orderedAscending)
		#expect(VersionComparison.compare("1.2.3", "1.2.3") == .orderedSame)
		#expect(VersionComparison.compare("1.2.4", "1.2.3") == .orderedDescending)
	}

	@Test("Different component counts")
	func differentLengths() {
		// 1.2 vs 1.2.0 — trailing zeros stripped, should be equal
		#expect(VersionComparison.compare("1.2", "1.2.0") == .orderedSame)
		#expect(VersionComparison.compare("1.2.0.0", "1.2") == .orderedSame)
	}

	@Test("Different component counts non-zero")
	func differentLengthsNonZero() {
		#expect(VersionComparison.compare("1.2", "1.2.1") == .orderedAscending)
	}

	// MARK: - Prerelease

	@Test("Prerelease is less than release")
	func prerelease() {
		#expect(VersionComparison.compare("1.0-beta", "1.0") == .orderedAscending)
	}

	@Test("Prerelease ordering")
	func prereleaseOrdering() {
		#expect(VersionComparison.compare("1.0-alpha", "1.0-beta") == .orderedAscending)
	}

	// MARK: - Build Metadata

	@Test("Build metadata is ignored")
	func buildMetadata() {
		#expect(VersionComparison.compare("1.0+build1", "1.0+build2") == .orderedSame)
		#expect(VersionComparison.compare("1.0+build", "1.0") == .orderedSame)
	}

	// MARK: - Less Helper

	@Test("less helper function")
	func lessHelper() {
		#expect(VersionComparison.less("1.0", "2.0"))
		#expect(!VersionComparison.less("2.0", "1.0"))
		#expect(!VersionComparison.less("1.0", "1.0"))
	}

	// MARK: - Numeric vs String

	@Test("Numeric segments compared numerically")
	func numericComparison() {
		#expect(VersionComparison.compare("1.9", "1.10") == .orderedAscending)
	}

	// MARK: - Edge Cases

	@Test("Empty strings")
	func emptyStrings() {
		#expect(VersionComparison.compare("", "") == .orderedSame)
	}

	@Test("Single component")
	func singleComponent() {
		#expect(VersionComparison.compare("1", "2") == .orderedAscending)
		#expect(VersionComparison.compare("10", "2") == .orderedDescending)
	}

	@Test("Real TextMate versions")
	func realVersions() {
		#expect(VersionComparison.compare("2.0-rc.10", "2.0-rc.9") == .orderedDescending)
		#expect(VersionComparison.compare("2.0-rc.10", "2.0") == .orderedAscending)
		#expect(VersionComparison.compare("2.0.23", "2.0.22") == .orderedDescending)
	}
}
