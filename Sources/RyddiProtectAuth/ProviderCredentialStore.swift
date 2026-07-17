import Foundation
import RyddiProtectCore
import Security

/// Opaque provider session material. It intentionally has no persistence conformance.
public struct ProviderCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumByteCount = 65_536

    fileprivate let bytes: Data

    public init(_ bytes: Data) throws {
        guard !bytes.isEmpty else {
            throw ProviderCredentialStoreError.emptyCredential
        }
        guard bytes.count <= Self.maximumByteCount else {
            throw ProviderCredentialStoreError.credentialTooLarge
        }
        self.bytes = bytes
    }

    public func withBytes<Result>(_ body: (Data) throws -> Result) rethrows -> Result {
        try body(bytes)
    }

    public var description: String { "<redacted provider credential>" }
    public var debugDescription: String { description }
}

public enum ProviderCredentialStoreOperation: String, Equatable, Sendable {
    case list
    case load
    case save
    case delete
}

public enum ProviderCredentialStoreError: Error, Equatable, Sendable {
    case emptyCredential
    case credentialTooLarge
    case keychainLocked(operation: ProviderCredentialStoreOperation)
    case keychainUnavailable(operation: ProviderCredentialStoreOperation)
    case accessDenied(operation: ProviderCredentialStoreOperation)
    case operationCancelled(operation: ProviderCredentialStoreOperation)
    case invalidRequest(operation: ProviderCredentialStoreOperation)
    case invalidStoredCredential
    case invalidStoredConnection
    case unexpectedStatus(operation: ProviderCredentialStoreOperation, status: Int32, message: String)
}

extension ProviderCredentialStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyCredential:
            "An empty provider credential cannot be stored."
        case .credentialTooLarge:
            "The provider credential exceeds the bounded storage limit."
        case .keychainLocked(let operation):
            "The provider credential could not be \(operation.pastTense) because the Keychain is locked."
        case .keychainUnavailable(let operation):
            "The provider credential could not be \(operation.pastTense) because the Keychain is unavailable."
        case .accessDenied(let operation):
            "The provider credential could not be \(operation.pastTense) because Keychain access was denied."
        case .operationCancelled(let operation):
            "The Keychain \(operation.rawValue) operation was cancelled."
        case .invalidRequest(let operation):
            "The Keychain rejected the provider credential \(operation.rawValue) request."
        case .invalidStoredCredential:
            "The stored provider credential is empty or has an unexpected format."
        case .invalidStoredConnection:
            "A stored provider connection has invalid locator metadata."
        case .unexpectedStatus(let operation, let status, let message):
            "The Keychain \(operation.rawValue) operation failed with status \(status): \(message)"
        }
    }
}

private extension ProviderCredentialStoreOperation {
    var pastTense: String {
        switch self {
        case .list: "listed"
        case .load: "loaded"
        case .save: "saved"
        case .delete: "deleted"
        }
    }
}

public protocol ProviderCredentialStoring: Sendable {
    func listConnectionLocators() throws -> [CloudConnectionLocator]
    func load(provider: CloudProviderKind, connectionID: UUID) throws -> ProviderCredential?
    func save(_ credential: ProviderCredential, connection: CloudConnectionLocator) throws

    @discardableResult
    func delete(provider: CloudProviderKind, connectionID: UUID) throws -> Bool
}

public extension ProviderCredentialStoring {
    func save(
        _ credential: ProviderCredential,
        provider: CloudProviderKind,
        connectionID: UUID
    ) throws {
        try save(
            credential,
            connection: CloudConnectionLocator(
                id: connectionID,
                provider: provider,
                ordinal: 1
            )
        )
    }
}

public struct ProviderCredentialStore: ProviderCredentialStoring, Sendable {
    public static let serviceNamespace = "com.reidar.ryddi.protect.credentials"

    private let serviceNamespace: String
    private let backend: any ProviderCredentialKeychainBackend

    public init() {
        self.init(
            serviceNamespace: Self.serviceNamespace,
            backend: SecurityFrameworkProviderCredentialBackend()
        )
    }

    init(
        serviceNamespace: String = ProviderCredentialStore.serviceNamespace,
        backend: any ProviderCredentialKeychainBackend
    ) {
        precondition(!serviceNamespace.isEmpty)
        self.serviceNamespace = serviceNamespace
        self.backend = backend
    }

