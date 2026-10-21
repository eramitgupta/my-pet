# App updates (Sparkle)

MyPet updates itself with [Sparkle 2](https://sparkle-project.org), the standard update
framework for Mac apps distributed outside the App Store. There is no custom updater and no
backend. Releases are files on **GitHub Releases**, and the list of versions (the *appcast*)
is a signed XML file on **GitHub Pages**.

```
 Your Mac (MyPet)                         GitHub
 ───────────────                          ──────
 Check for Updates… / daily check ──────► https://eramitgupta.github.io/my-pet/appcast.xml
   verify the feed's EdDSA signature ◄─── (signed appcast, gh-pages branch)
   newer version? show the update window
   Install Update ──────────────────────► releases/download/vX.Y.Z/MyPet-X.Y.Z.zip
   verify the archive's EdDSA signature
   replace the app, relaunch
```

## What users see

- **MyPet menu → Check for Updates…** (also in the app menu, and Settings → General → Check
  Now). This works whether or not automatic checks are on.
- **Update available:** Sparkle's native window shows the new version, the current version
  and the release notes (from `CHANGELOG.md`), with **Install Update**, **Remind Me Later** and
  **Skip This Version**.
- **Up to date:** a native "You're up to date!" alert.
- **Problems** (offline, no release published yet, or a bad signature): a native alert for
  checks the user started. Background checks fail silently and are logged.
- **Settings → General → Updates:** *Check for updates automatically* (daily, on by default)
  and *Download and install updates automatically* (off by default).

Settings and pets are kept across updates. They live in `~/Library/Preferences/com.erag.mypet.plist`
and `~/Library/Application Support/MyPet/`, outside the app bundle that Sparkle replaces. Launch
at login keeps working, because the app is replaced in place.

## Security model

| Protection | How |
|---|---|
| Only you can publish updates | Every update ZIP is signed with your **EdDSA (ed25519) private key**. The app has the matching public key (`SUPublicEDKey`) built in and refuses anything else. |
| The version list can't be forged | The appcast itself is signed, and the app requires that (`SURequireSignedFeed`). |
| Nothing unverified is unpacked | `SUVerifyUpdateBeforeExtraction` checks the signature before extraction. |
| A key mix-up can't ship | `scripts/publish-update.sh` re-checks each archive against the key *inside the app* before publishing (`scripts/verify-update.swift`). |
| Apple's protections stay on | With a Developer ID, the app, Sparkle's helpers and the DMG are signed with the hardened runtime and notarised; the update ZIP contains the stapled app. |

**The private key never goes in git.** It lives in your login Keychain and in the encrypted
`SPARKLE_PRIVATE_KEY` GitHub secret. `.gitignore` blocks `*.key`, `*.p12` and `*.pem`. Back it
up (for example in a password manager): if you lose it, installed copies can't accept new
updates and everyone has to reinstall by hand.

## One-time setup

### 1. Create the update signing key

```bash
scripts/sparkle-keys.sh
```

This runs Sparkle's `generate_keys`, which stores the private key in your login Keychain (macOS
may ask for permission). It then writes the **public** key into `macos/project.yml`
(`SPARKLE_PUBLIC_KEY`) and regenerates the Xcode project. Commit `macos/project.yml`; it only
contains the public key.

Back up the private key:

```bash
macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/mypet-sparkle-private.key
```

Then move that file into your password manager and delete it from the Desktop.

### 2. Add the GitHub secrets

