import AppKit
import Testing
@testable import TMEditorUI

@Suite("RenderContext")
struct RenderContextTests {
	// MARK: - Unprintable Representations

	@Test("NUL character has representation")
	func nulRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x00)))
		#expect(rep == "<NUL>")
	}

	@Test("Escape character has representation")
	func escapeRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x1B)))
		#expect(rep == "<ESC>")
	}

	@Test("Backspace character has representation")
	func backspaceRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x08)))
		#expect(rep == "<BS>")
	}

	@Test("Carriage return has representation")
	func crRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x0D)))
		#expect(rep == "<CR>")
	}

	@Test("Form feed has representation")
	func formFeedRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x0C)))
		#expect(rep == "<NP>")
	}

	@Test("Ctrl+A is ^A")
	func ctrlARepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x01)))
		#expect(rep == "^A")
	}

	@Test("Ctrl+Z is ^Z")
	func ctrlZRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x1A)))
		#expect(rep == "^Z")
	}

	@Test("Non-breaking space has representation")
	func nbspRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0xA0)))
		#expect(rep == "·")
	}

	@Test("DEL area characters get diamond")
	func delAreaRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x7F)))
		#expect(rep == "◆")
	}

	@Test("C1 control characters get diamond")
	func c1ControlRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x80)))
		#expect(rep == "◆")
	}

	@Test("Printable ASCII returns nil")
	func printableASCII() throws {
		#expect(try unprintableRepresentation(for: #require(Unicode.Scalar(0x41))) == nil) // 'A'
		#expect(try unprintableRepresentation(for: #require(Unicode.Scalar(0x7E))) == nil) // '~'
		#expect(try unprintableRepresentation(for: #require(Unicode.Scalar(0x20))) == nil) // space
	}

	@Test("Tab returns nil")
	func tabReturnsNil() throws {
		#expect(try unprintableRepresentation(for: #require(Unicode.Scalar(0x09))) == nil)
	}

	@Test("Newline returns nil")
	func newlineReturnsNil() throws {
		#expect(try unprintableRepresentation(for: #require(Unicode.Scalar(0x0A))) == nil)
	}

	@Test("Unicode line separator has representation")
	func lineSeparatorRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x2028)))
		#expect(rep == "<U+2028>")
	}

	@Test("Unicode BOM/ZWNBS has representation")
	func bomRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0xFEFF)))
		#expect(rep == "<U+FEFF>")
	}

	@Test("Unicode word joiner has representation")
	func wordJoinerRepresentation() throws {
		let rep = try unprintableRepresentation(for: #require(Unicode.Scalar(0x2060)))
		#expect(rep == "<U+2060>")
	}

	// MARK: - Invisibles Mapping

	@Test("Default invisible map excludes all glyphs")
	@MainActor
	func defaultMapping() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		// Default map "~ ~\t~\n" excludes all invisibles
		let rc = RenderContext(context: ctx)
		#expect(rc.spaceGlyph == "")
		#expect(rc.tabGlyph == "")
		#expect(rc.newlineGlyph == "")
	}

	@Test("Custom mapping sets standard glyphs")
	@MainActor
	func customMapping() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx, invisibleMap: " ·\t‣\n¬")
		#expect(rc.spaceGlyph == "·")
		#expect(rc.tabGlyph == "‣")
		#expect(rc.newlineGlyph == "¬")
	}

	@Test("Exclude space glyph via ~ prefix")
	@MainActor
	func excludeSpace() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx, invisibleMap: "~ ")
		#expect(rc.spaceGlyph == "")
	}

	@Test("Custom tab glyph")
	@MainActor
	func customTabGlyph() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx, invisibleMap: "\t→")
		#expect(rc.tabGlyph == "→")
	}

	@Test("Custom newline glyph")
	@MainActor
	func customNewlineGlyph() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx, invisibleMap: "\n↵")
		#expect(rc.newlineGlyph == "↵")
	}

	@Test("Exclude all invisibles")
	@MainActor
	func excludeAll() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx, invisibleMap: "~ ~\t~\n")
		#expect(rc.spaceGlyph == "")
		#expect(rc.tabGlyph == "")
		#expect(rc.newlineGlyph == "")
	}

	// MARK: - Folding Dots Cache

	@Test("Folding dots are cached by size")
	@MainActor
	func foldingDotsCaching() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)

		var factoryCallCount = 0
		let rc = RenderContext(context: ctx) { width, height in
			factoryCallCount += 1
			// Create a minimal bitmap context as stand-in for an image
			let bmp = CGContext(
				data: nil,
				width: Int(width),
				height: Int(height),
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
			)
			return bmp?.makeImage()
		}

		let img1 = rc.foldingDots(width: 20, height: 10)
		let img2 = rc.foldingDots(width: 20, height: 10)
		let img3 = rc.foldingDots(width: 40, height: 20)

		#expect(img1 != nil)
		#expect(img2 != nil)
		#expect(img3 != nil)
		#expect(factoryCallCount == 2) // Only called once per unique size
	}

	@Test("Folding dots returns nil without factory")
	@MainActor
	func foldingDotsNilWithoutFactory() throws {
		let bitmapRep = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 4, bitsPerPixel: 32,
		))
		let ctx = try #require(NSGraphicsContext(bitmapImageRep: bitmapRep)?.cgContext)
		let rc = RenderContext(context: ctx)
		#expect(rc.foldingDots(width: 20, height: 10) == nil)
	}
}
