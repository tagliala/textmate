#if canImport(AppKit)
import AppKit

// MARK: - ProjectLayoutView

/// Constraint-based layout that arranges the document view, file browser,
/// and HTML output panel with draggable dividers. Port of the C++
/// `ProjectLayoutView` from `Frameworks/DocumentWindow/src/ProjectLayoutView.mm`.
///
/// Layout variants:
/// ```
/// ┌──────────┬──┬─────────────────┐   ┌─────────────────┬──┬──────────┐
/// │ file     │  │                 │   │                 │  │ file     │
/// │ browser  │  │  document view  │   │  document view  │  │ browser  │
/// │          │  │                 │   │                 │  │          │
/// └──────────┴──┴─────────────────┘   └─────────────────┴──┴──────────┘
///   fileBrowserOnRight = false           fileBrowserOnRight = true
///
/// With HTML output below:              With HTML output on right:
/// ┌──────────┬──┬─────────────────┐   ┌──────────┬──┬───────┬──┬─────┐
/// │ file     │  │  document view  │   │ file     │  │ doc   │  │html │
/// │ browser  │  │                 │   │ browser  │  │       │  │     │
/// ├──────────┴──┼─────────────────┤   │          │  │       │  │     │
/// │             │ HTML output     │   └──────────┴──┴───────┴──┴─────┘
/// └─────────────┴─────────────────┘
/// ```
@MainActor
public class ProjectLayoutView: NSView {
	// MARK: - Subviews

	/// The main document/editor area.
	public var documentView: NSView? {
		willSet { documentView?.removeFromSuperview() }
		didSet {
			if let v = documentView {
				v.translatesAutoresizingMaskIntoConstraints = false
				addSubview(v)
			}
			needsUpdateConstraints = true
			updateKeyViewLoop()
		}
	}

	/// The file browser sidebar.
	public var fileBrowserView: NSView? {
		willSet {
			fileBrowserView?.removeFromSuperview()
			fileBrowserDivider?.removeFromSuperview()
			fileBrowserDivider = nil
		}
		didSet {
			if let v = fileBrowserView {
				v.translatesAutoresizingMaskIntoConstraints = false
				addSubview(v)
				let div = makeDivider(vertical: true)
				addSubview(div)
				fileBrowserDivider = div
			}
			needsUpdateConstraints = true
			updateKeyViewLoop()
		}
	}

	/// The HTML output panel (for bundle command output).
	public var htmlOutputView: NSView? {
		willSet {
			htmlOutputView?.removeFromSuperview()
			htmlOutputDivider?.removeFromSuperview()
			htmlOutputDivider = nil
		}
		didSet {
			if let v = htmlOutputView {
				v.translatesAutoresizingMaskIntoConstraints = false
				addSubview(v)
				let div = makeDivider(vertical: htmlOutputOnRight)
				addSubview(div)
				htmlOutputDivider = div
			}
			needsUpdateConstraints = true
			updateKeyViewLoop()
		}
	}

	// MARK: - Layout Configuration

	/// Width of the file browser sidebar (persisted to UserDefaults).
	public var fileBrowserWidth: CGFloat = 250 {
		didSet {
			fileBrowserWidthConstraint?.constant = fileBrowserWidth
			UserDefaults.standard.set(Int(fileBrowserWidth), forKey: "fileBrowserWidth")
		}
	}

	/// Whether the file browser is on the right side (default: left).
	public var fileBrowserOnRight: Bool = false {
		didSet {
			guard fileBrowserOnRight != oldValue, fileBrowserView != nil else { return }
			needsUpdateConstraints = true
		}
	}

	/// Size of the HTML output panel.
	public var htmlOutputSize: NSSize = .init(width: 200, height: 200) {
		didSet {
			htmlOutputSizeConstraint?.constant = htmlOutputOnRight
				? htmlOutputSize.width : htmlOutputSize.height
		}
	}

	/// Whether the HTML output is on the right (default: bottom).
	public var htmlOutputOnRight: Bool = false {
		didSet {
			guard htmlOutputOnRight != oldValue else { return }
			// Recreate divider with correct orientation
			if htmlOutputView != nil {
				let v = htmlOutputView
				htmlOutputView = nil
				htmlOutputView = v
			}
		}
	}

	// MARK: - Private

	private var fileBrowserDivider: NSView?
	private var htmlOutputDivider: NSView?
	private var fileBrowserWidthConstraint: NSLayoutConstraint?
	private var htmlOutputSizeConstraint: NSLayoutConstraint?
	private var layoutConstraints: [NSLayoutConstraint] = []
	private var isDragging = false

	override public init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true

		let defaults = UserDefaults.standard
		if let w = defaults.object(forKey: "fileBrowserWidth") as? CGFloat, w > 0 {
			fileBrowserWidth = w
		}
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Constraint Layout

