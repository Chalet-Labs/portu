public enum TokenRole: String, Codable, CaseIterable, Sendable {
    case supply
    case borrow
    case reward
    case stake
    case lpToken
    case balance

    public var isPositive: Bool {
        switch self {
        case .supply, .stake, .lpToken, .balance: true
        case .borrow, .reward: false
        }
    }

    public var isBorrow: Bool { self == .borrow }
    public var isReward: Bool { self == .reward }
}
