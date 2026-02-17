import AppKit
import CoreText

// MARK: - Print Settings Keys

/// User-defaults and print-info dictionary keys for printing.
public enum PrintSettingKey {
	/// The UUID of the theme used for print rendering.
	public static let themeUUID = "OakPrintThemeUUID"

	/// The font size (in points) for printed text.
	public static let fontSize = "OakPrintFontSize"

	/// Whether to print header and footer (document name, page number, date).
	public static let headerAndFooter = "OakPrintHeaderAndFooter"
}

// MARK: - Printable Document View

/// A view that renders document text for printing with syntax highlighting.
///
/// Port of C++ `OakDocumentPrintableView` from
/// `Frameworks/document/src/Printing.mm`.
///
/// The view creates its own ``EditorLayoutManager`` configured for the
/// print page size with soft wrapping enabled.  When the print system
/// calls `knowsPageRange(_:)`, the layout is fully computed and page
/// boundaries are determined at line edges so that no line is split
/// across pages.
@MainActor
public class PrintableDocumentView: NSView {
	// MARK: - Properties

	/// The text content to print.
	private let textContent: String

	/// The document title (used for `printJobTitle`).
	private let documentTitle: String

	/// The font name from the editor (used as base font).
	private let fontName: String?

	/// Font size for printing (overridden by print options).
	private var fontSize: CGFloat = 11

	/// The computed page rectangles in document coordinates.
	private var pageRects: [CGRect] = []

	/// Whether layout needs to be recomputed.
	private var needsLayoutUpdate: Bool = true

	/// The page width in points (excluding margins).
	private var pageWidth: CGFloat = 0

	/// The page height in points (excluding margins).
	private var pageHeight: CGFloat = 0

	/// The layout manager used for print rendering.
	private let layoutManager = EditorLayoutManager()

	/// Style provider callback — given (line index, line text), returns
	/// style runs for syntax-highlighted printing.
	public var styleProvider: ((Int, String) -> [StyleRun])? {
		didSet {
			layoutManager.styleProvider = styleProvider
			needsLayoutUpdate = true
		}
	}

	// MARK: - Initialization

	/// Creates a printable view for the given text content.
	///
	/// - Parameters:
	///   - text: The full document text.
	///   - title: The document title (used in the print job name).
	///   - fontName: The font name to use (nil = system monospace).
	///   - styleProvider: Optional callback for syntax highlighting.
	public init(
		text: String,
		title: String,
		fontName: String? = nil,
		styleProvider: ((Int, String) -> [StyleRun])? = nil,
	) {
		textContent = text
		documentTitle = title
		self.fontName = fontName
		self.styleProvider = styleProvider
		super.init(frame: .zero)

		layoutManager.softWrap = true
		layoutManager.styleProvider = styleProvider
		layoutManager.setText(text)

		registerDefaults()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	// MARK: - Defaults

	private func registerDefaults() {
		UserDefaults.standard.register(defaults: [
			PrintSettingKey.fontSize: 11,
			PrintSettingKey.headerAndFooter: false,
		])
	}

	// MARK: - NSView Overrides

	override public var isFlipped: Bool {
		true
	}

	override public var printJobTitle: String {
		documentTitle
	}

	// MARK: - Page Geometry

	override public func knowsPageRange(_ range: NSRangePointer) -> Bool {
		guard let printInfo = NSPrintOperation.current?.printInfo else {
			return false
		}

		// Compute usable area from imageable page bounds.
		let imageable = NSIntersectionRect(
			printInfo.imageablePageBounds,
			NSRect(origin: .zero, size: printInfo.paperSize),
		)
		printInfo.leftMargin = imageable.minX
		printInfo.rightMargin = printInfo.paperSize.width - imageable.maxX
		printInfo.topMargin = printInfo.paperSize.height - imageable.maxY
		printInfo.bottomMargin = imageable.minY

		let newWidth = floor(printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin)
		let newHeight = floor(printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin)
		let newFontSize = (printInfo.dictionary()[PrintSettingKey.fontSize] as? NSNumber)?
			.doubleValue ?? 11

		if pageWidth != newWidth { needsLayoutUpdate = true
			pageWidth = newWidth
		}
		if pageHeight != newHeight { needsLayoutUpdate = true
			pageHeight = newHeight
		}
		if fontSize != CGFloat(newFontSize) { needsLayoutUpdate = true
			fontSize = CGFloat(newFontSize)
		}

		updateLayout()

		frame = NSRect(x: 0, y: 0, width: pageWidth, height: layoutManager.totalHeight)

		range.pointee = NSRange(location: 1, length: pageRects.count)
		return true
	}

	override public func rectForPage(_ page: Int) -> NSRect {
		guard page >= 1, page <= pageRects.count else {
			return .zero
		}
		return pageRects[page - 1]
	}

	// MARK: - Drawing

	override public func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		guard !NSGraphicsContext.current!.isDrawingToScreen else { return }

		let visibleLines = layoutManager.layoutLines(in: dirtyRect, overscan: 0)
		guard let context = NSGraphicsContext.current?.cgContext else { return }

		for line in visibleLines {
			let drawPoint = CGPoint(x: line.origin.x, y: line.origin.y)

			// Draw background highlights
			line.drawBackground(
				at: drawPoint,
				height: line.height,
				in: context,
				defaultBackground: NSColor.white.cgColor,
			)

			// Draw the text. CTLineDraw expects the baseline position.
			// In a flipped view the baseline is at origin.y + ascent.
			let ascent = CTLineGetTypographicBounds(line.ctLine, nil, nil, nil)
			let baselinePoint = CGPoint(
				x: drawPoint.x,
				y: drawPoint.y + CGFloat(ascent),
			)

			context.saveGState()
			// Core Text uses a non-flipped coordinate system. We need
			// to flip the context for correct glyph rendering.
			context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
			line.drawForeground(at: baselinePoint, in: context)
			context.restoreGState()

			// Draw decorations
			line.drawUnderlines(at: baselinePoint, in: context)
			line.drawStrikethroughs(at: baselinePoint, in: context)
		}
	}

