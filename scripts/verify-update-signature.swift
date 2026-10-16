// Checks a download's Sparkle signature against the public key the app carries (SUPublicEDKey), the
// way installed copies will. Signing and checking with the private key alone would pass even if the
// two halves came from different keys, and then no installed copy would accept the update.
// Usage: swift scripts/verify-update-signature.swift <file> <signature> <public-key>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: swift scripts/verify-update-signature.swift <file> <signature> <public-key>\n".utf8))
    exit(1)
}
guard let file = FileManager.default.contents(atPath: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]),
      let keyData = Data(base64Encoded: arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      publicKey.isValidSignature(signature, for: file) else {
    FileHandle.standardError.write(Data("The update signature doesn't match the app's public key (SUPublicEDKey).\n".utf8))
    exit(1)
}
