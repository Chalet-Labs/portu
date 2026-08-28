#!/usr/bin/xcrun swift

import CryptoKit
import Darwin
import Foundation

// Verifies a Sparkle Ed25519 archive signature against a PUBLIC key, proving a
// generated update verifies with the exact key clients have embedded — not just
// with the seed that produced it.
//
// usage: verify_sparkle_signature.swift <base64-public-key> <file-path> <base64-signature>

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("expected <base64-public-key> <file-path> <base64-signature>")
}

guard
    let publicKeyData = Data(base64Encoded: arguments[1]),
    publicKeyData.count == 32,
    let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
else {
    fail("expected a base64-encoded 32-byte Ed25519 public key")
}

guard let fileData = FileManager.default.contents(atPath: arguments[2]) else {
    fail("could not read file at '\(arguments[2])'")
}

guard let signature = Data(base64Encoded: arguments[3]) else {
    fail("signature is not valid base64")
}

guard publicKey.isValidSignature(signature, for: fileData) else {
    fail("Ed25519 signature does not verify against the provided public key")
}

exit(0)
