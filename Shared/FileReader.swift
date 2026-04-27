//  FileReader.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import Foundation
import Security

enum FileReader {
    static let maxFileSize: UInt64 = 10_000_000  // 10 MB

    // MARK: - Core reading

    static func readData(url: URL) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        let size = attrs[.size] as? UInt64 ?? 0
        guard size <= maxFileSize else {
            throw FileReaderError.fileTooLarge(size)
        }
        return try Data(contentsOf: url)
    }

    static func read(url: URL) throws -> String {
        let data = try readData(url: url)
        return decodeToString(data)
    }

    static func decodeToString(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - CMS signature striping

    static func isCMSEnvelope(_ data: Data) -> Bool {
        // PKCS#7 signedData OID: 1.2.840.113549.1.7.2
        let oid: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02]
        guard data.count > 20 else { return false }
        return data.prefix(20).range(of: Data(oid)) != nil
    }

    static func stripCMSSignature(from data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        let update = data.withUnsafeBytes {
            CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count)
        }
        guard update == errSecSuccess else { return nil }
        guard CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else {
            return nil
        }
        return content as Data
    }

    // MARK: - Binary plist conversion

    static func isBinaryPlist(_ data: Data) -> Bool {
        data.starts(with: [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74])  // "bplist"
    }

    static func convertBinaryPlistToXMLString(_ data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            )
        else { return nil }
        guard
            let xmlData = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
        else { return nil }
        return String(data: xmlData, encoding: .utf8)
    }

    // MARK: - VPP / Apps & Books service token

    /// Metadata extracted from a `.vpptoken` file for use in the preview banner.
    struct VPPTokenInfo {
        let expDate: Date?
        let orgName: String?
    }

    /// Returns the parsed expiration date and org name from a base64-wrapped VPP token.
    /// Returns nil if the file is not a valid token envelope.
    static func vppTokenInfo(_ data: Data) -> VPPTokenInfo? {
        let trimmed = decodeToString(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let object = try? JSONSerialization.jsonObject(with: decoded),
              let dict = object as? [String: Any]
        else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let exp = (dict["expDate"] as? String).flatMap(formatter.date(from:))
        let org = dict["orgName"] as? String
        return VPPTokenInfo(expDate: exp, orgName: org)
    }

    /// Decodes a base64-wrapped VPP service token to pretty-printed JSON.
    static func decodeVPPToken(_ data: Data) -> String? {
        let trimmed = decodeToString(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let object = try? JSONSerialization.jsonObject(with: decoded)
        else { return nil }

        guard let pretty = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    // MARK: - AutoPkg recipe (XML plist → YAML)

    /// Parses an XML plist recipe and emits a YAML representation for preview.
    /// Returns nil when the data isn't a valid plist.
    static func convertRecipeToYAMLString(_ data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return YAMLEmitter.emit(plist, recipe: true)
    }

    enum FileReaderError: LocalizedError {
        case fileTooLarge(UInt64)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let size):
                let mb = Double(size) / 1_000_000
                return String(format: "File too large (%.1f MB). Maximum is 10 MB.", mb)
            }
        }
    }
}

// MARK: - YAML emitter

/// Emits a Foundation property list (`[String: Any]`, `[Any]`, `String`, `NSNumber`, `Date`, `Data`)
/// as YAML 1.2 text. Tailored for AutoPkg recipe presentation: literal block scalars for multi-line
/// strings, AutoPkg-canonical key order for the top-level recipe dict, and stable alphabetical
/// ordering elsewhere.
enum YAMLEmitter {
    /// Top-level keys appear in this order when `recipe` is true. Anything not listed
    /// falls through to alphabetical order.
    static let recipeKeyOrder = [
        "Description", "Identifier", "ParentRecipe", "MinimumVersion", "Input", "Process"
    ]

