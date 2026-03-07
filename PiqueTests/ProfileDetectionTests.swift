import XCTest
@testable import Pique

final class ProfileDetectionTests: XCTestCase {

    // MARK: - isAppleConfigProfile

    func testDDMWithAppleType() {
        let json: [String: Any] = [
            "Type": "com.apple.configuration.passcode.settings",
            "Identifier": "test-id",
            "Payload": ["minLength": 6]
        ]
        XCTAssertTrue(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    func testMDMWithPayloadContent() {
        let json: [String: Any] = [
            "PayloadContent": [
                ["PayloadType": "com.apple.wifi.managed", "SSID": "TestNetwork"]
            ]
        ]
        XCTAssertTrue(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    func testRegularJSONNotProfile() {
        let json: [String: Any] = [
            "name": "test",
            "version": 1
        ]
        XCTAssertFalse(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    func testEmptyDictNotProfile() {
        let json: [String: Any] = [:]
        XCTAssertFalse(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    func testNonAppleTypeNotProfile() {
        let json: [String: Any] = [
            "Type": "org.example.custom.profile"
        ]
        XCTAssertFalse(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    func testPayloadContentWithTypeKey() {
        let json: [String: Any] = [
            "PayloadContent": [
                ["Type": "com.apple.configuration.screensharing", "Enabled": true]
            ]
        ]
        XCTAssertTrue(SyntaxHighlighter.isAppleConfigProfile(json))
    }

    // MARK: - extractSettings

    func testDDMDeclarationExtractsPayload() {
        let json: [String: Any] = [
            "Type": "com.apple.configuration.passcode",
            "Identifier": "id-123",
            "Payload": ["minLength": 8, "requireAlphanumeric": true]
        ]
        let settings = SyntaxHighlighter.extractSettings(json)
        XCTAssertEqual(settings["minLength"] as? Int, 8)
        XCTAssertEqual(settings["requireAlphanumeric"] as? Bool, true)
        XCTAssertNil(settings["Type"])
        XCTAssertNil(settings["Identifier"])
    }

    func testManagedClientPreferencesExtractsMCX() {
        let json: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadContent": [
                "com.example.app": [
                    "Forced": [
                        ["mcx_preference_settings": ["key1": "val1", "key2": 42]]
                    ]
                ]
            ]
        ]
        let settings = SyntaxHighlighter.extractSettings(json)
        XCTAssertEqual(settings["key1"] as? String, "val1")
        XCTAssertEqual(settings["key2"] as? Int, 42)
    }

    func testStandardPayloadFiltersMetaKeys() {
        let json: [String: Any] = [
            "PayloadType": "com.apple.wifi.managed",
            "PayloadVersion": 1,
            "PayloadUUID": "abc-123",
            "PayloadIdentifier": "com.example.wifi",
            "SSID_STR": "MyNetwork",
            "EncryptionType": "WPA2"
        ]
        let settings = SyntaxHighlighter.extractSettings(json)
        XCTAssertNil(settings["PayloadType"])
        XCTAssertNil(settings["PayloadVersion"])
        XCTAssertNil(settings["PayloadUUID"])
        XCTAssertNil(settings["PayloadIdentifier"])
        XCTAssertEqual(settings["SSID_STR"] as? String, "MyNetwork")
        XCTAssertEqual(settings["EncryptionType"] as? String, "WPA2")
    }

    func testExtractSettingsFiltersPayloadContentKey() {
        let json: [String: Any] = [
            "PayloadType": "com.apple.wifi.managed",
            "PayloadContent": "should-be-filtered",
            "SSID_STR": "MyNetwork"
        ]
        let settings = SyntaxHighlighter.extractSettings(json)
        XCTAssertNil(settings["PayloadContent"], "PayloadContent key should be filtered out")
        XCTAssertEqual(settings["SSID_STR"] as? String, "MyNetwork")
    }

    func testPayloadWithNoSettingsReturnsEmpty() {
        let json: [String: Any] = [
            "PayloadType": "com.apple.wifi.managed",
            "PayloadVersion": 1,
            "PayloadUUID": "abc-123",
            "PayloadIdentifier": "com.example.wifi",
            "PayloadDisplayName": "WiFi",
            "PayloadDescription": "desc",
            "PayloadOrganization": "org",
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": true,
            "PayloadEnabled": true
        ]
        let settings = SyntaxHighlighter.extractSettings(json)
        XCTAssertTrue(settings.isEmpty)
    }
}
