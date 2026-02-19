import Foundation
import Testing
@testable import TMBundle

@Suite("BundlePlistParser")
struct BundlePlistParserTests {
	// MARK: - Basic Parsing

	@Test func parseEmptyDictionary() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict/>
		</plist>
		"""
		let dict = try BundlePlistParser.parse(data: Data(xml.utf8))
		#expect(dict.isEmpty)
	}

	@Test func parseStringValues() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>name</key>
		  <string>Test Grammar</string>
		  <key>scopeName</key>
		  <string>source.test</string>
		</dict>
		</plist>
		"""
		let dict = try BundlePlistParser.parse(data: Data(xml.utf8))
		#expect(try BundlePlistParser.string(dict, key: "name") == "Test Grammar")
		#expect(try BundlePlistParser.string(dict, key: "scopeName") == "source.test")
	}

	@Test func missingKeyThrows() throws {
		let dict: [String: Any] = ["name": "Test"]
		#expect(throws: BundlePlistParser.ParseError.self) {
			try BundlePlistParser.string(dict, key: "missing")
		}
	}

	@Test func wrongTypeThrows() throws {
		let dict: [String: Any] = ["name": 42]
		#expect(throws: BundlePlistParser.ParseError.self) {
			try BundlePlistParser.string(dict, key: "name")
		}
	}

	@Test func invalidPlistThrows() throws {
		let bad = Data("not a plist".utf8)
		#expect(throws: BundlePlistParser.ParseError.self) {
			try BundlePlistParser.parse(data: bad)
		}
	}

	// MARK: - Optional Accessors

	@Test func optionalAccessors() {
		let dict: [String: Any] = [
			"str": "hello",
			"num": 42,
			"flag": true,
		]
		#expect(BundlePlistParser.optionalString(dict, key: "str") == "hello")
		#expect(BundlePlistParser.optionalString(dict, key: "missing") == nil)
		#expect(BundlePlistParser.optionalInt(dict, key: "num") == 42)
		#expect(BundlePlistParser.optionalBool(dict, key: "flag") == true)
	}

	@Test func boolFromString() {
		let dict: [String: Any] = ["yes": "yes", "no": "false", "one": "1"]
		#expect(BundlePlistParser.optionalBool(dict, key: "yes") == true)
		#expect(BundlePlistParser.optionalBool(dict, key: "no") == false)
		#expect(BundlePlistParser.optionalBool(dict, key: "one") == true)
	}
}

// MARK: - Grammar Definition Tests

@Suite("GrammarDefinition")
struct GrammarDefinitionTests {
	@Test func parseMinimalGrammar() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>scopeName</key>
		  <string>source.test</string>
		  <key>name</key>
		  <string>Test Language</string>
		  <key>fileTypes</key>
		  <array>
		    <string>test</string>
		    <string>tst</string>
		  </array>
		  <key>patterns</key>
		  <array>
		    <dict>
		      <key>match</key>
		      <string>\\b(if|else|while)\\b</string>
		      <key>name</key>
		      <string>keyword.control.test</string>
		    </dict>
		  </array>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let grammar = try GrammarDefinition.parse(dict)

