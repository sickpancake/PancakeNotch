// Makes a Sparkle update-signing key with CryptoKit (no Keychain): writes the private key to the
// file given as the first argument and prints the public key (SUPublicEDKey).
// Usage: swift scripts/make-update-key.swift <private-key-file>
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-update-key.swift <private-key-file>\n".utf8))
    exit(1)
}
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString()
    .write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
