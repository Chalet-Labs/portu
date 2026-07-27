import Foundation

// Zerion omits these flags in some otherwise valid position rows.
// swiftlint:disable discouraged_optional_boolean

struct ZerionPositionResource: Decodable {
    let id: String
    let attributes: Attributes
    let relationships: Relationships

    struct Attributes: Decodable {
        let name: String?
        let parent: String?
        let `protocol`: String?
        let protocolModule: String?
        let groupID: String?
        let positionType: String
        let quantity: Quantity
        let value: Decimal?
        let fungibleInfo: FungibleInfo?
        let flags: Flags?
        let applicationMetadata: ApplicationMetadata?

        enum CodingKeys: String, CodingKey {
            case name, parent, `protocol`, quantity, value, flags
            case protocolModule = "protocol_module"
            case groupID = "group_id"
            case positionType = "position_type"
            case fungibleInfo = "fungible_info"
            case applicationMetadata = "application_metadata"
        }
    }

    struct Quantity: Decodable {
        let numeric: String
    }

    struct FungibleInfo: Decodable {
        let name: String?
        let symbol: String?
        let icon: Icon?
        let flags: FungibleFlags?
        let implementations: [Implementation]
    }

    struct Icon: Decodable {
        let url: String?
    }

    struct FungibleFlags: Decodable {
        let verified: Bool?
    }

    struct Implementation: Decodable {
        let chainID: String
        let address: String?

        enum CodingKeys: String, CodingKey {
            case chainID = "chain_id"
            case address
        }
    }

    struct Flags: Decodable {
        let displayable: Bool?
        let isTrash: Bool?

        enum CodingKeys: String, CodingKey {
            case displayable
            case isTrash = "is_trash"
        }
    }

    struct ApplicationMetadata: Decodable {
        let name: String?
        let icon: Icon?
    }

    struct Relationships: Decodable {
        let chain: Relationship
        let dapp: Relationship?
    }

    struct Relationship: Decodable {
        let data: Linkage?
    }

    struct Linkage: Decodable {
        let id: String
    }
}

// swiftlint:enable discouraged_optional_boolean