    static func emit(_ root: Any, recipe: Bool = false) -> String {
        var out = ""
        write(root, indent: 0, leadOnSameLine: false, recipeRoot: recipe, into: &out)
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    private static func write(_ value: Any, indent: Int, leadOnSameLine: Bool, recipeRoot: Bool, into out: inout String) {
        switch value {
        case let dict as [String: Any]:
            writeDict(dict, indent: indent, leadOnSameLine: leadOnSameLine, recipeRoot: recipeRoot, into: &out)
        case let arr as [Any]:
            writeArray(arr, indent: indent, into: &out)
        case let str as String:
            writeString(str, indent: indent, into: &out)
        case let num as NSNumber:
            writeNumber(num, into: &out)
        case let date as Date:
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            out += fmt.string(from: date)
        case let data as Data:
            out += "!!binary " + data.base64EncodedString()
        default:
            out += "null"
        }
    }

    private static func writeDict(_ dict: [String: Any], indent: Int, leadOnSameLine: Bool, recipeRoot: Bool, into out: inout String) {
        if dict.isEmpty {
            out += "{}\n"
            return
        }
        let pad = String(repeating: "  ", count: indent)
        let keys = orderedKeys(Array(dict.keys), preferredFirst: recipeRoot ? recipeKeyOrder : [])
        for (i, key) in keys.enumerated() {
            let keyPrefix = (i == 0 && leadOnSameLine) ? "" : pad
            let keyStr = formatScalarKey(key)
            let value = dict[key]!
            if let str = value as? String, str.contains("\n") {
                out += "\(keyPrefix)\(keyStr): "
                writeString(str, indent: indent + 1, into: &out)
            } else if isInlineScalar(value) {
                out += "\(keyPrefix)\(keyStr): "
                write(value, indent: indent + 1, leadOnSameLine: false, recipeRoot: false, into: &out)
                out += "\n"
            } else if let arr = value as? [Any], arr.isEmpty {
                out += "\(keyPrefix)\(keyStr): []\n"
            } else if let d = value as? [String: Any], d.isEmpty {
                out += "\(keyPrefix)\(keyStr): {}\n"
            } else {
                out += "\(keyPrefix)\(keyStr):\n"
                write(value, indent: indent + 1, leadOnSameLine: false, recipeRoot: false, into: &out)
            }
        }
    }

    private static func writeArray(_ arr: [Any], indent: Int, into out: inout String) {
        if arr.isEmpty {
            out += String(repeating: "  ", count: indent) + "[]\n"
            return
        }
        let pad = String(repeating: "  ", count: indent)
        for item in arr {
            if let dict = item as? [String: Any], !dict.isEmpty {
                out += "\(pad)- "
                writeDict(dict, indent: indent + 1, leadOnSameLine: true, recipeRoot: false, into: &out)
            } else if isInlineScalar(item) {
                out += "\(pad)- "
                write(item, indent: indent + 1, leadOnSameLine: false, recipeRoot: false, into: &out)
                out += "\n"
            } else {
                out += "\(pad)-\n"
                write(item, indent: indent + 1, leadOnSameLine: false, recipeRoot: false, into: &out)
            }
        }
    }

    /// Multi-line strings render as a `|-` literal block scalar (preserves newlines, strips
    /// trailing blank lines). Single-line strings render plain unless they need quoting.
    private static func writeString(_ str: String, indent: Int, into out: inout String) {
        if str.contains("\n") {
            let pad = String(repeating: "  ", count: indent)
            out += "|-\n"
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                out += line.isEmpty ? "\n" : "\(pad)\(line)\n"
            }
            return
        }
        if needsQuoting(str) {
            out += "\"\(escapeForDoubleQuoted(str))\""
        } else {
            out += str
        }
    }

    private static func writeNumber(_ num: NSNumber, into out: inout String) {
        if CFGetTypeID(num) == CFBooleanGetTypeID() {
            out += num.boolValue ? "true" : "false"
        } else {
            out += "\(num)"
        }
    }

    private static func formatScalarKey(_ key: String) -> String {
        needsQuoting(key) ? "\"\(escapeForDoubleQuoted(key))\"" : key
    }

    private static func isInlineScalar(_ v: Any) -> Bool {
        switch v {
        case is NSNumber, is Date, is Data: return true
        case let s as String: return !s.contains("\n")
        default: return false
        }
    }

    /// Strings matching YAML reserved tokens, looking like numbers, or containing
    /// structural characters need double-quoting to round-trip correctly.
    private static func needsQuoting(_ str: String) -> Bool {
        if str.isEmpty { return true }
        if let first = str.first, "!&*-?{[}]|>%@`#,\"'".contains(first) { return true }
        if str.first?.isWhitespace == true || str.last?.isWhitespace == true { return true }
        if str.contains(": ") || str.contains(" #") { return true }
        let reserved = #"^(true|false|yes|no|on|off|null|~|-?\d+(\.\d+)?([eE][+-]?\d+)?)$"#
        if str.range(of: reserved, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private static func escapeForDoubleQuoted(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
           .replacingOccurrences(of: "\n", with: "\\n")
           .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func orderedKeys(_ keys: [String], preferredFirst: [String]) -> [String] {
        let keySet = Set(keys)
        let preferred = preferredFirst.filter { keySet.contains($0) }
        let remaining = keys.filter { !preferred.contains($0) }.sorted()
        return preferred + remaining
    }
}