	override public func updateConstraints() {
		NSLayoutConstraint.deactivate(layoutConstraints)
		layoutConstraints.removeAll()
		super.updateConstraints()

		guard let doc = documentView else { return }

		// ---------- Document view ----------

		// Top: always pinned to top
		layoutConstraints.append(doc.topAnchor.constraint(equalTo: topAnchor))

		// Bottom
		if let _ = htmlOutputView, let htmlDiv = htmlOutputDivider, !htmlOutputOnRight {
			layoutConstraints.append(doc.bottomAnchor.constraint(equalTo: htmlDiv.topAnchor))
		} else {
			layoutConstraints.append(doc.bottomAnchor.constraint(equalTo: bottomAnchor))
		}

		// Leading
		if let fb = fileBrowserView, let fbDiv = fileBrowserDivider, !fileBrowserOnRight {
			_ = fb // suppress unused
			layoutConstraints.append(doc.leadingAnchor.constraint(equalTo: fbDiv.trailingAnchor))
		} else {
			layoutConstraints.append(doc.leadingAnchor.constraint(equalTo: leadingAnchor))
		}

		// Trailing
		if let html = htmlOutputView, let htmlDiv = htmlOutputDivider, htmlOutputOnRight {
			_ = html
			layoutConstraints.append(doc.trailingAnchor.constraint(equalTo: htmlDiv.leadingAnchor))
		} else if let _ = fileBrowserView, let fbDiv = fileBrowserDivider, fileBrowserOnRight {
			layoutConstraints.append(doc.trailingAnchor.constraint(equalTo: fbDiv.leadingAnchor))
		} else {
			layoutConstraints.append(doc.trailingAnchor.constraint(equalTo: trailingAnchor))
		}

		// ---------- File browser ----------

		if let fb = fileBrowserView, let fbDiv = fileBrowserDivider {
			// Width
			let wc = fb.widthAnchor.constraint(equalToConstant: fileBrowserWidth)
			wc.priority = .dragThatCannotResizeWindow
			fileBrowserWidthConstraint = wc
			layoutConstraints.append(wc)

			// Vertical
			layoutConstraints.append(fb.topAnchor.constraint(equalTo: topAnchor))
			layoutConstraints.append(fbDiv.topAnchor.constraint(equalTo: topAnchor))

			if let html = htmlOutputView, let htmlDiv = htmlOutputDivider, !htmlOutputOnRight {
				_ = html
				layoutConstraints.append(fb.bottomAnchor.constraint(equalTo: htmlDiv.topAnchor))
				layoutConstraints.append(fbDiv.bottomAnchor.constraint(equalTo: htmlDiv.topAnchor))
			} else {
				layoutConstraints.append(fb.bottomAnchor.constraint(equalTo: bottomAnchor))
				layoutConstraints.append(fbDiv.bottomAnchor.constraint(equalTo: bottomAnchor))
			}

			// Horizontal placement
			if fileBrowserOnRight {
				layoutConstraints.append(fb.trailingAnchor.constraint(equalTo: trailingAnchor))
				layoutConstraints.append(fbDiv.trailingAnchor.constraint(equalTo: fb.leadingAnchor))
			} else {
				layoutConstraints.append(fb.leadingAnchor.constraint(equalTo: leadingAnchor))
				layoutConstraints.append(fbDiv.leadingAnchor.constraint(equalTo: fb.trailingAnchor))
			}
		}

		// ---------- HTML output ----------

		if let html = htmlOutputView, let htmlDiv = htmlOutputDivider {
			if htmlOutputOnRight {
				let wc = html.widthAnchor.constraint(equalToConstant: htmlOutputSize.width)
				wc.priority = NSLayoutConstraint
					.Priority(rawValue: NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)
				htmlOutputSizeConstraint = wc
				layoutConstraints.append(wc)

				layoutConstraints.append(html.topAnchor.constraint(equalTo: topAnchor))
				layoutConstraints.append(html.bottomAnchor.constraint(equalTo: bottomAnchor))
				layoutConstraints.append(htmlDiv.topAnchor.constraint(equalTo: topAnchor))
				layoutConstraints.append(htmlDiv.bottomAnchor.constraint(equalTo: bottomAnchor))

				if let _ = fileBrowserView, let fbDiv = fileBrowserDivider, fileBrowserOnRight {
					layoutConstraints.append(html.trailingAnchor.constraint(equalTo: fbDiv.leadingAnchor))
				} else {
					layoutConstraints.append(html.trailingAnchor.constraint(equalTo: trailingAnchor))
				}
				layoutConstraints.append(htmlDiv.trailingAnchor.constraint(equalTo: html.leadingAnchor))
			} else {
				let hc = html.heightAnchor.constraint(equalToConstant: htmlOutputSize.height)
				hc.priority = NSLayoutConstraint
					.Priority(rawValue: NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)
				htmlOutputSizeConstraint = hc
				layoutConstraints.append(hc)

				layoutConstraints.append(html.bottomAnchor.constraint(equalTo: bottomAnchor))
				layoutConstraints.append(html.leadingAnchor.constraint(equalTo: leadingAnchor))
				layoutConstraints.append(html.trailingAnchor.constraint(equalTo: trailingAnchor))
				layoutConstraints.append(htmlDiv.bottomAnchor.constraint(equalTo: html.topAnchor))
				layoutConstraints.append(htmlDiv.leadingAnchor.constraint(equalTo: leadingAnchor))
				layoutConstraints.append(htmlDiv.trailingAnchor.constraint(equalTo: trailingAnchor))
			}
		}

		NSLayoutConstraint.activate(layoutConstraints)
		window?.invalidateCursorRects(for: self)
	}

