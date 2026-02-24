import Foundation

// MARK: - File Type Detection Result

/// Result of file type detection, with the detected scope and confidence.
public struct FileTypeResult: Sendable, Equatable {
	/// The grammar scope (e.g., "source.swift").
	public let scope: String

	/// How the type was detected.
	public let method: DetectionMethod

	/// How the detection was performed.
	public enum DetectionMethod: Sendable, Equatable {
		case shebang
		case firstLine
		case fileExtension
		case filename
		case userOverride
		case defaultFallback
	}
}

// MARK: - File Type Detector

/// Detects file types by examining file name, extension, and content.
///
/// Matches the C++ `file::type` functionality — uses a combination of:
/// 1. User overrides (via settings)
/// 2. Shebang line analysis
/// 3. First-line pattern matching (e.g., XML declaration, `<?php`)
/// 4. File extension mapping
/// 5. Exact filename matching
///
/// The default scope map covers common file types. Additional mappings
/// can be registered at runtime.
public struct FileTypeDetector: Sendable {
	// MARK: - Extension → Scope Mapping

	/// Maps file extensions to grammar scopes.
	public var extensionMap: [String: String]

	/// Maps exact filenames to grammar scopes.
	public var filenameMap: [String: String]

	/// Maps shebang interpreters to grammar scopes.
	public var interpreterMap: [String: String]

	/// Maps first-line patterns (regex) to grammar scopes.
	public var firstLinePatterns: [(pattern: String, scope: String)]

	/// The fallback scope when nothing else matches.
	public var defaultScope: String = "text.plain"

	// MARK: - Init

	public init(
		extensionMap: [String: String]? = nil,
		filenameMap: [String: String]? = nil,
		interpreterMap: [String: String]? = nil,
		firstLinePatterns: [(pattern: String, scope: String)]? = nil,
	) {
		self.extensionMap = extensionMap ?? Self.defaultExtensionMap
		self.filenameMap = filenameMap ?? Self.defaultFilenameMap
		self.interpreterMap = interpreterMap ?? Self.defaultInterpreterMap
		self.firstLinePatterns = firstLinePatterns ?? Self.defaultFirstLinePatterns
	}

	// MARK: - Detection

	/// Detects the file type from path and optional content.
	public func detect(path: String?, content: String? = nil) -> FileTypeResult {
		// 1. Content-based detection (shebang and first-line patterns)
		if let content {
			if let result = detectFromContent(content) {
				return result
			}
		}

		// 2. Path-based detection
		if let path {
			if let result = detectFromPath(path) {
				return result
			}
		}

		// 3. Fallback
		return FileTypeResult(scope: defaultScope, method: .defaultFallback)
	}

	// MARK: - Content Detection

	/// Detects file type from content (shebang, first-line patterns).
	public func detectFromContent(_ content: String) -> FileTypeResult? {
		let firstLine = String(content.prefix(while: { $0 != "\n" && $0 != "\r" }))

		// Shebang detection
		if firstLine.hasPrefix("#!") {
			if let result = detectFromShebang(firstLine) {
				return result
			}
		}

		// First-line pattern matching
		for (pattern, scope) in firstLinePatterns {
			if let regex = try? NSRegularExpression(pattern: pattern, options: []),
			   regex.firstMatch(
			   	in: firstLine,
			   	range: NSRange(firstLine.startIndex..., in: firstLine),
			   ) != nil
			{
				return FileTypeResult(scope: scope, method: .firstLine)
			}
		}

		return nil
	}

	/// Extracts the interpreter from a shebang line and maps it to a scope.
	private func detectFromShebang(_ shebangLine: String) -> FileTypeResult? {
		let line = shebangLine.trimmingCharacters(in: .whitespaces)
		guard line.hasPrefix("#!") else { return nil }

		let path = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)

