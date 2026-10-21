---
name: mypet-release
description: Cut a MyPet release — bump the version, write the CHANGELOG entry, run checks (including the end-to-end update test), build the universal app, make the DMG and the signed Sparkle update + appcast, optionally sign and notarise, and tag for the GitHub release workflow. Use whenever the user mentions releasing, shipping, versioning, a DMG, notarisation, Developer ID signing, Gatekeeper warnings or distributing MyPet to other people ("release banao", "dmg do", "v0.2 ship karo").
---

# Releasing MyPet

## 1. Bump the version (keep the three places in sync)

| File | Field |
|---|---|
| `Cargo.toml` | `[workspace.package] version` (the build script reads it for the app) |
| `macos/project.yml` | `MARKETING_VERSION`, then run `cd macos && xcodegen generate` |
| `CHANGELOG.md` | a `## [x.y.z] - date` section written for users: it's shown in the in-app update window |

`CFBundleVersion` equals the version (Sparkle compares it), so never reuse or lower a version.
The release workflow refuses a tag that doesn't match all of these.

## 2. Checks (all must pass before building)

```bash
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && cargo test --all-targets
```

Also run `scripts/test-updates.sh`: a real Sparkle install of the new build with a throwaway key,
offline. It deletes `build/MyPet.app` afterwards, so build the release after it.

XCTest needs full Xcode (`xcodebuild -project macos/mypet.xcodeproj -scheme mypet test`) or CI.
If neither is available, say that the Swift tests were not run.

## 3. Build and package

```bash
scripts/build-app.sh release   # universal (arm64 + x86_64), ad-hoc signed
scripts/make-dmg.sh            # build/MyPet-<version>.dmg
```

Confirm the result: `lipo -archs build/MyPet.app/Contents/MacOS/MyPet` should list both
architectures, `codesign --verify --strict build/MyPet.app` should pass, and make-dmg prints
`checksum … is VALID`. The `hdiutil … deprecated` warning is harmless.

## 4. Sparkle update and appcast

The release workflow does this when the `SPARKLE_PRIVATE_KEY` secret exists. By hand:
`scripts/publish-update.sh pages/appcast.xml https://github.com/eramitgupta/my-pet/releases/download/vX.Y.Z/`.
It zips the app with `ditto`, EdDSA-signs the zip, adds the appcast item with release notes from
CHANGELOG, signs the feed, and verifies the zip against the key embedded in the app. The full
setup and troubleshooting are in `docs/UPDATES.md`. The app must have `SPARKLE_PUBLIC_KEY` set
(`scripts/sparkle-keys.sh`).

## 4b. Signing and notarisation (only with the user's credentials)

An ad-hoc DMG works, but Gatekeeper warns other people ("right-click → Open"). To remove the
warning, the user needs an Apple Developer Program membership:

```bash
MYPET_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
MYPET_NOTARY_PROFILE=MyPet scripts/notarize.sh
```

The profile comes from
`xcrun notarytool store-credentials MyPet --apple-id … --team-id …`. As an alternative, set
`APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`. The user enters passwords and creates
credentials themselves; never type them in for the user. Notarisation needs full Xcode.

## 5. Tag (only when the user asks to publish)

Pushing a `v*` tag runs `.github/workflows/release.yml`. It signs and notarises when the
repository secrets `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`,
`APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` exist, and otherwise publishes an ad-hoc
DMG. Tagging and pushing are outward-facing, so confirm with the user first:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

## Report

Give the version, the DMG path and size, the architectures, the signature type (ad-hoc or
Developer ID) and the notarisation status, and list anything that was skipped.
