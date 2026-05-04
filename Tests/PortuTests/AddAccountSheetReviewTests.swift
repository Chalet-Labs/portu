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
}