		// Handle `/usr/bin/env interpreter`
		let interpreter: String
		if path.contains("env") {
			let parts = path.split(separator: " ").map(String.init)
			if let envIndex = parts.firstIndex(where: { $0.hasSuffix("env") }),
			   envIndex + 1 < parts.count
			{
				// Skip flags like -S
				let afterEnv = parts[(envIndex + 1)...]
				let cmd = afterEnv.first { !$0.hasPrefix("-") }
				interpreter = cmd.map { ($0 as NSString).lastPathComponent } ?? ""
			} else {
				interpreter = ""
			}
		} else {
			// Direct path: `/usr/bin/python3`
			let parts = path.split(separator: " ").map(String.init)
			interpreter = (parts.first.map { ($0 as NSString).lastPathComponent }) ?? ""
		}

		guard !interpreter.isEmpty else { return nil }

		// Try exact match first, then strip version numbers
		if let scope = interpreterMap[interpreter] {
			return FileTypeResult(scope: scope, method: .shebang)
		}

		// Strip trailing version number: python3.11 → python, ruby3 → ruby
		let stripped = interpreter.replacingOccurrences(
			of: "[0-9]+(\\.[0-9]+)*$",
			with: "",
			options: .regularExpression,
		)
		if !stripped.isEmpty, let scope = interpreterMap[stripped] {
			return FileTypeResult(scope: scope, method: .shebang)
		}

