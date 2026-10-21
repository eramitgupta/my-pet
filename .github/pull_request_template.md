## What does this change?

<!-- A short description of the change and why it's needed. -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] New pet / artwork
- [ ] Performance improvement
- [ ] Documentation
- [ ] Build / CI

## How was it tested?

<!-- Commands you ran, what you checked by hand, macOS version and Mac (Apple Silicon / Intel). -->

## Checklist

- [ ] `cargo fmt --all --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test --all-targets` pass
- [ ] `scripts/build-app.sh release` builds, and the app runs
- [ ] Tests added or updated for new behaviour
- [ ] If the Rust↔Swift interface changed: `ABI_VERSION` bumped, `include/pet_core.h` updated, `header_check` passes
- [ ] If rendering, timers or sampling changed: CPU measured before/after (see `docs/PERFORMANCE.md`)
- [ ] UI changes checked in light and dark mode, with screenshots below
- [ ] Docs updated (README / GUIDELINES / docs) where needed

## Screenshots

<!-- For UI or pet changes. -->
