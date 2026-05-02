//
//  SparkleClientCredentials.swift
//  leanring-buddy
//
//  Manages a per-install bearer token used to authenticate every request to
//  the Sparkle Cloudflare Worker. The token is generated locally on first
//  launch (or first call), stored in the macOS Keychain, and read back on
//  subsequent launches. The Worker validates the token format, then keys
//  per-install daily rate limits off the token so a single client cannot
//  drain the proxy's API budget.
//
//  The token does NOT prove identity — it's a TOFU (trust on first use)
//  credential whose only job is to give the Worker a stable, per-install
//  handle for rate limiting and to filter out casual probes that don't
//  send any auth header at all. For real attestation we'd need Apple's
//  App Attest, which is heavier and out of scope here.
//

import Foundation
import Security

/// Singleton accessor for the Sparkle client bearer token. The token is
/// generated once per install and persisted in the Keychain; subsequent
/// reads return the cached value. Never logs the raw token — only a short
/// prefix is printed for diagnostics.
final class SparkleClientCredentials {
    static let shared = SparkleClientCredentials()

    /// Wire-format prefix the Worker uses to recognize Sparkle-issued tokens.
    /// Bumping the version (v1 → v2) lets us roll out a new generation if a
    /// build leaks. The Worker rejects anything that doesn't start with the
    /// active prefix, so old builds with old tokens stop working immediately.
    private static let tokenVersionPrefix = "sparkle_v1_"

    /// Number of random bytes we hex-encode into the token suffix. 32 bytes
    /// (256 bits) is more than enough entropy to make tokens unguessable.
    private static let tokenRandomByteCount = 32

    /// Keychain service identifier. Namespaced to the app's bundle ID so
    /// multiple Sparkle-style apps on the same machine never collide.
    private static let keychainService = "com.vibecademy.app.client-credentials"

    /// Keychain account identifier. We only ever store one credential, so a
    /// fixed account name is enough.
    private static let keychainAccount = "default"

    /// Cached token value so we don't hit the Keychain on every API call.
    private var cachedClientToken: String?

    /// Lock guarding the cache + Keychain interaction. Reads/writes can come
    /// from any actor (the Claude API runs off-main, AssemblyAI shares a
    /// background URLSession), so we serialize access here.
    private let cacheLock = NSLock()

    private init() {}

    /// Returns the current bearer token, generating and persisting one on
    /// first call if no token exists yet. Synchronous — Keychain access is
    /// fast (single-digit milliseconds) and this is called per HTTP request,
    /// so making it async would add complexity without measurable benefit.
    var currentClientToken: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cachedClientToken {
            return cachedClientToken
        }

        if let storedClientToken = readClientTokenFromKeychain() {
            cachedClientToken = storedClientToken
            return storedClientToken
        }

        let freshClientToken = generateClientToken()
        let writeSucceeded = writeClientTokenToKeychain(freshClientToken)
        if !writeSucceeded {
            // Worst case: Keychain refuses to persist. We still return the
            // freshly generated token for THIS launch so the user isn't
            // locked out of the app. Next launch will generate a new one,
            // which means the user appears as a new client to the Worker —
            // not ideal, but better than a hard failure.
            print("⚠️ SparkleClientCredentials: Keychain write failed; token will not persist across launches")
        }
        cachedClientToken = freshClientToken
        return freshClientToken
    }

    /// Generates a fresh `sparkle_v1_<64 hex chars>` token using the system
    /// CSPRNG. Crashes only if the kernel cannot produce randomness, which
    /// would indicate a broken device — there's no graceful fallback there.
    private func generateClientToken() -> String {
        var randomBytes = [UInt8](repeating: 0, count: Self.tokenRandomByteCount)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard randomStatus == errSecSuccess else {
            fatalError("SparkleClientCredentials: SecRandomCopyBytes failed (status \(randomStatus))")
        }
        let hexEncodedRandomBytes = randomBytes
            .map { String(format: "%02x", $0) }
            .joined()
        return Self.tokenVersionPrefix + hexEncodedRandomBytes
    }

    /// Keychain query shared by read/write/delete operations.
    private func keychainBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
    }

    private func readClientTokenFromKeychain() -> String? {
        var query = keychainBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var fetchedItem: AnyObject?
        let fetchStatus = SecItemCopyMatching(query as CFDictionary, &fetchedItem)
        guard fetchStatus == errSecSuccess else {
            if fetchStatus != errSecItemNotFound {
                print("⚠️ SparkleClientCredentials: Keychain read returned status \(fetchStatus)")
            }
            return nil
        }
        guard let storedTokenData = fetchedItem as? Data,
              let storedTokenString = String(data: storedTokenData, encoding: .utf8),
              storedTokenString.hasPrefix(Self.tokenVersionPrefix) else {
            // Stored value is corrupt or from a previous token generation.
            // Wipe it so we re-generate on the next access.
            _ = deleteClientTokenFromKeychain()
            return nil
        }
        return storedTokenString
    }

    private func writeClientTokenToKeychain(_ clientToken: String) -> Bool {
        guard let clientTokenData = clientToken.data(using: .utf8) else {
            return false
        }

        // SecItemAdd fails with errSecDuplicateItem if a row already exists,
        // so we proactively delete any prior value before adding. This also
        // handles the corrupt-existing-row case from `readClientTokenFromKeychain`.
        _ = deleteClientTokenFromKeychain()

        var addQuery = keychainBaseQuery()
        addQuery[kSecValueData as String] = clientTokenData
        // Only this device — never sync the credential through iCloud Keychain.
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("⚠️ SparkleClientCredentials: Keychain write returned status \(addStatus)")
            return false
        }
        return true
    }

    @discardableResult
    private func deleteClientTokenFromKeychain() -> Bool {
        let deleteStatus = SecItemDelete(keychainBaseQuery() as CFDictionary)
        return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
    }

    /// Short, log-safe identifier derived from the current token. Used in
    /// console diagnostics so we can correlate logs without exposing the
    /// full credential.
    var loggableTokenSummary: String {
        let token = currentClientToken
        let suffix = token.dropFirst(Self.tokenVersionPrefix.count).prefix(8)
        return "\(Self.tokenVersionPrefix)\(suffix)…"
    }
}
