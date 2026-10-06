import Foundation
import SwiftData

// The model-to-snapshot boundary. The value types in this folder import Foundation only;
// reading SwiftData models happens here.

public extension TokenIdentityMappingSnapshot {
    @MainActor
    init(_ mapping: TokenIdentityMapping) {
        self.id = mapping.id
        self.canonicalKey = mapping.canonicalKey
        self.chain = mapping.chain
        self.contractAddress = mapping.contractAddress
        self.coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(mapping.coinGeckoId)
        self.zapperId = TokenIdentityMappingFeature.normalizedProviderID(mapping.zapperId)
    }
}
