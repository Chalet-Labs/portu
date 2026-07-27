@testable import Portu
import PortuCore
import Testing

struct AddAccountExchangeSecretsTests {
    @Test func `passphrase is persisted only for Coinbase`() {
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .coinbase) == "phrase")
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .kraken) == nil)
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .binance) == nil)
        #expect(AddAccountExchangeSecrets.persistedPassphrase("", for: .coinbase) == nil)
    }

    @Test func `switching away from Coinbase clears passphrase`() {
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.coinbase, currentPassphrase: "phrase") == "phrase")
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.kraken, currentPassphrase: "phrase").isEmpty)
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.binance, currentPassphrase: "phrase").isEmpty)
    }
}

struct AddAccountAccessibilityTests {
    @Test func `close icon button has explicit accessible label`() {
        #expect(AddAccountAccessibility.closeButtonLabel == "Close")
    }

    @Test func `close icon button uses mode agnostic accessible hint`() {
        #expect(AddAccountAccessibility.closeButtonHint == "Closes the account sheet.")
    }
}

struct AddAccountSheetSavePolicyTests {
    @Test func `save policy blocks submit while syncing`() {
        #expect(AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: false, isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: true, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: false, isSyncBlocked: true))
    }

    @Test func `save policy blocks field editing while syncing`() {
        #expect(AddAccountSheetSavePolicy.canEditFields(isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(isSyncing: true, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(isSyncing: false, isSyncBlocked: true))
    }
}
