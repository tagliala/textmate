import AppKit

/// A parsed color from a `.tmTheme` file.
///
/// Theme colors are specified as hex strings: `#RRGGBB` or `#RRGGBBAA`.
/// Short forms (`#RGB`, `#RGBA`) are also accepted.
public struct ThemeColor: Sendable, Hashable {
	public let red: CGFloat
	public let green: CGFloat
	public let blue: CGFloat
	public let alpha: CGFloat

	public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	/// Parse a hex color string (`#RRGGBB`, `#RRGGBBAA`, `#RGB`, `#RGBA`).
	///
	/// Returns `nil` if the string is not a valid hex color.
	public init?(hex: String) {
		var s = hex
		if s.hasPrefix("#") {
			s = String(s.dropFirst())
		}
		guard !s.isEmpty else { return nil }

		if s.count <= 4 {
			// Short form: #RGB or #RGBA
			let chars = Array(s)
			guard chars.count >= 3 else { return nil }
			guard let r = UInt8(String(repeating: chars[0], count: 2), radix: 16),
			      let g = UInt8(String(repeating: chars[1], count: 2), radix: 16),
			      let b = UInt8(String(repeating: chars[2], count: 2), radix: 16)
			else { return nil }
			let a: UInt8 = chars.count >= 4
				? (UInt8(String(repeating: chars[3], count: 2), radix: 16) ?? 0xFF)
				: 0xFF
			self.init(
				red: CGFloat(r) / 255,
				green: CGFloat(g) / 255,
				blue: CGFloat(b) / 255,
				alpha: CGFloat(a) / 255,
			)
		} else {
			// Long form: #RRGGBB or #RRGGBBAA
			guard s.count >= 6 else { return nil }
			let chars = Array(s)
			guard let r = UInt8(String(chars[0 ... 1]), radix: 16),
			      let g = UInt8(String(chars[2 ... 3]), radix: 16),
			      let b = UInt8(String(chars[4 ... 5]), radix: 16)
			else { return nil }
			let a: UInt8 = chars.count >= 8
				? (UInt8(String(chars[6 ... 7]), radix: 16) ?? 0xFF)
				: 0xFF
			self.init(
				red: CGFloat(r) / 255,
				green: CGFloat(g) / 255,
				blue: CGFloat(b) / 255,
				alpha: CGFloat(a) / 255,
			)
		}
	}

	/// Convert to an `NSColor` in sRGB color space.
	public var nsColor: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}

	/// Convert to a `CGColor` in sRGB color space.
	public var cgColor: CGColor {
		nsColor.cgColor
	}

	/// Whether this color is considered "dark" (luminance < 0.5).
	public var isDark: Bool {
		let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
		return luminance < 0.5
	}
}