	// MARK: - Layout

	/// Recomputes the layout and page break positions.
	///
	/// Pagination iterates visual lines, accumulating height until
	/// a page boundary is reached.  Page breaks always occur at line
	/// boundaries so no line is split across pages.
	private func updateLayout() {
		guard needsLayoutUpdate else { return }
		needsLayoutUpdate = false

		pageRects.removeAll()

		// Configure the layout manager for printing.
		if let name = fontName {
			layoutManager.setFont(name: name, size: fontSize)
		} else {
			layoutManager.setFont(
				NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
			)
		}
		layoutManager.viewportSize = CGSize(width: pageWidth, height: pageHeight)

		// Force full layout by requesting all lines.
		let allRect = CGRect(
			x: 0,
			y: 0,
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude,
		)
		let allLines = layoutManager.layoutLines(in: allRect, overscan: 0)

		guard !allLines.isEmpty else {
			// Empty document — single empty page.
			pageRects.append(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
			return
		}

		// Build page rects by accumulating lines until the page is full.
		var currentPageY = allLines[0].origin.y
		var currentPageBottom = currentPageY + pageHeight

		var pageStartY = currentPageY
		var lastLineBottom = currentPageY

		for line in allLines {
			let lineTop = line.origin.y
			let lineBottom = lineTop + line.height

			if lineBottom > currentPageBottom, lastLineBottom > pageStartY {
				// This line doesn't fit — end the current page at the
				// previous line's bottom.
				let rect = CGRect(
					x: 0,
					y: pageStartY,
					width: pageWidth,
					height: lastLineBottom - pageStartY,
				)
				pageRects.append(rect)

				// Start a new page from this line.
				pageStartY = lineTop
				currentPageY = lineTop
				currentPageBottom = lineTop + pageHeight
			}

			lastLineBottom = lineBottom
		}

		// Final page for remaining lines.
		if lastLineBottom > pageStartY {
			let rect = CGRect(
				x: 0,
				y: pageStartY,
				width: pageWidth,
				height: lastLineBottom - pageStartY,
			)
			pageRects.append(rect)
		}

		// Ensure at least one page.
		if pageRects.isEmpty {
			pageRects.append(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
		}
	}

	// MARK: - Public Query

	/// The number of computed pages.
	public var pageCount: Int {
		pageRects.count
	}
}
