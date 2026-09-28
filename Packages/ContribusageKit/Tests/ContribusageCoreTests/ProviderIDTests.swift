import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// Settings (`enabledProviders`) and `state.json` store provider IDs as bare strings (SPEC §10.7).
@Test func providerIDEncodesAsItsRawValue() throws {
    let json = try JSONEncoder().encode([ProviderID.fake])
    #expect(String(decoding: json, as: UTF8.self) == #"["fake"]"#)
    #expect(try JSONDecoder().decode([ProviderID].self, from: json) == [.fake])
    let keyed = try JSONEncoder().encode([ProviderID.fake: 1])
    #expect(String(decoding: keyed, as: UTF8.self) == #"{"fake":1}"#)
}
