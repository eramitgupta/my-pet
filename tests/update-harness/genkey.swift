import CryptoKit
import Foundation
// Throwaway Ed25519 key pair for scripts/test-updates.sh. Never used for real releases.
let key = Curve25519.Signing.PrivateKey()
let dir = CommandLine.arguments[1]
try key.rawRepresentation.base64EncodedString().write(toFile: dir + "/private.key", atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: dir + "/public.key", atomically: true, encoding: .utf8)
