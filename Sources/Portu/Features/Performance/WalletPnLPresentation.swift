import Foundation
import PortuCore

enum WalletPnLDirection: Equatable {
    case gain
    case loss
    case unchanged

    init(value: Decimal) {
        self = if value > 0 {
            .gain
        } else if value < 0 {
            .loss
        } else {
            .unchanged
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .gain: "Gain"
        case .loss: "Loss"
        case .unchanged: "No change"
        }
    }

    var systemImage: String {
        switch self {
        case .gain: "arrow.up.right"
        case .loss: "arrow.down.right"
        case .unchanged: "minus"
        }
    }
}

struct WalletPnLFlowRow: Equatable, Identifiable {
    let title: String
    let value: Decimal

    var id: String {
        title
    }
}

struct WalletPnLAssetRow: Equatable, Identifiable {
    let implementationID: String
    let averageBuyPrice: Decimal?
    let averageSellPrice: Decimal?
    let totalGain: Decimal?
    let realizedGain: Decimal?
    let unrealizedGain: Decimal?
    let totalInvested: Decimal?
    let totalFee: Decimal?
    let completenessLabel: String

    var id: String {
        implementationID
    }
}

enum WalletPnLPresentation {
    static let estimateDisclosure =
        "Zerion FIFO estimate, not tax advice. Transfers, airdrops, excluded unpriced assets, and tax rules can change the result."

    static func flowRows(for pnl: ProviderPnLDTO) -> [WalletPnLFlowRow] {
        [
            pnl.receivedExternal.map {
                WalletPnLFlowRow(title: "Received externally", value: $0)
            },
            pnl.sentExternal.map {
                WalletPnLFlowRow(title: "Sent externally", value: $0)
            },
            pnl.sentForNFTs.map {
                WalletPnLFlowRow(title: "Sent for NFTs", value: $0)
            },
            pnl.receivedForNFTs.map {
                WalletPnLFlowRow(title: "Received for NFTs", value: $0)
            }
        ].compactMap(\.self)
    }

    static func assetRows(for pnl: ProviderPnLDTO) -> [WalletPnLAssetRow] {
        pnl.assets.map {
            WalletPnLAssetRow(
                implementationID: $0.implementationID,
                averageBuyPrice: $0.averageBuyPrice,
                averageSellPrice: $0.averageSellPrice,
                totalGain: $0.totalGain,
                realizedGain: $0.realizedGain,
                unrealizedGain: $0.unrealizedGain,
                totalInvested: $0.totalInvested,
                totalFee: $0.totalFee,
                completenessLabel: $0.identity == nil
                    ? "Provider-only identifier"
                    : "Mapped asset")
        }
    }
}
