import Foundation
import Security
import XCTest
@testable import RyddiProtectAuth
import RyddiProtectCore

final class ProviderCredentialStoreTests: XCTestCase {
    private let namespace = "com.reidar.ryddi.tests.credentials"
    private let connectionID = UUID(uuidString: "7818380F-2805-49A0-9557-B17BFB26E221")!

    func testSaveCreatesDataProtectionItemScopedOnlyByProviderAndConnectionUUID() throws {
        let backend = RecordingKeychainBackend()
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)
        let credential = try ProviderCredential(Data("opaque-session-material".utf8))

        try store.save(credential, provider: .googleDrive, connectionID: connectionID)

        let query = try XCTUnwrap(backend.addQueries.only)
        XCTAssertEqual(query[string: kSecClass], kSecClassGenericPassword as String)
        XCTAssertEqual(query[string: kSecAttrService], "\(namespace).googleDrive")
        XCTAssertEqual(query[string: kSecAttrAccount], connectionID.uuidString.lowercased())
        XCTAssertEqual(query[bool: kSecUseDataProtectionKeychain], true)
        XCTAssertEqual(
            query[string: kSecAttrAccessible],
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(query[data: kSecValueData], Data("opaque-session-material".utf8))
        XCTAssertNil(query[kSecAttrSynchronizable as String])
        XCTAssertEqual(query[data: kSecAttrGeneric], Data("1".utf8))
        XCTAssertTrue(backend.updateCalls.isEmpty)
    }

    func testSaveAndRediscoverNonSensitiveConnectionLocatorAcrossStoreInstances() throws {
        let backend = RecordingKeychainBackend()
        let firstStore = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)
        let locator = try CloudConnectionLocator(id: connectionID, provider: .mega, ordinal: 7)
        try firstStore.save(
            ProviderCredential(Data("restart-safe-session".utf8)),
            connection: locator
        )
        backend.copyStatuses = [errSecItemNotFound, errSecItemNotFound, errSecSuccess]
        backend.copyResults = [
            nil,
            nil,
            [
                kSecAttrAccount as String: connectionID.uuidString.lowercased(),
                kSecAttrGeneric as String: Data("7".utf8)
            ] as NSDictionary
        ]