		#expect(grammar.scopeName == "source.test")
		#expect(grammar.name == "Test Language")
		#expect(grammar.fileTypes == ["test", "tst"])
		#expect(grammar.patterns.count == 1)
		#expect(grammar.patterns[0].name == "keyword.control.test")
		#expect(grammar.patterns[0].match != nil)
	}

	@Test func parseGrammarWithRepository() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>scopeName</key>
		  <string>source.example</string>
		  <key>patterns</key>
		  <array>
		    <dict>
		      <key>include</key>
		      <string>#strings</string>
		    </dict>
		  </array>
		  <key>repository</key>
		  <dict>
		    <key>strings</key>
		    <dict>
		      <key>patterns</key>
		      <array>
		        <dict>
		          <key>begin</key>
		          <string>"</string>
		          <key>end</key>
		          <string>"</string>
		          <key>name</key>
		          <string>string.quoted.double</string>
		        </dict>
		      </array>
		    </dict>
		  </dict>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let grammar = try GrammarDefinition.parse(dict)

		#expect(grammar.patterns[0].include == "#strings")
		#expect(grammar.repository["strings"] != nil)
		#expect(grammar.repository["strings"]?.patterns?.count == 1)
		#expect(grammar.repository["strings"]?.patterns?[0].begin == "\"")
	}

	@Test func parseGrammarWithCaptures() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>scopeName</key>
		  <string>source.captures</string>
		  <key>patterns</key>
		  <array>
		    <dict>
		      <key>match</key>
		      <string>(func)\\s+(\\w+)</string>
		      <key>captures</key>
		      <dict>
		        <key>1</key>
		        <dict>
		          <key>name</key>
		          <string>keyword.declaration</string>
		        </dict>
		        <key>2</key>
		        <dict>
		          <key>name</key>
		          <string>entity.name.function</string>
		        </dict>
		      </dict>
		    </dict>
		  </array>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let grammar = try GrammarDefinition.parse(dict)

		let captures = grammar.patterns[0].captures
		#expect(captures != nil)
		#expect(captures?["1"]?.name == "keyword.declaration")
		#expect(captures?["2"]?.name == "entity.name.function")
	}

	@Test func missingScopeNameThrows() throws {
		let dict: [String: Any] = ["name": "No scope"]
		#expect(throws: BundlePlistParser.ParseError.self) {
			try GrammarDefinition.parse(dict)
		}
	}
}

// MARK: - Snippet Definition Tests

@Suite("SnippetDefinition")
struct SnippetDefinitionTests {
	@Test func parseSnippet() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>name</key>
		  <string>Function</string>
		  <key>tabTrigger</key>
		  <string>fun</string>
		  <key>scope</key>
		  <string>source.swift</string>
		  <key>content</key>
		  <string>func ${1:name}(${2:args}) {
		    $0
		}</string>
		  <key>uuid</key>
		  <string>ABC-123</string>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let snippet = try SnippetDefinition.parse(dict)

		#expect(snippet.name == "Function")
		#expect(snippet.tabTrigger == "fun")
		#expect(snippet.scope == "source.swift")
		#expect(snippet.uuid == "ABC-123")
		#expect(snippet.content.contains("${1:name}"))
	}

	@Test func missingContentThrows() throws {
		let dict: [String: Any] = ["name": "Bad snippet"]
		#expect(throws: BundlePlistParser.ParseError.self) {
			try SnippetDefinition.parse(dict)
		}
	}
}

// MARK: - Command Definition Tests

@Suite("CommandDefinition")
struct CommandDefinitionTests {
	@Test func parseCommand() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>name</key>
		  <string>Run Script</string>
		  <key>command</key>
		  <string>#!/bin/bash
		echo "Hello"</string>
		  <key>input</key>
		  <string>document</string>
		  <key>output</key>
		  <string>showAsTooltip</string>
		  <key>beforeRunningCommand</key>
		  <string>saveActiveFile</string>
		  <key>keyEquivalent</key>
		  <string>^⇧R</string>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let cmd = try CommandDefinition.parse(dict)

		#expect(cmd.name == "Run Script")
		#expect(cmd.command.contains("echo"))
		#expect(cmd.input == .document)
		#expect(cmd.output == .showAsTooltip)
		#expect(cmd.beforeRunning == .saveActiveFile)
		#expect(cmd.keyEquivalent == "^⇧R")
	}

	@Test func missingCommandThrows() throws {
		let dict: [String: Any] = ["name": "Bad"]
		#expect(throws: BundlePlistParser.ParseError.self) {
			try CommandDefinition.parse(dict)
		}
	}

	@Test func defaultValues() throws {
		let dict: [String: Any] = ["command": "echo hi"]
		let cmd = try CommandDefinition.parse(dict)

		#expect(cmd.name == "Untitled")
		#expect(cmd.input == .selection)
		#expect(cmd.output == .replaceSelectedText)
		#expect(cmd.beforeRunning == .nothing)
		#expect(!cmd.disableOutputAutoIndent)
	}
}

