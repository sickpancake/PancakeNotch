// Makes a Sparkle update-signing key with CryptoKit (no Keychain): writes the private key to the
// file given as the first argument and prints the public key (SUPublicEDKey). The file is made
// readable only by you from the start, and an existing file is never overwritten.
// Usage: swift scripts/make-update-key.swift <private-key-file>
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-update-key.swift <private-key-file>\n".utf8))
    exit(1)
}
let path = CommandLine.arguments[1]
let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
guard descriptor >= 0 else {
    FileHandle.standardError.write(Data("Can't create \(path): \(String(cString: strerror(errno)))\n".utf8))
    exit(1)
}
let key = Curve25519.Signing.PrivateKey()
let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
try handle.write(contentsOf: Data(key.rawRepresentation.base64EncodedString().utf8))
try handle.close()
print(key.publicKey.rawRepresentation.base64EncodedString())
