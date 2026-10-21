---
paths:
  - "scripts/**"
  - ".github/**"
  - "macos/project.yml"
  - "macos/Package.swift"
  - ".claude/skills/**/scripts/**"
---

# Build, script & CI rules

- **Bash 3.2 compatibility:** macOS ships bash 3.2. Start scripts with
  `#!/usr/bin/env bash` and `set -euo pipefail`. Expand arrays that may be empty with
  `${arr[@]+"${arr[@]}"}`, because a bare `"${arr[@]}"` aborts under `set -u`. Avoid
  `mapfile`, `declare -A` and `${var,,}`.
- **Command Line Tools must suffice:** `build-rust.sh`, `build-app.sh` and `make-dmg.sh` cannot
  need full Xcode. Only `notarize.sh` and the XCTest/xcodebuild steps may, and they must fail
  with a clear message when it's missing.
- **Find tools robustly:** Xcode build phases run with a minimal `PATH`, so scripts search
  `~/.cargo/bin`, `/opt/homebrew/opt/rustup/bin` and the Homebrew bins for `cargo`.
- **No account needed by default:** signing is ad-hoc (`-`) unless `MYPET_SIGN_IDENTITY` is set.
  Secrets come only from the environment or a keychain profile. Never echo them, write them to
  files, or commit them.
- **Environment variables** use the `MYPET_` prefix (`MYPET_ARCHS`, `MYPET_SIGN_IDENTITY`,
  `MYPET_NOTARY_PROFILE`, `MYPET_RUST_CONFIG`, `MYPET_VERSION` and `MYPET_SPARKLE_PUBLIC_KEY`,
  the last two for update testing). The app itself reads the test hooks `MYPET_SIMULATE_POWER`
  and `MYPET_FEED_URL`, plus `MYPET_PETS_DIR`.
- **Version = CFBundleVersion.** Sparkle compares `CFBundleVersion`, so it always equals the
  release version (no timestamps or build counters). Bump `Cargo.toml`, `MARKETING_VERSION` and
  `CHANGELOG.md` together; the release workflow checks all three against the tag.
- **SwiftPM never prompts.** Scripts build with `--only-use-versions-from-resolved-file`, disable
  git's credential helper and set `GIT_TERMINAL_PROMPT=0`. Sparkle is public, so a GitHub password
  prompt is always a bug. Commit `macos/Package.resolved`.
- **Sparkle signing order:** Installer.xpc → Downloader.xpc (`--preserve-metadata=entitlements`)
  → Autoupdate → Updater.app → Sparkle.framework → the app (see `build-app.sh`).
- **Signing keys:** the Sparkle private key reaches `sign_update` only through stdin
  (`--ed-key-file -`) or the Keychain. Never write it to the repository or logs. Test keys come
  from `tests/update-harness/genkey.swift` into a `mktemp` directory, which is deleted
  afterwards.
- **Universal binaries:** SwiftPM's `--show-bin-path` is shared between architectures, so
  copy each slice out before building the next one, then `lipo`. Verify with `lipo -archs`.
- **Version** has one source: `[workspace.package] version` in `Cargo.toml` (read by
  `build-app.sh`). Keep `MARKETING_VERSION` in `project.yml` equal to it.
- **Xcode project** is generated: edit `macos/project.yml`, then run
  `cd macos && xcodegen generate`. Never hand-edit `project.pbxproj`.
- **GitHub Actions:** `secrets.*` cannot appear in step-level `if:`. Expose a job-level env
  flag (`HAS_CERT`) and test `env.HAS_CERT`. Keep `ci.yml` checks identical to the local
  pre-PR checklist (fmt, clippy, cargo test, Xcode build + test, universal build).
- Validate YAML after edits:
  `ruby -ryaml -e 'ARGV.each{|f| YAML.load_file(f)}' .github/workflows/*.yml`.
