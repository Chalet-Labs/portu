import PortuCore
import SwiftData

enum ZapperToZerionMigrator {
    @MainActor
    static func migrate(
        in modelContext: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let accounts = try modelContext.fetch(FetchDescriptor<Account>())
        var migratedAccounts: [Account] = []
        for account in accounts where account.kind == .wallet && account.dataSource == .zapper {
            account.dataSource = .zerion
            migratedAccounts.append(account)
        }
        if !migratedAccounts.isEmpty {
            do {
                try save(modelContext)
            } catch {
                modelContext.rollback()
                for account in migratedAccounts {
                    account.dataSource = .zapper
                }
                throw error
            }
        }
    }
}
