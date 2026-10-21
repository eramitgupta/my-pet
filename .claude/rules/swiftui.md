---
paths:
  - "macos/mypet/Settings/**/*.swift"
  - "macos/mypet/MenuBar/*View.swift"
---

# SwiftUI rules (settings window & popover)

- **Don't write `@State`.** On the macOS 27 SDK it is a macro whose plugin ships only with full
  Xcode, so the CLT build fails with "SwiftUIMacros.StateMacro could not be found". Use the
  property-wrapper type directly; it behaves identically:
  ```swift
  private let hover = State(initialValue: false)   // read: hover.wrappedValue
  Toggle("…", isOn: hover.projectedValue)          // binding: hover.projectedValue
  ```
  `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Binding` and `@Environment` are fine.
- **Native macOS look:** `Form { Section(…) { … } }.formStyle(.grouped)` with standard
  `Toggle`, `Picker`, `Slider` (via `LabeledSlider`), `ColorPicker` and `Link`. No custom web-like
  styling or hard-coded colours. Use semantic colours (`.secondary`, `.tertiary`,
  `.accentColor`) so light and dark mode both work.
- **Data flow:** read `store.settings`, write through `store.binding(\.path)` or
  `store.update { }`. Live numbers come only from `MetricsStore` (`@ObservedObject`), which
  updates every 1–5 s.
- **No per-frame updates in SwiftUI.** Animated pets render through `AnimatedPetPreview`
  (an AppKit layer and `FrameTicker`), which pauses when the window is hidden. Never drive
  animation with SwiftUI state or `TimelineView`.
- **Colour previews** use `settings.gradientColor(at:)`, which calls the Rust engine, so the UI
  matches the pet exactly. Never re-implement the gradient in Swift.
- **Accessibility:** icon-only buttons get `.accessibilityLabel` and `.help`. Composite rows
  use `.accessibilityElement(children: .ignore)` with a label and value. Gallery cards expose
  their selection. Everything must be reachable by keyboard (Tab).
- **Links** open in the default browser via `Link` or `NSWorkspace.shared.open`. Keep URLs in
  `ProjectLinks` and app strings in `AppInfo`.
- **Popover** (`MenuContentView`): stays about 290 pt wide and compact. Add a control there only
  if users toggle it often. Everything else belongs in the Settings window.
- Explanatory text goes in `.font(.caption).foregroundStyle(.secondary)` under the control,
  and should be one sentence where possible.
