// Checks Sparkle signatures against the public key the app carries (SUPublicEDKey), the way installed
// copies will. Signing and checking with the private key alone would pass even if the two halves came
// from different keys, and then no installed copy would accept the update. Only the public key is needed,
// so jobs that never see the private key can check a release too.
// Usage:
//   swift scripts/verify-update-signature.swift <file> <signature> <public-key>    a download
//   swift scripts/verify-update-signature.swift --feed <appcast.xml> <public-key>  a signed update feed
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
let usage = """
    usage: swift scripts/verify-update-signature.swift <file> <signature> <public-key>
           swift scripts/verify-update-signature.swift --feed <appcast.xml> <public-key>
    """
guard arguments.count == 4 else { fail(usage) }
let feedMode = arguments[1] == "--feed"
let path = feedMode ? arguments[2] : arguments[1]
guard let file = FileManager.default.contents(atPath: path) else { fail("Can't read \(path).") }
guard let keyData = Data(base64Encoded: arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("The public key isn't a valid update key.")
}

if !feedMode {
    guard let signature = Data(base64Encoded: arguments[2]), publicKey.isValidSignature(signature, for: file) else {
        fail("The update signature doesn't match the app's public key (SUPublicEDKey).")
    }
    exit(0)
}

// A signed feed ends with the block sign_update appends:
//   <!-- sparkle-signatures:\nedSignature: <base64>\nlength: <bytes>\n-->\n
// and the signature covers every byte before it. Like Sparkle, the last such block counts; unlike
// Sparkle, nothing but white space may follow it and the length has to match.
let prefix = Data("<!-- sparkle-signatures:\n".utf8)
guard let block = file.range(of: prefix, options: .backwards) else {
    fail("The update feed isn't signed.")
}
guard let end = file.range(of: Data("-->".utf8), in: block.upperBound..<file.endIndex) else {
    fail("The update feed's signature block isn't closed.")
}
let trailing = String(decoding: file[end.upperBound...], as: UTF8.self)
guard trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    fail("The update feed has something after its signature.")
}
let content = file[file.startIndex..<block.lowerBound]
var signature: Data?
var length: Int?
for line in String(decoding: file[block.upperBound..<end.lowerBound], as: UTF8.self).split(separator: "\n") {
    if line.hasPrefix("edSignature:") {
        signature = Data(base64Encoded: line.dropFirst("edSignature:".count).trimmingCharacters(in: .whitespaces))
    } else if line.hasPrefix("length:") {
        length = Int(line.dropFirst("length:".count).trimmingCharacters(in: .whitespaces))
    }
}
guard let signature, let length, length == content.count else {
    fail("The update feed's signature block is incomplete or its length is wrong.")
}
guard publicKey.isValidSignature(signature, for: content) else {
    fail("The update feed's signature doesn't match the app's public key (SUPublicEDKey).")
}