In the repository: **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Required | Value |
|---|---|---|
| `SPARKLE_PRIVATE_KEY` | for updates | The exported private key. `scripts/sparkle-keys.sh --github` sets this for you (needs the `gh` CLI). |
| `MACOS_CERT_P12_BASE64` | for Developer ID | `base64 -i DeveloperID.p12 \| pbcopy`. Your *Developer ID Application* certificate and its private key, exported from Keychain Access as .p12. |
| `MACOS_CERT_PASSWORD` | for Developer ID | The password you chose when exporting the .p12. |
| `MACOS_SIGN_IDENTITY` | for Developer ID | For example `Developer ID Application: Your Name (ABCDE12345)`. |
| `APPLE_ID` | for notarisation | The Apple ID email of your developer account. |
| `APPLE_TEAM_ID` | for notarisation | Your 10-character Team ID. |
| `APPLE_APP_PASSWORD` | for notarisation | An app-specific password from [appleid.apple.com](https://appleid.apple.com). |

Without the Developer ID secrets, releases are ad-hoc signed: users confirm the first launch
(right-click → Open), and updates still work because they are EdDSA-verified. Without
`SPARKLE_PRIVATE_KEY`, releases are published but not offered as in-app updates, and the
workflow prints a warning.

### 3. Turn on GitHub Pages

After the first release, the workflow creates a `gh-pages` branch containing `appcast.xml`.
Then go to **Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch:
`gh-pages` / root**. The feed will be served at
`https://eramitgupta.github.io/my-pet/appcast.xml`, which is `SPARKLE_FEED_URL` in
`macos/project.yml`.

## Releasing a new version

1. Bump the version in **`Cargo.toml`** (`[workspace.package] version`) and
   **`macos/project.yml`** (`MARKETING_VERSION`). The release workflow checks that they match the
   tag.
2. Add a section to **`CHANGELOG.md`**, written for users. It becomes the release notes on GitHub
   *and* in the update window:
   ```markdown
   ## [0.2.0] - 2026-11-01

   ### New
   - Owl pet 🦉
   ```
3. Commit, then tag and push:
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   ```

`.github/workflows/release.yml` then:

1. checks that the tag, `Cargo.toml`, `project.yml` and `CHANGELOG.md` agree,
2. runs the tests,
3. builds the universal app, signs it and Sparkle's helpers, then notarises and staples it
   (if Developer ID is configured),
4. creates `MyPet-X.Y.Z.dmg` for new installs and `MyPet-X.Y.Z.zip` as the update archive,
5. signs the ZIP, adds it to `appcast.xml` and signs the feed (`scripts/publish-update.sh`),
6. publishes the GitHub release with both files, and then
7. pushes the appcast to `gh-pages`. This happens last, so the feed never points at a file
   that isn't there yet.

Versions are compared on `CFBundleVersion`, which always equals the release version (for
example `0.2.0`). Never reuse or lower a version number.

### Publishing by hand (without CI)

```bash
scripts/build-app.sh release      # or scripts/notarize.sh with a Developer ID
scripts/make-dmg.sh
git worktree add pages gh-pages
scripts/publish-update.sh pages/appcast.xml https://github.com/eramitgupta/my-pet/releases/download/v0.2.0/
gh release create v0.2.0 build/MyPet-0.2.0.dmg build/MyPet-0.2.0.zip --notes-file <(scripts/release-notes.sh 0.2.0)
(cd pages && git add appcast.xml && git commit -m "Appcast: MyPet 0.2.0" && git push)
```

`publish-update.sh` signs with the key in your Keychain, or with `SPARKLE_PRIVATE_KEY` when that
is set.

## Testing updates

```bash
scripts/test-updates.sh
```

This runs fully offline with a throwaway key. It builds version 0.0.0 and the current version,
publishes a signed update to a local appcast, and then uses the **real Sparkle framework** to
find, download, verify and install it. It also checks "already up to date", and that a
tampered download is rejected without touching the installed app. CI runs it on every push. It
overwrites and then deletes `build/MyPet.app`, because those builds carry the throwaway key.

To watch the real update window, point a build at a test feed with the `MYPET_FEED_URL`
environment variable. Updates are still checked against the app's built-in key and the feed
signature, so this test hook can't be used to sneak an update in:

```bash
MYPET_FEED_URL=http://127.0.0.1:8765/appcast.xml build/MyPet.app/Contents/MacOS/MyPet
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Updates aren't available in this build" | The build has no `SPARKLE_PUBLIC_KEY`. Run `scripts/sparkle-keys.sh`, commit `macos/project.yml`, rebuild. |
| "The update feed is improperly signed" | `appcast.xml` was edited after signing, or signed with another key. Re-run `publish-update.sh` (it re-signs), and check that `SPARKLE_PRIVATE_KEY` matches the public key in the app. |
| "The update is improperly signed" | The ZIP changed after signing, or was signed with a different key. `publish-update.sh` would have refused it; rebuild and republish. |
| "An error occurred in retrieving update information" | Offline, Pages not enabled yet, or `appcast.xml` not published. Open the feed URL in a browser. |
| No update offered even though a release exists | The release's version isn't higher than the installed `CFBundleVersion`, or the workflow skipped the appcast (missing `SPARKLE_PRIVATE_KEY`). |
| The release workflow fails at "Check version" | The tag, `Cargo.toml`, `MARKETING_VERSION` and the `CHANGELOG.md` section must all say the same version. |

Logs: `log stream --predicate 'subsystem == "com.erag.mypet" AND category == "updates"'`.
In zsh, `log` is a shell builtin, so use `/usr/bin/log` there.