	// MARK: - Divider Drag Resize

	override public func resetCursorRects() {
		if let rect = fileBrowserResizeRect {
			addCursorRect(rect, cursor: .resizeLeftRight)
		}
		if let rect = htmlOutputResizeRect {
			addCursorRect(rect, cursor: htmlOutputOnRight ? .resizeLeftRight : .resizeUpDown)
		}
	}

	override public var mouseDownCanMoveWindow: Bool {
		false
	}

	override public func hitTest(_ point: NSPoint) -> NSView? {
		let local = convert(point, from: superview)
		if let rect = fileBrowserResizeRect, NSMouseInRect(local, rect, isFlipped) {
			return self
		}
		if let rect = htmlOutputResizeRect, NSMouseInRect(local, rect, isFlipped) {
			return self
		}
		return super.hitTest(point)
	}

	override public func mouseDown(with event: NSEvent) {
		let mouseDown = convert(event.locationInWindow, from: nil)

		var target: NSView?
		if let rect = fileBrowserResizeRect, NSMouseInRect(mouseDown, rect, isFlipped) {
			target = fileBrowserView
		} else if let rect = htmlOutputResizeRect, NSMouseInRect(mouseDown, rect, isFlipped) {
			target = htmlOutputView
		}

		guard let target else {
			super.mouseDown(with: event)
			return
		}

		let initialFrame = target.frame
		isDragging = true
		defer { isDragging = false }

		while true {
			guard let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
			if next.type == .leftMouseUp { break }

			let current = convert(next.locationInWindow, from: nil)

			if target === fileBrowserView {
				let delta = current.x - mouseDown.x
				let width = initialFrame.width + delta * (fileBrowserOnRight ? -1 : 1)
				fileBrowserWidth = max(50, round(width))
				UserDefaults.standard.set(Int(fileBrowserWidth), forKey: "fileBrowserWidth")
			} else if target === htmlOutputView {
				if htmlOutputOnRight {
					let width = initialFrame.width + (mouseDown.x - current.x)
					htmlOutputSize.width = max(50, round(width))
				} else {
					let height = initialFrame.height + (current.y - mouseDown.y)
					htmlOutputSize.height = max(50, round(height))
				}
			}

			window?.invalidateCursorRects(for: self)
		}
	}

	// MARK: - Resize Rects

	private var fileBrowserResizeRect: NSRect? {
		guard let fb = fileBrowserView else { return nil }
		let r = fb.frame
		return fileBrowserOnRight
			? NSRect(x: r.minX - 3, y: r.minY, width: 10, height: r.height)
			: NSRect(x: r.maxX - 4, y: r.minY, width: 10, height: r.height)
	}

	private var htmlOutputResizeRect: NSRect? {
		guard let html = htmlOutputView else { return nil }
		let r = html.frame
		return htmlOutputOnRight
			? NSRect(x: r.minX - 3, y: r.minY, width: 10, height: r.height)
			: NSRect(x: r.minX, y: r.maxY - 4, width: r.width, height: 10)
	}

	// MARK: - Helpers

	private func makeDivider(vertical: Bool) -> NSView {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		if vertical {
			box.widthAnchor.constraint(equalToConstant: 1).isActive = true
		} else {
			box.heightAnchor.constraint(equalToConstant: 1).isActive = true
		}
		return box
	}

	private func updateKeyViewLoop() {
		let views = [documentView, htmlOutputView, fileBrowserView].compactMap(\.self)
		for i in 0 ..< views.count {
			views[i].nextKeyView = views[(i + 1) % views.count]
		}
	}

	/// Close the HTML output panel.
	public func performCloseSplit() {
		htmlOutputView = nil
	}
}
#endif