        let relaunchedStore = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)
        let rediscovered = try relaunchedStore.listConnectionLocators()

        XCTAssertEqual(rediscovered, [locator])
        XCTAssertEqual(backend.copyQueries.count, CloudProviderKind.allCases.count)
        for query in backend.copyQueries {
            XCTAssertEqual(query[bool: kSecUseDataProtectionKeychain], true)
            XCTAssertEqual(query[bool: kSecReturnAttributes], true)
            XCTAssertEqual(query[string: kSecMatchLimit], kSecMatchLimitAll as String)
            XCTAssertNil(query[kSecReturnData as String])
            XCTAssertNil(query[kSecAttrSynchronizable as String])
        }
    }

    func testProtocolSavePreservesConnectionLocatorOrdinal() throws {
        let backend = RecordingKeychainBackend()
        let store: any ProviderCredentialStoring = ProviderCredentialStore(
            serviceNamespace: namespace,
            backend: backend
        )
        let locator = try CloudConnectionLocator(id: connectionID, provider: .dropbox, ordinal: 9)

        try store.save(
            ProviderCredential(Data("protocol-session".utf8)),
            connection: locator
        )

        let query = try XCTUnwrap(backend.addQueries.only)
        XCTAssertEqual(query[string: kSecAttrService], "\(namespace).dropbox")
        XCTAssertEqual(query[string: kSecAttrAccount], connectionID.uuidString.lowercased())
        XCTAssertEqual(query[data: kSecAttrGeneric], Data("9".utf8))
    }

    func testConnectionDiscoveryRejectsMalformedLocatorMetadata() throws {
        let backend = RecordingKeychainBackend()
        backend.copyStatuses = [errSecSuccess]
        backend.copyResults = [[
            kSecAttrAccount as String: "not-a-uuid",
            kSecAttrGeneric as String: Data("1".utf8)
        ] as NSDictionary]
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        XCTAssertThrowsError(try store.listConnectionLocators()) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, .invalidStoredConnection)
        }
    }

    func testSaveUpdatesDuplicateItemWithoutWeakeningProtectionAttributes() throws {
        let backend = RecordingKeychainBackend()
        backend.addStatuses = [errSecDuplicateItem]
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)
        let replacement = try ProviderCredential(Data("replacement-session".utf8))

        try store.save(replacement, provider: .dropbox, connectionID: connectionID)

        let update = try XCTUnwrap(backend.updateCalls.only)
        XCTAssertEqual(update.query[string: kSecAttrService], "\(namespace).dropbox")
        XCTAssertEqual(update.query[string: kSecAttrAccount], connectionID.uuidString.lowercased())
        XCTAssertEqual(update.query[bool: kSecUseDataProtectionKeychain], true)
        XCTAssertNil(update.query[kSecAttrSynchronizable as String])
        XCTAssertEqual(
            update.attributes[string: kSecAttrAccessible],
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(update.attributes[data: kSecValueData], Data("replacement-session".utf8))
        XCTAssertNil(update.attributes[kSecAttrSynchronizable as String])
    }

    func testLoadReturnsOpaqueCredentialUsingDataProtectionQuery() throws {
        let backend = RecordingKeychainBackend()
        backend.copyResult = Data("loaded-session".utf8) as NSData
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        let credential = try XCTUnwrap(store.load(provider: .mega, connectionID: connectionID))

        XCTAssertEqual(credential.withBytes { $0 }, Data("loaded-session".utf8))
        XCTAssertEqual(String(describing: credential), "<redacted provider credential>")
        let query = try XCTUnwrap(backend.copyQueries.only)
        XCTAssertEqual(query[string: kSecAttrService], "\(namespace).mega")
        XCTAssertEqual(query[string: kSecAttrAccount], connectionID.uuidString.lowercased())
        XCTAssertEqual(query[bool: kSecUseDataProtectionKeychain], true)
        XCTAssertEqual(query[bool: kSecReturnData], true)
        XCTAssertEqual(query[string: kSecMatchLimit], kSecMatchLimitOne as String)
        XCTAssertNil(query[kSecAttrSynchronizable as String])
    }

    func testMissingCredentialLoadsAsNilAndDeleteIsIdempotent() throws {
        let backend = RecordingKeychainBackend()
        backend.copyStatuses = [errSecItemNotFound]
        backend.deleteStatuses = [errSecItemNotFound, errSecSuccess]
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        XCTAssertNil(try store.load(provider: .dropbox, connectionID: connectionID))
        XCTAssertFalse(try store.delete(provider: .dropbox, connectionID: connectionID))
        XCTAssertTrue(try store.delete(provider: .dropbox, connectionID: connectionID))

        XCTAssertEqual(backend.deleteQueries.count, 2)
        for query in backend.deleteQueries {
            XCTAssertEqual(query[bool: kSecUseDataProtectionKeychain], true)
            XCTAssertNil(query[kSecAttrSynchronizable as String])
        }
    }

    func testKnownSecurityStatusesHaveStableErrorMapping() throws {
        try assertLoadStatus(
            errSecInteractionNotAllowed,
            mapsTo: .keychainLocked(operation: .load)
        )
        try assertLoadStatus(
            errSecNotAvailable,
            mapsTo: .keychainUnavailable(operation: .load)
        )
        try assertLoadStatus(
            errSecMissingEntitlement,
            mapsTo: .accessDenied(operation: .load)
        )
        try assertLoadStatus(
            errSecUserCanceled,
            mapsTo: .operationCancelled(operation: .load)
        )
        try assertLoadStatus(
            errSecParam,
            mapsTo: .invalidRequest(operation: .load)
        )
        try assertLoadStatus(errSecDecode, mapsTo: .invalidStoredCredential)
    }

    func testUnexpectedSecurityStatusPreservesOperationAndStatusWithoutCredentialContext() throws {
        let backend = RecordingKeychainBackend()
        backend.deleteStatuses = [-42_424]
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        XCTAssertThrowsError(try store.delete(provider: .mega, connectionID: connectionID)) { error in
            guard case .unexpectedStatus(let operation, let status, let message) = error as? ProviderCredentialStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(operation, .delete)
            XCTAssertEqual(status, -42_424)
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains(connectionID.uuidString))
        }
    }

    func testSuccessfulLoadRejectsEmptyOrUnexpectedResult() throws {
        let backend = RecordingKeychainBackend()
        backend.copyResult = "not credential data" as NSString
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        XCTAssertThrowsError(try store.load(provider: .dropbox, connectionID: connectionID)) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, .invalidStoredCredential)
        }
        XCTAssertThrowsError(try ProviderCredential(Data())) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, .emptyCredential)
        }
        XCTAssertThrowsError(try ProviderCredential(
            Data(repeating: 0x41, count: ProviderCredential.maximumByteCount + 1)
        )) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, .credentialTooLarge)
        }

        backend.copyResult = Data(
            repeating: 0x41,
            count: ProviderCredential.maximumByteCount + 1
        ) as NSData
        XCTAssertThrowsError(try store.load(provider: .dropbox, connectionID: connectionID)) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, .invalidStoredCredential)
        }
    }

    func testLockedKeychainErrorUsesTheActualOperationName() {
        let error = ProviderCredentialStoreError.keychainLocked(operation: .load)
        XCTAssertEqual(
            error.errorDescription,
            "The provider credential could not be loaded because the Keychain is locked."
        )
    }

    func testStoreProtocolCanBeReplacedWithoutSecurityFrameworkBackend() throws {
        let expected = try ProviderCredential(Data("fixture".utf8))
        let store: any ProviderCredentialStoring = FakeProviderCredentialStore(credential: expected)

        let loaded = try XCTUnwrap(store.load(provider: .dropbox, connectionID: connectionID))
        XCTAssertEqual(loaded.withBytes { $0 }, Data("fixture".utf8))
    }

    private func assertLoadStatus(
        _ status: OSStatus,
        mapsTo expected: ProviderCredentialStoreError
    ) throws {
        let backend = RecordingKeychainBackend()
        backend.copyStatuses = [status]
        let store = ProviderCredentialStore(serviceNamespace: namespace, backend: backend)

        XCTAssertThrowsError(try store.load(provider: .dropbox, connectionID: connectionID)) { error in
            XCTAssertEqual(error as? ProviderCredentialStoreError, expected)
        }
    }
}