// MARK: - Preference Definition Tests

@Suite("PreferenceDefinition")
struct PreferenceDefinitionTests {
	@Test func parsePreference() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		  <key>name</key>
		  <string>Comments</string>
		  <key>scope</key>
		  <string>source.swift</string>
		  <key>uuid</key>
		  <string>UUID-456</string>
		  <key>settings</key>
		  <dict>
		    <key>shellVariables</key>
		    <array>
		      <dict>
		        <key>name</key>
		        <string>TM_COMMENT_START</string>
		        <key>value</key>
		        <string>// </string>
		      </dict>
		      <dict>
		        <key>name</key>
		        <string>TM_COMMENT_START_2</string>
		        <key>value</key>
		        <string>/* </string>
		      </dict>
		      <dict>
		        <key>name</key>
		        <string>TM_COMMENT_END_2</string>
		        <key>value</key>
		        <string> */</string>
		      </dict>
		    </array>
		    <key>increaseIndentPattern</key>
		    <string>\\{\\s*$</string>
		  </dict>
		</dict>
		</plist>
		"""
		let data = Data(xml.utf8)
		let dict = try BundlePlistParser.parse(data: data)
		let pref = try PreferenceDefinition.parse(dict)

		#expect(pref.name == "Comments")
		#expect(pref.scope == "source.swift")
		#expect(pref.uuid == "UUID-456")
		#expect(pref.settings.shellVariables.count == 3)
		#expect(pref.settings.shellVariables[0].name == "TM_COMMENT_START")
		#expect(pref.settings.shellVariables[0].value == "// ")
		#expect(pref.settings.increaseIndentPattern != nil)
		#expect(pref.settings.comment?.lineComment == "// ")
		#expect(pref.settings.comment?.blockCommentStart == "/* ")
		#expect(pref.settings.comment?.blockCommentEnd == " */")
	}

	@Test func parsePreferenceWithSmartPairs() throws {
		let dict: [String: Any] = [
			"settings": [
				"smartTypingPairs": [["(", ")"], ["{", "}"], ["\"", "\""]],
			] as [String: Any],
		]
		let pref = try PreferenceDefinition.parse(dict)
		#expect(pref.settings.smartTypingPairs?.count == 3)
		#expect(pref.settings.smartTypingPairs?[0] == ["(", ")"])
	}

	@Test func emptySettingsHandled() throws {
		let dict: [String: Any] = ["name": "Empty"]
		let pref = try PreferenceDefinition.parse(dict)
		#expect(pref.settings.shellVariables.isEmpty)
		#expect(pref.settings.smartTypingPairs == nil)
	}

	@Test func parseSymbolSettings() throws {
		let dict: [String: Any] = [
			"settings": [
				"showInSymbolList": true,
				"symbolTransformation": "s/^\\s*//;s/\\s*\\(.*//",
			] as [String: Any],
		]
		let pref = try PreferenceDefinition.parse(dict)
		#expect(pref.settings.showInSymbolList == true)
		#expect(pref.settings.symbolTransformation == "s/^\\s*//;s/\\s*\\(.*//")
	}

	@Test func symbolTransformationNotConfusedWithShowInSymbolList() throws {
		// Regression: symbolTransformation was parsed from key "showInSymbolList"
		let dict: [String: Any] = [
			"settings": [
				"showInSymbolList": true,
			] as [String: Any],
		]
		let pref = try PreferenceDefinition.parse(dict)
		#expect(pref.settings.showInSymbolList == true)
		#expect(pref.settings.symbolTransformation == nil)
	}
}
