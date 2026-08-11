#!/usr/bin/xcrun swift

import CryptoKit
import Darwin
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let encodedSeed = (String(bytes: input, encoding: .utf8) ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines)

guard let seed = Data(base64Encoded: encodedSeed), seed.count == 32 else {
    FileHandle.standardError.write(Data("error: expected a base64-encoded 32-byte Ed25519 private seed\n".utf8))
    exit(2)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} catch {
    FileHandle.standardError.write(Data("error: unable to derive Ed25519 public key\n".utf8))
    exit(2)
}
