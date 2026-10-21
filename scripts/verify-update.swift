#!/usr/bin/env swift
// Verifies an update archive's EdDSA signature against the public key embedded in the app,
// exactly as Sparkle will on users' Macs. Run before publishing so a key mix-up can't ship.
//   swift scripts/verify-update.swift <archive.zip> <base64-signature> <path/to/MyPet.app>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: verify-update.swift <archive> <signature> <app>\n".data(using: .utf8)!)
    exit(2)
}
let info = NSDictionary(contentsOfFile: args[3] + "/Contents/Info.plist")
guard let keyString = info?["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: keyString),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write("error: app has no valid SUPublicEDKey\n".data(using: .utf8)!)
    exit(1)
}
guard let signature = Data(base64Encoded: args[2]),
      let archive = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write("error: unreadable archive or signature\n".data(using: .utf8)!)
    exit(1)
}
if key.isValidSignature(signature, for: archive) {
    print("✓ signature matches the app's SUPublicEDKey")
} else {
    FileHandle.standardError.write("error: signature does NOT match the app's SUPublicEDKey; users could not install this update\n".data(using: .utf8)!)
    exit(1)
}
