import PortuCore
import SwiftUI

public extension TokenRole {
    var displayColor: Color {
        switch self {
        case .supply: .green
        case .borrow: .orange
        case .reward: .yellow
        case .stake: .blue
        case .lpToken: .cyan
        case .balance: .secondary
        }
    }
}