		return nil
	}

	// MARK: - Path Detection

	/// Detects file type from filename and extension.
	public func detectFromPath(_ path: String) -> FileTypeResult? {
		let filename = (path as NSString).lastPathComponent

		// Exact filename match
		if let scope = filenameMap[filename] {
			return FileTypeResult(scope: scope, method: .filename)
		}

		// Case-insensitive filename match
		let lowerFilename = filename.lowercased()
		for (name, scope) in filenameMap {
			if name.lowercased() == lowerFilename {
				return FileTypeResult(scope: scope, method: .filename)
			}
		}

		// Extension match
		let ext = (filename as NSString).pathExtension.lowercased()
		if !ext.isEmpty, let scope = extensionMap[ext] {
			return FileTypeResult(scope: scope, method: .fileExtension)
		}

		// Compound extensions (e.g., "test.spec.ts" → check "spec.ts")
		let components = filename.split(separator: ".").map(String.init)
		if components.count > 2 {
			let compoundExt = components.suffix(2).joined(separator: ".").lowercased()
			if let scope = extensionMap[compoundExt] {
				return FileTypeResult(scope: scope, method: .fileExtension)
			}
		}

		return nil
	}

	// MARK: - Default Mappings

	/// Default file extension to grammar scope mapping.
	public static let defaultExtensionMap: [String: String] = [
		// Programming languages
		"swift": "source.swift",
		"m": "source.objc",
		"mm": "source.objcpp",
		"c": "source.c",
		"cc": "source.cpp",
		"cpp": "source.cpp",
		"cxx": "source.cpp",
		"h": "source.objcpp",
		"hpp": "source.cpp",
		"hxx": "source.cpp",
		"java": "source.java",
		"kt": "source.kotlin",
		"kts": "source.kotlin",
		"scala": "source.scala",
		"go": "source.go",
		"rs": "source.rust",
		"py": "source.python",
		"rb": "source.ruby",
		"pl": "source.perl",
		"pm": "source.perl",
		"php": "source.php",
		"js": "source.js",
		"jsx": "source.js.jsx",
		"ts": "source.ts",
		"tsx": "source.tsx",
		"cs": "source.cs",
		"fs": "source.fsharp",
		"vb": "source.vbnet",
		"lua": "source.lua",
		"r": "source.r",
		"R": "source.r",
		"dart": "source.dart",
		"ex": "source.elixir",
		"exs": "source.elixir",
		"erl": "source.erlang",
		"hrl": "source.erlang",
		"hs": "source.haskell",
		"ml": "source.ocaml",
		"mli": "source.ocaml",
		"clj": "source.clojure",
		"cljs": "source.clojure",

		// Shell
		"sh": "source.shell",
		"bash": "source.shell",
		"zsh": "source.shell",
		"fish": "source.shell.fish",

		// Markup
		"html": "text.html.basic",
		"htm": "text.html.basic",
		"xhtml": "text.html.basic",
		"xml": "text.xml",
		"xsl": "text.xml.xsl",
		"xsd": "text.xml",
		"svg": "text.xml.svg",

		// Data
		"json": "source.json",
		"yaml": "source.yaml",
		"yml": "source.yaml",
		"toml": "source.toml",
		"ini": "source.ini",
		"cfg": "source.ini",
		"conf": "source.ini",
		"plist": "text.xml.plist",
		"csv": "text.csv",

		// Markdown / Text
		"md": "text.html.markdown",
		"markdown": "text.html.markdown",
		"rst": "text.restructuredtext",
		"tex": "text.tex.latex",
		"txt": "text.plain",
		"log": "text.plain",

		// Web
		"css": "source.css",
		"scss": "source.scss",
		"sass": "source.sass",
		"less": "source.less",
		"styl": "source.stylus",

		// Config
		"dockerfile": "source.dockerfile",
		"cmake": "source.cmake",

		// SQL
		"sql": "source.sql",

		// Diff
		"diff": "source.diff",
		"patch": "source.diff",

		// Build
		"make": "source.makefile",
		"rave": "source.makefile",
	]

	/// Default exact filename to grammar scope mapping.
	public static let defaultFilenameMap: [String: String] = [
		"Makefile": "source.makefile",
		"GNUmakefile": "source.makefile",
		"CMakeLists.txt": "source.cmake",
		"Dockerfile": "source.dockerfile",
		"Containerfile": "source.dockerfile",
		"Rakefile": "source.ruby",
		"Gemfile": "source.ruby",
		"Podfile": "source.ruby",
		"Vagrantfile": "source.ruby",
		"Guardfile": "source.ruby",
		"Fastfile": "source.ruby",
		".gitignore": "source.gitignore",
		".gitattributes": "source.gitattributes",
		".editorconfig": "source.ini",
		".bashrc": "source.shell",
		".bash_profile": "source.shell",
		".zshrc": "source.shell",
		".zprofile": "source.shell",
		"Package.swift": "source.swift",
		"Package.resolved": "source.json",
		".swiftlint.yml": "source.yaml",
		"Brewfile": "source.ruby",
		"Procfile": "source.yaml",
		"Justfile": "source.makefile",
	]

	/// Default shebang interpreter to grammar scope mapping.
	public static let defaultInterpreterMap: [String: String] = [
		"python": "source.python",
		"python3": "source.python",
		"ruby": "source.ruby",
		"perl": "source.perl",
		"node": "source.js",
		"bash": "source.shell",
		"sh": "source.shell",
		"zsh": "source.shell",
		"fish": "source.shell.fish",
		"php": "source.php",
		"lua": "source.lua",
		"Rscript": "source.r",
		"elixir": "source.elixir",
		"awk": "source.awk",
		"sed": "source.shell",
		"swift": "source.swift",
		"tclsh": "source.tcl",
		"wish": "source.tcl",
	]

	/// Default first-line patterns for content-based detection.
	public static let defaultFirstLinePatterns: [(pattern: String, scope: String)] = [
		(pattern: "^<\\?xml\\b", scope: "text.xml"),
		(pattern: "^<\\?php\\b", scope: "source.php"),
		(pattern: "^<!DOCTYPE\\s+html", scope: "text.html.basic"),
		(pattern: "^<html", scope: "text.html.basic"),
		(pattern: "^%YAML", scope: "source.yaml"),
		(pattern: "^\\\\documentclass", scope: "text.tex.latex"),
		(pattern: "^\\\\input\\{", scope: "text.tex"),
		(pattern: "^-\\*-.*mode:\\s*ruby", scope: "source.ruby"),
		(pattern: "^-\\*-.*mode:\\s*python", scope: "source.python"),
		(pattern: "^-\\*-.*mode:\\s*perl", scope: "source.perl"),
	]

	/// The shared default detector instance.
	public static let `default` = FileTypeDetector()
}
