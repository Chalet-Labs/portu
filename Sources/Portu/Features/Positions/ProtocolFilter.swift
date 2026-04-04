enum ProtocolFilter: Hashable {
    case all
    case none
    case specific(String)

    func matches(_ protocolId: String?) -> Bool {
        switch self {
        case .all: true
        case .none: protocolId == nil
        case let .specific(id): protocolId == id
        }
    }
}
