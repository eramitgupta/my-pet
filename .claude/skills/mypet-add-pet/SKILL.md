---
name: mypet-add-pet
description: Add a new animated pet (or redesign an existing one) for MyPet — pixel-art sprite strips, tint masks and manifest.json, bundled or user-installed. Use whenever the user asks for a new animal/character, wants to change how a pet looks or animates, mentions sprites, frames, pixel art, manifest.json or the pet gallery, e.g. "ek owl add karo", "make the dog cuter", "add a unicorn pet".
---

# Adding a pet to MyPet

A pet is a folder with `manifest.json` and five horizontal sprite strips (idle, walk, run,
jump, sleep), plus optional grayscale masks. `SpriteLibrary` loads bundled pets from
`macos/mypet/Assets/Pets/` and user pets from `~/Library/Application Support/MyPet/Pets/`.
An invalid pet is skipped and logged; it never crashes the app.

## Choose the route

1. **Bundled pet (preferred for the repo):** add a species to
   `scripts/generate-sprites.swift`. The six built-in pets are drawn from shapes there, which
   keeps the style consistent and easy to tweak.
2. **Hand-made art (the user supplies PNGs):** write the folder directly in the format below.

## Art rules (so tinting works)

The app multiplies the memory-gradient colour into masked pixels.
- Draw tintable body areas in **neutral greys** (base `#DBDBDB`, shade `#AAAAAA`, highlight
  `#FFFFFF`, far-side limbs `#949494`). Saturated colours would tint muddy.
- Keep outline `#2A2230`, eyes, noses, collars and other accents in real colours. They are
  black in the mask, so they survive the tint.
- The mask PNG is 8-bit **grayscale without alpha**: white = recolour, black = keep. CoreGraphics
  clipping rejects masks that have alpha.
- Frames are 32×32 and face **right** (the app mirrors when needed). Feet sit on row 29 and the
  outline on row 30.
- `baseColor` in the manifest is used when the gradient is switched off. Pick the animal's
  natural colour.

## Route 1: extend the generator

In `scripts/generate-sprites.swift`:
- Quadrupeds: build a `Quad` (see `cat`, `fox`, `panda`). Set `body`, `head`, `legT`, and the
  `tail` / `farEar` / `nearEar` / `face` / `bodyMarks` / `details` closures. Draw far-side
  parts with `.far` before the body. Paint details with `paintOnBody` so they never float.
- Other body plans: write a `draw<Name>(_ p: Pose) -> Canvas` like `drawRabbit` or `drawDino`,
  and reuse or define pose arrays (`idlePoses()`, `bipedRunPoses`, `rabbitHopPoses`).
- Add a `Species(...)` entry to `species`, and its id to `SpriteLibrary.preferredOrder` if it
  should appear in a set position in the gallery.

Then regenerate and **look at the result**. The preview is the only way to judge the art:

```bash
swift scripts/generate-sprites.swift --preview docs/pets-preview.png
```

Open `docs/pets-preview.png` with the Read tool. To inspect one animation, crop it with
`sips -c <h> <w> --cropOffset <y> <x>`. Each frame is 144 px wide at 4× scale including padding,
and rows run in species order. Check that legs stay visible in every run frame, that ears and
tails are attached, and that sleep frames read as a lying animal with z's. Iterate until it
looks right.

## Route 2: folder format

```
<id>/manifest.json
<id>/{idle,walk,run,jump,sleep}.png         # width = frames × 32, height = 32
<id>/{idle,walk,run,jump,sleep}_mask.png    # optional, same size
```
```json
{ "id": "owl", "displayName": "Owl", "frameSize": [32, 32], "baseColor": "#B08A5A",
  "menuBarAnimation": "run",
  "animations": { "idle": {"frames": 4, "fps": 4, "loop": true},
                  "walk": {"frames": 6, "fps": 8, "loop": true},
                  "run":  {"frames": 6, "fps": 12, "loop": true},
                  "jump": {"frames": 6, "fps": 10, "loop": false},
                  "sleep":{"frames": 4, "fps": 2, "loop": true} } }
```
Validation (`PetManifest.validate`): all five animations present, 1–64 frames, fps in (0, 60],
frameSize between 1 and 256 px, an id without `/`, and sheets at least frames × frameSize.

## Verify

1. Rebuild and relaunch (see the `mypet-build-run` skill). Bundled assets are copied into the
   app by `build-app.sh`.
2. Check the logs for `Skipping pet at …` errors and for `Loaded N pets` with the new count.
3. Ask the user to open Settings → Pets: the new card should animate in the gallery.
4. The XCTest `AssetTests.testAllBundledPetsLoad` lists the expected ids. Add the new one when
   the pet is bundled.
