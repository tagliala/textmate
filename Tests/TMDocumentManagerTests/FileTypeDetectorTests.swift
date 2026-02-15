import Foundation
import Testing
@testable import TMDocumentManager

@Suite("FileTypeDetector - File Type Detection")
struct FileTypeDetectorTests {
	let detector = FileTypeDetector.default

	// MARK: - Extension Detection

	@Test("Detect Swift file by extension")
	func detectSwift() {
		let result = detector.detect(path: "/tmp/hello.swift")
		#expect(result.scope == "source.swift")
		#expect(result.method == .fileExtension)
	}

	@Test("Detect Python file by extension")
	func detectPython() {
		let result = detector.detect(path: "/tmp/script.py")
		#expect(result.scope == "source.python")
	}

	@Test("Detect Ruby file by extension")
	func detectRuby() {
		let result = detector.detect(path: "/tmp/app.rb")
		#expect(result.scope == "source.ruby")
	}

	@Test("Detect JavaScript file by extension")
	func detectJS() {
		let result = detector.detect(path: "/tmp/app.js")
		#expect(result.scope == "source.js")
	}

	@Test("Detect TypeScript file by extension")
	func detectTS() {
		let result = detector.detect(path: "/tmp/app.ts")
		#expect(result.scope == "source.ts")
	}

	@Test("Detect C++ file by extension")
	func detectCpp() {
		let result = detector.detect(path: "/tmp/main.cc")
		#expect(result.scope == "source.cpp")
	}

	@Test("Detect HTML file by extension")
	func detectHTML() {
		let result = detector.detect(path: "/tmp/page.html")
		#expect(result.scope == "text.html.basic")
	}

	@Test("Detect JSON file by extension")
	func detectJSON() {
		let result = detector.detect(path: "/tmp/config.json")
		#expect(result.scope == "source.json")
	}

	@Test("Detect YAML file by extension")
	func detectYAML() {
		let result = detector.detect(path: "/tmp/config.yml")
		#expect(result.scope == "source.yaml")
	}

	@Test("Detect Markdown file by extension")
	func detectMarkdown() {
		let result = detector.detect(path: "/tmp/README.md")
		#expect(result.scope == "text.html.markdown")
	}

	@Test("Detect CSS file by extension")
	func detectCSS() {
		let result = detector.detect(path: "/tmp/styles.css")
		#expect(result.scope == "source.css")
	}

	@Test("Detect SQL file by extension")
	func detectSQL() {
		let result = detector.detect(path: "/tmp/query.sql")
		#expect(result.scope == "source.sql")
	}

	@Test("Detect shell script by extension")
	func detectShell() {
		let result = detector.detect(path: "/tmp/deploy.sh")
		#expect(result.scope == "source.shell")
	}

	@Test("Detect Go file by extension")
	func detectGo() {
		let result = detector.detect(path: "/tmp/main.go")
		#expect(result.scope == "source.go")
	}

	@Test("Detect Rust file by extension")
	func detectRust() {
		let result = detector.detect(path: "/tmp/lib.rs")
		#expect(result.scope == "source.rust")
	}

	@Test("Case insensitive extension matching")
	func caseInsensitive() {
		// Extensions are lowercased during detection
		let result = detector.detect(path: "/tmp/file.PY")
		#expect(result.scope == "source.python")
	}

	// MARK: - Filename Detection

	@Test("Detect Makefile by exact name")
	func detectMakefile() {
		let result = detector.detect(path: "/tmp/Makefile")
		#expect(result.scope == "source.makefile")
		#expect(result.method == .filename)
	}

	@Test("Detect Dockerfile by exact name")
	func detectDockerfile() {
		let result = detector.detect(path: "/tmp/Dockerfile")
		#expect(result.scope == "source.dockerfile")
		#expect(result.method == .filename)
	}

	@Test("Detect Gemfile by exact name")
	func detectGemfile() {
		let result = detector.detect(path: "/tmp/Gemfile")
		#expect(result.scope == "source.ruby")
		#expect(result.method == .filename)
	}

	@Test("Detect .gitignore by exact name")
	func detectGitignore() {
		let result = detector.detect(path: "/tmp/.gitignore")
		#expect(result.scope == "source.gitignore")
	}

	@Test("Detect .bashrc by exact name")
	func detectBashrc() {
		let result = detector.detect(path: "/home/user/.bashrc")
		#expect(result.scope == "source.shell")
	}

	@Test("Detect CMakeLists.txt by exact name")
	func detectCMakeLists() {
		let result = detector.detect(path: "/tmp/CMakeLists.txt")
		#expect(result.scope == "source.cmake")
		#expect(result.method == .filename)
	}

	// MARK: - Shebang Detection

	@Test("Detect Python from shebang")
	func sheebangPython() {
		let content = "#!/usr/bin/python3\nimport sys\nprint(sys.argv)"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.python")
		#expect(result.method == .shebang)
	}

	@Test("Detect Ruby from shebang")
	func sheebangRuby() {
		let content = "#!/usr/bin/ruby\nputs 'hello'"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.ruby")
		#expect(result.method == .shebang)
	}