private final class RecordingKeychainBackend: ProviderCredentialKeychainBackend, @unchecked Sendable {
    var copyStatuses: [OSStatus] = []
    var addStatuses: [OSStatus] = []
    var updateStatuses: [OSStatus] = []
    var deleteStatuses: [OSStatus] = []
    var copyResult: CFTypeRef?
    var copyResults: [CFTypeRef?] = []

    private(set) var copyQueries: [[String: Any]] = []
    private(set) var addQueries: [[String: Any]] = []
    private(set) var updateCalls: [(query: [String: Any], attributes: [String: Any])] = []
    private(set) var deleteQueries: [[String: Any]] = []

    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus {
        copyQueries.append(swiftDictionary(query))
        result = copyResults.isEmpty ? copyResult : copyResults.removeFirst()
        return copyStatuses.isEmpty ? errSecSuccess : copyStatuses.removeFirst()
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        addQueries.append(swiftDictionary(attributes))
        return addStatuses.isEmpty ? errSecSuccess : addStatuses.removeFirst()
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        updateCalls.append((swiftDictionary(query), swiftDictionary(attributes)))
        return updateStatuses.isEmpty ? errSecSuccess : updateStatuses.removeFirst()
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        deleteQueries.append(swiftDictionary(query))
        return deleteStatuses.isEmpty ? errSecSuccess : deleteStatuses.removeFirst()
    }

    private func swiftDictionary(_ dictionary: CFDictionary) -> [String: Any] {
        (dictionary as NSDictionary) as? [String: Any] ?? [:]
    }
}

private struct FakeProviderCredentialStore: ProviderCredentialStoring {
    let credential: ProviderCredential

    func listConnectionLocators() throws -> [CloudConnectionLocator] {
        []
    }

    func load(provider _: CloudProviderKind, connectionID _: UUID) throws -> ProviderCredential? {
        credential
    }

    func save(
        _: ProviderCredential,
        connection _: CloudConnectionLocator
    ) throws {}

    func delete(provider _: CloudProviderKind, connectionID _: UUID) throws -> Bool {
        true
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    subscript(string key: CFString) -> String? {
        self[key as String] as? String
    }

    subscript(bool key: CFString) -> Bool? {
        self[key as String] as? Bool
    }

    subscript(data key: CFString) -> Data? {
        self[key as String] as? Data
    }
}