    public func load(provider: CloudProviderKind, connectionID: UUID) throws -> ProviderCredential? {
        var query = itemQuery(provider: provider, connectionID: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = backend.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound {
            return nil
        }
        try Self.requireSuccess(status, operation: .load)

        guard let bytes = result as? Data,
              !bytes.isEmpty,
              bytes.count <= ProviderCredential.maximumByteCount else {
            throw ProviderCredentialStoreError.invalidStoredCredential
        }
        return try ProviderCredential(bytes)
    }

    public func save(_ credential: ProviderCredential, connection: CloudConnectionLocator) throws {
        var addQuery = itemQuery(provider: connection.provider, connectionID: connection.id)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecAttrGeneric as String] = Self.ordinalData(connection.ordinal)
        addQuery[kSecValueData as String] = credential.bytes

        let addStatus = backend.add(addQuery as CFDictionary)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw Self.error(for: addStatus, operation: .save)
        }

        let updateAttributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrGeneric as String: Self.ordinalData(connection.ordinal),
            kSecValueData as String: credential.bytes
        ]
        let updateStatus = backend.update(
            itemQuery(provider: connection.provider, connectionID: connection.id) as CFDictionary,
            attributes: updateAttributes as CFDictionary
        )
        try Self.requireSuccess(updateStatus, operation: .save)
    }

    public func listConnectionLocators() throws -> [CloudConnectionLocator] {
        var locators = [CloudConnectionLocator]()
        for provider in CloudProviderKind.allCases {
            var query = providerQuery(provider: provider)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitAll

            var result: CFTypeRef?
            let status = backend.copyMatching(query as CFDictionary, result: &result)
            if status == errSecItemNotFound {
                continue
            }
            try Self.requireSuccess(status, operation: .list)

            let dictionaries: [[String: Any]]
            if let array = result as? [[String: Any]] {
                dictionaries = array
            } else if let dictionary = result as? [String: Any] {
                dictionaries = [dictionary]
            } else {
                throw ProviderCredentialStoreError.invalidStoredConnection
            }
            for dictionary in dictionaries {
                guard let account = dictionary[kSecAttrAccount as String] as? String,
                      let connectionID = UUID(uuidString: account),
                      let ordinalData = dictionary[kSecAttrGeneric as String] as? Data,
                      let ordinalText = String(data: ordinalData, encoding: .utf8),
                      let ordinal = Int(ordinalText),
                      let locator = try? CloudConnectionLocator(
                          id: connectionID,
                          provider: provider,
                          ordinal: ordinal
                      ) else {
                    throw ProviderCredentialStoreError.invalidStoredConnection
                }
                locators.append(locator)
            }
        }
        return locators.sorted {
            if $0.provider == $1.provider {
                if $0.ordinal == $1.ordinal { return $0.id.uuidString < $1.id.uuidString }
                return $0.ordinal < $1.ordinal
            }
            return $0.provider.rawValue < $1.provider.rawValue
        }
    }

    @discardableResult
    public func delete(provider: CloudProviderKind, connectionID: UUID) throws -> Bool {
        let status = backend.delete(itemQuery(provider: provider, connectionID: connectionID) as CFDictionary)
        if status == errSecItemNotFound {
            return false
        }
        try Self.requireSuccess(status, operation: .delete)
        return true
    }

    private func itemQuery(provider: CloudProviderKind, connectionID: UUID) -> [String: Any] {
        var query = providerQuery(provider: provider)
        query[kSecAttrAccount as String] = connectionID.uuidString.lowercased()
        return query
    }

    private func providerQuery(provider: CloudProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(serviceNamespace).\(provider.rawValue)",
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private static func ordinalData(_ ordinal: Int) -> Data {
        Data(String(ordinal).utf8)
    }

    private static func requireSuccess(
        _ status: OSStatus,
        operation: ProviderCredentialStoreOperation
    ) throws {
        guard status == errSecSuccess else {
            throw error(for: status, operation: operation)
        }
    }

    private static func error(
        for status: OSStatus,
        operation: ProviderCredentialStoreOperation
    ) -> ProviderCredentialStoreError {
        switch status {
        case errSecInteractionNotAllowed:
            .keychainLocked(operation: operation)
        case errSecNotAvailable:
            .keychainUnavailable(operation: operation)
        case errSecAuthFailed, errSecMissingEntitlement:
            .accessDenied(operation: operation)
        case errSecUserCanceled:
            .operationCancelled(operation: operation)
        case errSecParam:
            .invalidRequest(operation: operation)
        case errSecDecode:
            .invalidStoredCredential
        default:
            .unexpectedStatus(
                operation: operation,
                status: status,
                message: securityMessage(for: status)
            )
        }
    }

    private static func securityMessage(for status: OSStatus) -> String {
        guard let message = SecCopyErrorMessageString(status, nil) else {
            return "Unknown Security.framework error"
        }
        return message as String
    }
}

protocol ProviderCredentialKeychainBackend: Sendable {
    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct SecurityFrameworkProviderCredentialBackend: ProviderCredentialKeychainBackend {
    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus {
        SecItemCopyMatching(query, &result)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}
