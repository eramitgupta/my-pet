# Contributing to MyPet

Thanks for your interest in MyPet! Bug reports, new pets, performance improvements,
documentation fixes and features are all welcome.

By participating, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug**: open a [bug report](https://github.com/eramitgupta/my-pet/issues/new?template=bug_report.yml).
  Include your macOS version, your Mac (Apple Silicon or Intel) and the steps to reproduce.
- **Suggest a feature**: open a [feature request](https://github.com/eramitgupta/my-pet/issues/new?template=feature_request.yml).
- **Add a pet**: propose it with the [new pet template](https://github.com/eramitgupta/my-pet/issues/new?template=new_pet.yml)
  or send a pull request (see [Adding a pet](README.md#adding-a-pet)).
- **Security issues**: please **don't** open a public issue. Follow [SECURITY.md](SECURITY.md).

For anything larger than a small fix, open an issue first so we can agree on the approach
before you spend time on it.

## Development setup

Requirements:

- macOS 13 or later
- Xcode Command Line Tools: `xcode-select --install`. Full Xcode is optional and is needed only
  for the Xcode project, XCTest and Instruments.
- Rust via [rustup](https://rustup.rs), with both Mac targets:

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

Build and run:

```bash
scripts/build-app.sh debug
```

```bash
open build/MyPet.app
```

You can also open `macos/mypet.xcodeproj` in Xcode and press ⌘R. It builds the Rust core
automatically.

## Project layout

| Path | What lives there |
|---|---|
| `rust/pet-core/` | Rust engine: CPU/memory monitoring, colour gradient, animation, FFI |
| `include/pet_core.h` | The C interface between Rust and Swift (hand-written) |
| `macos/mypet/` | Swift app: menu bar, settings UI, rendering, assets |
| `scripts/` | Build, packaging and asset-generation scripts |
| `tests/` | Rust integration tests |
| `docs/` | Metric definitions and performance notes |

[GUIDELINES.md](GUIDELINES.md) explains the architecture, the Rust↔Swift contract, threading
rules and the performance budget. Please read it before making non-trivial changes.

## Before you open a pull request

Run the checks that CI runs:

```bash
cargo fmt --all --check
```

```bash
cargo clippy --all-targets -- -D warnings
```

```bash
cargo test --all-targets
```

```bash
scripts/build-app.sh release
```

If you have full Xcode, also run the Swift tests:

```bash
xcodebuild -project macos/mypet.xcodeproj -scheme mypet -destination 'platform=macOS' test
```

Then check these:

- **New behaviour comes with tests.** Logic belongs in Rust where possible, because it is easy
  to unit-test there.
- **Changing the Rust↔Swift interface?** Bump `ABI_VERSION` and `PET_CORE_ABI_VERSION`, update
  `include/pet_core.h`, and keep `tests/header_check.rs` green.
- **Touching rendering, timers or sampling?** Measure CPU before and after (see
  [docs/PERFORMANCE.md](docs/PERFORMANCE.md)). The budget is under 1.5 % CPU while animating.
- **UI changes:** check light and dark mode and keyboard navigation, and include a screenshot
  in the PR.
- **No new dependencies.** The only third-party package is Sparkle (for updates), and the
  Rust core has none. Please
  discuss with the maintainer before adding one.

## Code style

- Rust: `cargo fmt` and clippy without warnings. Keep `unsafe` to `sys.rs` and `ffi.rs`, with a
  `// SAFETY:` comment on every block.
- Swift: follow the surrounding code. Use `final class` by default, `@MainActor` for UI
  controllers, and no force-unwraps outside tests.
- Comments explain *why*, not *what*.

## Commit messages and pull requests

- Keep each pull request focused on one change. Small PRs are reviewed faster.
- Use a short, imperative summary line, for example `Add owl pet` or `Fix colour flicker on wake`.
- Fill in the pull request template and link the issue it closes (`Closes #12`).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
