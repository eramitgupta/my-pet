---
name: mypet-add-setting
description: Add or change a user preference in MyPet end-to-end — PetSettings model, tolerant decoding, sanitising, the SwiftUI control in Settings or the menu-bar popover, applying it live in the controllers, and tests. Use whenever the user wants a new option, toggle, slider, picker or preference ("ek option do", "setting add karo", "make X configurable"), or changes the default of an existing one.
---

# Adding a setting

Settings flow in one direction:

`PetSettings` (model) → `SettingsStore` (UserDefaults, debounced) → `AppDelegate.apply` →
`MenuBarController.apply` / previews. UI controls write through `store.binding(\.path)` or
`store.update { … }`.

Every change applies live with no restart and survives relaunch. The `facing` setting
(`PetFacing`) is a complete recent example to copy.

## 1. Model (`macos/mypet/Settings/PetSettings.swift`)

- If the value has a fixed set of options, add an `enum X: String, Codable, CaseIterable,
  Identifiable` with `title` (and `symbol` if it appears in a picker).
- Add `var x = <default>` to `PetSettings`. Defaults must suit a first launch.
- Add the key to `CodingKeys` **and** a `x = v(.x, d.x)` line to `init(from:)`. Decoding is
  deliberately tolerant: a missing or unknown value falls back to the default, so old saved
  settings keep loading.
- For numbers, clamp them in `sanitized` and add a `static let xRange` for the UI to share.
- Never rename or reuse a stored key. Add a new key instead. If the meaning of stored data
  changes, bump `storageKey` (`settings.v1` → `v2`) and migrate.

## 2. UI (`macos/mypet/Settings/SettingsView.swift`, `MenuBar/MenuContentView.swift`)

- Pick the right pane: **Pets** (which pet), **Appearance** (looks and colour), **Behaviour**
  (memory mode, speed), **General** (startup, performance), **About**.
- Use native controls inside `Form { Section … }.formStyle(.grouped)`: `Toggle`, `Picker`
  (`.segmented` for 2–4 short options, `.radioGroup` when the options need explaining),
  `LabeledSlider`, `ColorPicker`.
- Add a short `.font(.caption).foregroundStyle(.secondary)` explanation when the effect isn't
  obvious.
- Put it in the popover only if users toggle it often (pause, flip, colour mode). The popover
  must stay compact.
- Follow `.claude/rules/swiftui.md`: no `@State` attribute, and accessibility labels on
  icon-only buttons.

## 3. Apply it live

- Menu-bar pet: handle the setting in `MenuBarController.apply(_:constrained:)`. Compare the
  new value with the stored `settings` so unchanged settings cost nothing, and force a redraw
  with `shownImage = nil` when visuals change.
- App-wide (sampling, power): handle it in `AppDelegate.apply`.
- Engine-level (speed, memory mode): map it into `ActorOptions` → `PetActorHandle.configure`.
  A brand-new engine field is an FFI change (see the `mypet-ffi-change` skill).
- Previews: pass the value into `AnimatedPetPreview` so Settings shows the real effect.

## 4. Tests and checks

- XCTest (`macos/Tests/mypetTests`): extend `testRoundTripThroughUserDefaults` and, for a
  tricky default or migration, add a test. XCTest needs Xcode or CI. When neither is
  available, verify the pure logic by compiling it with a small `swiftc` harness in the
  scratchpad, as was done for `FacingController`.
- `cd macos && swift build` must stay free of warnings. Then rebuild and relaunch the app (see
  the `mypet-build-run` skill).
- To test a value without clicking through the UI, inject it with `defaults write
  com.erag.mypet settings.v1 -data <hex json>`, then restore the old value.
- Mention the option in the README feature list when it is visible to users.
