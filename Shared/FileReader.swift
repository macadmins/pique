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