	@Test("Detect bash from env shebang")
	func sheebangEnvBash() {
		let content = "#!/usr/bin/env bash\necho hello"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.shell")
		#expect(result.method == .shebang)
	}

	@Test("Detect Node from env shebang")
	func sheebangEnvNode() {
		let content = "#!/usr/bin/env node\nconsole.log('hi')"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.js")
		#expect(result.method == .shebang)
	}

	@Test("Detect python with version stripped")
	func sheebangPythonVersion() {
		let content = "#!/usr/bin/python3.11\nimport os"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.python")
	}

	@Test("Detect perl from shebang")
	func sheebangPerl() {
		let content = "#!/usr/bin/perl\nuse strict;"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.perl")
	}

	@Test("Env with flags: /usr/bin/env -S python3")
	func envWithFlags() {
		let content = "#!/usr/bin/env -S python3\nimport sys"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.python")
	}

	// MARK: - First-Line Pattern Detection

	@Test("Detect XML from declaration")
	func firstLineXML() {
		let content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "text.xml")
		#expect(result.method == .firstLine)
	}

	@Test("Detect PHP from opening tag")
	func firstLinePHP() {
		let content = "<?php\necho 'hello';"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "source.php")
		#expect(result.method == .firstLine)
	}

	@Test("Detect HTML from DOCTYPE")
	func firstLineHTML() {
		let content = "<!DOCTYPE html>\n<html>"
		let result = detector.detect(path: nil, content: content)
		#expect(result.scope == "text.html.basic")
		#expect(result.method == .firstLine)
	}

	// MARK: - Content takes priority over path

	@Test("Shebang overrides file extension")
	func sheebangOverridesExtension() {
		// A .txt file with a Python shebang
		let content = "#!/usr/bin/python3\nprint('hello')"
		let result = detector.detect(path: "/tmp/script.txt", content: content)
		#expect(result.scope == "source.python")
		#expect(result.method == .shebang)
	}

	// MARK: - Fallback

	@Test("Unknown extension falls back to text.plain")
	func fallbackUnknown() {
		let result = detector.detect(path: "/tmp/file.xyz123")
		#expect(result.scope == "text.plain")
		#expect(result.method == .defaultFallback)
	}

	@Test("No path and no content falls back")
	func fallbackNone() {
		let result = detector.detect(path: nil, content: nil)
		#expect(result.scope == "text.plain")
		#expect(result.method == .defaultFallback)
	}

	@Test("Empty content falls back to path")
	func emptyContentFallsToPath() {
		let result = detector.detect(path: "/tmp/hello.swift", content: "")
		#expect(result.scope == "source.swift")
	}

	// MARK: - Custom Detector

	@Test("Custom extension mapping")
	func customExtensionMap() {
		var custom = FileTypeDetector()
		custom.extensionMap["xyz"] = "source.xyz"

		let result = custom.detect(path: "/tmp/file.xyz")
		#expect(result.scope == "source.xyz")
	}

	@Test("Custom filename mapping")
	func customFilenameMap() {
		var custom = FileTypeDetector()
		custom.filenameMap["Buildfile"] = "source.build"

		let result = custom.detect(path: "/tmp/Buildfile")
		#expect(result.scope == "source.build")
	}

	@Test("Custom interpreter mapping")
	func customInterpreterMap() {
		var custom = FileTypeDetector()
		custom.interpreterMap["myinterp"] = "source.myinterp"

		let content = "#!/usr/bin/myinterp\nstuff"
		let result = custom.detect(path: nil, content: content)
		#expect(result.scope == "source.myinterp")
	}

	// MARK: - FileTypeResult

	@Test("FileTypeResult detection methods are distinguishable")
	func detectionMethods() {
		#expect(FileTypeResult.DetectionMethod.shebang != .fileExtension)
		#expect(FileTypeResult.DetectionMethod.filename != .firstLine)
		#expect(FileTypeResult.DetectionMethod.userOverride != .defaultFallback)
	}

	// MARK: - Default Maps

	@Test("Default extension map covers common types")
	func defaultExtensionMapCoverage() {
		let map = FileTypeDetector.defaultExtensionMap
		let requiredKeys = [
			"swift", "py", "rb", "js", "ts", "c", "cc", "cpp", "h",
			"html", "css", "json", "yaml", "md", "sh", "sql", "go", "rs",
		]
		for key in requiredKeys {
			#expect(map[key] != nil, "Missing extension: \(key)")
		}
	}

	@Test("Default filename map covers essentials")
	func defaultFilenameMapCoverage() {
		let map = FileTypeDetector.defaultFilenameMap
		let requiredKeys = [
			"Makefile", "Dockerfile", "Gemfile", ".gitignore", "CMakeLists.txt",
		]
		for key in requiredKeys {
			#expect(map[key] != nil, "Missing filename: \(key)")
		}
	}

	@Test("Default interpreter map covers common interpreters")
	func defaultInterpreterMapCoverage() {
		let map = FileTypeDetector.defaultInterpreterMap
		let requiredKeys = ["python", "ruby", "perl", "node", "bash", "sh"]
		for key in requiredKeys {
			#expect(map[key] != nil, "Missing interpreter: \(key)")
		}
	}
}
