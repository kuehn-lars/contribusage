import ContribusageCore
import Foundation
import Testing

/// FR-16 against the real Keychain: only with `CONTRIBUSAGE_LIVE_TESTS=1` (SPEC §16.1), under a throwaway service.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CONTRIBUSAGE_LIVE_TESTS"] == "1"))
func keychainSecretStoreRoundTrips() throws {
    let store = KeychainSecretStore(service: "contribusage.tests.\(UUID().uuidString)")
    defer { try? store.delete("token") }
    #expect(try store.read("token") == nil)
    try store.write("token", value: "ghp_first")
    try store.write("token", value: "ghp_second")
    #expect(try store.read("token") == "ghp_second")
    try store.delete("token")
    #expect(try store.read("token") == nil)
    try store.delete("token")
}
