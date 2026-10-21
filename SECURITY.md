# Security Policy

## Supported versions

Security fixes go into the latest release. Please update to the newest version before
reporting.

| Version | Supported |
|---|---|
| Latest release (0.1.x) | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please don't report security vulnerabilities in public issues, discussions or pull requests.**

Report them privately through GitHub instead:

1. Go to the [Security tab](https://github.com/eramitgupta/my-pet/security) of the repository.
2. Click **Report a vulnerability**
   ([direct link](https://github.com/eramitgupta/my-pet/security/advisories/new)).
3. Describe the issue, the affected version and macOS version, the steps to reproduce, and its
   impact.

If private reporting is unavailable, contact the maintainer
[@eramitgupta](https://github.com/eramitgupta) through their GitHub profile and ask for a
private channel. Don't include vulnerability details in that first message.

## What to expect

- An acknowledgement within **7 days**.
- An initial assessment within **14 days**, including whether the report is accepted.
- Progress updates until a fix is released. Reporters are credited in the release notes unless
  they prefer to stay anonymous.

Please give us reasonable time to release a fix before you disclose the issue publicly.

## Scope

MyPet is a local menu-bar app with no accounts and no data collection. It reads system
statistics (CPU, memory, swap) through public macOS APIs and stores its settings in your user
defaults. Its only network activity is checking for and downloading updates with
[Sparkle](https://sparkle-project.org) from GitHub Pages and GitHub Releases. Both the update
feed and each update are EdDSA-signed and verified (see [docs/UPDATES.md](docs/UPDATES.md)).
Examples of what's in scope:

- Memory-safety bugs in the Rust core or across the Rust↔Swift boundary
- Loading a crafted pet folder (`manifest.json` or PNG files) that crashes the app or runs code
- Problems in the build, signing or release scripts that could compromise distributed builds
- Any way to make MyPet install an update that isn't signed with the project's update key

Out of scope: issues that need an already-compromised Mac or physical access, and ad-hoc-signed
local builds behaving as macOS intends (Gatekeeper prompts).
