import Foundation
import XCTest

final class SettingsLocalizationTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func translations() throws -> [String: String] {
        let url = repository.appendingPathComponent("Octoshot/zh-Hans.lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func matches(_ pattern: String, in source: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        }
    }

    func testEveryAppLocalizationKeyHasSimplifiedChineseTranslation() throws {
        let table = try translations()
        let app = repository.appendingPathComponent("Octoshot")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        let unchangedTechnicalNames: Set<String> = ["AI", "LaTeX", "Agent / CLI"]
        var checked = Set<String>()
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let prefix = file.lastPathComponent == "OctoshotL10n.swift" ? #"(?:OctoshotL10n\.)?"# : #"OctoshotL10n\."#
            let keys = try matches(prefix + #"(?:text|format)\(\s*"((?:\\.|[^"\\])*)""#, in: source)
                + matches(#"String\(\s*localized:\s*"((?:\\.|[^"\\])*)""#, in: source)
            for escaped in keys {
                let entry = Data("\"\(escaped)\" = \"\(escaped)\";".utf8)
                let parsed = try XCTUnwrap(PropertyListSerialization.propertyList(from: entry, format: nil) as? [String: String])
                let key = try XCTUnwrap(parsed.keys.first)
                checked.insert(key)
                let translated = try XCTUnwrap(table[key], "Missing zh-Hans key in \(file.lastPathComponent): \(key)")
                XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                if !unchangedTechnicalNames.contains(key) {
                    XCTAssertNotEqual(translated, key, "Untranslated key: \(key)")
                }
                let specifiers = #"(%(?:\d+\$)?[@df])"#
                XCTAssertEqual(try matches(specifiers, in: key).sorted(),
                               try matches(specifiers, in: translated).sorted(),
                               "Format arguments must be preserved: \(key)")
            }
        }
        XCTAssertGreaterThan(checked.count, 200, "The scanner must cover Settings and the shared localization catalog")
    }

    func testSettingsLabelsDoNotBypassLocalization() throws {
        let folder = repository.appendingPathComponent("Octoshot/Preferences")
        let numericUnits: Set<String> = [
            #"\(Int(speculativeThresholdBinding.wrappedValue * 100))%"#,
            #"\(Int(settings.gifFPS)) fps"#
        ]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension == "swift" && !file.lastPathComponent.hasPrefix("AppSettings") {
            let source = try String(contentsOf: file, encoding: .utf8)
            let literals = try matches(#"(?:Text|Toggle|Button|Picker|Label|TextField|SecureField|Section|help|accessibilityLabel)\(\s*(?:verbatim:\s*)?"([^"\n]*)""#, in: source)
                + matches(#"(?:title|subtitle):\s*"([^"\n]*)""#, in: source)
            for literal in literals {
                XCTAssertTrue(numericUnits.contains(literal),
                              "Localize Settings UI literals explicitly in \(file.lastPathComponent): \(literal)")
            }
            XCTAssertTrue(try matches(#"Text\(([^)\n]*\.rawValue)"#, in: source).isEmpty,
                          "Do not display unlocalized enum raw values in \(file.lastPathComponent)")
        }
    }
}
