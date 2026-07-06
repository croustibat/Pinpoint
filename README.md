# Pinpoint

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/croustibat/Pinpoint)](https://github.com/croustibat/Pinpoint/releases/latest)
[![Platform: macOS 15+](https://img.shields.io/badge/platform-macOS%2015%2B-blue)](https://github.com/croustibat/Pinpoint/releases/latest)
[![Built with Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift&logoColor=white)](https://developer.apple.com/swift/)

> Point at exactly what you mean.

Pinpoint is a native macOS menu-bar app that captures your screen, lets you drop
**numbered markers** on what matters, and copies a **ready-to-paste prompt** for
your AI agent — an annotated image plus instructions that reference every marker.

Built with Swift / SwiftUI + ScreenCaptureKit. Free & open source.

🔗 **[pinpoint-ashy.vercel.app](https://pinpoint-ashy.vercel.app)** · **[Download the latest release](https://github.com/croustibat/Pinpoint/releases/latest)**

![Pinpoint demo — capture a region, drop numbered markers, and copy a ready-to-paste prompt for your agent](docs/demo.gif)

## Why I built this

I pair-program with AI agents all day — Claude Code, Codex — and I kept hitting
the same wall: paste a screenshot, then type a paragraph to explain *which*
button or *which* misaligned icon I meant. Worse, most chat UIs keep only the
image and silently drop the text you copied with it, so half my context never
arrived.

Humans don't describe pixels to each other — we point. Pinpoint lets you do the
same with an agent: drop a numbered marker on the thing, and it copies an
annotated image **plus** a structured prompt that maps every marker to a
position and a note. No more "the button in the corner — no, the other one."

I built it for myself and use it every day. It's open source because the problem
isn't mine alone.

## Download

### Homebrew

```sh
brew install --cask croustibat/tap/pinpoint
```

On Homebrew 6+ you'll be asked to trust the tap once first — run
`brew trust croustibat/tap`, then re-run the install. See the
[tap](https://github.com/croustibat/homebrew-tap) for details.

### Direct download

1. Grab the latest **`Pinpoint.dmg`** from the [releases page](https://github.com/croustibat/Pinpoint/releases/latest).
2. Open it and drag **Pinpoint** into your Applications folder.
3. Launch it — it lives in your menu bar. Signed with a Developer ID and notarized by Apple.

On your first capture, macOS asks for **Screen Recording** permission
(System Settings → Privacy & Security → Screen Recording), then quit and
relaunch Pinpoint once.

**Requirements:** macOS 15 or later · Apple Silicon & Intel.

## Features

- **Region capture** — press **⌘⇧1** (rebindable) → the screen dims; drag a
  rectangle (live dimensions, `Esc` to cancel). Native resolution, multi-display
  and Retina aware. A "capture full screen" fallback lives in the menu.
- **Numbered markers** — click to drop ringed, numbered pins (drag to move, a
  note per marker). Add arrows and rectangles for emphasis.
- **Three marker styles** — filled disc, pointer pin, light outline — applied on
  screen *and* in the export.
- **A prompt your agent can read** — **⌘C** copies the annotated PNG **and** a
  structured text: image size, each marker's description and position (in %),
  then your instructions. Parses cleanly in Claude Code, Codex, and the like.
- **Legend baked in** (optional) — embeds the marker descriptions + instructions
  into the image, so a single paste carries everything (most chat UIs drop the
  clipboard text).
- **The shelf** — a built-in library of your screenshots: browse, favorite, sort,
  rename, Quick Look, and reopen any capture with its annotations.
- **Global shortcuts** — capture or open the shelf from anywhere, fully rebindable.
- **Bilingual** — follows your macOS language (English / French).
- **Native & private** — SwiftUI + ScreenCaptureKit, living in your menu bar.
  Your captures never leave your Mac.

A copied prompt looks like this:

```text
# Annotated capture — 1280×800 px

An image is attached. Numbered (ringed) badges point to specific elements.
Markers (position in % of the image, top-left origin):

1. Primary CTA button · ~62 % × 48 %
2. Misaligned icon · ~12 % × 22 %

## Instructions
Make the CTA full-width on mobile and fix the icon alignment.
```

## Build from source

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the
`.xcodeproj` (not versioned).

```bash
brew install xcodegen      # if needed
xcodegen generate          # creates Pinpoint.xcodeproj — run from the repo root
open Pinpoint.xcodeproj
```

In Xcode:

1. The signing **Team** is baked into `project.yml` (`DEVELOPMENT_TEAM`), so signing
   stays stable across `xcodegen generate` runs. On another machine, replace it with
   your own (System Settings → your developer account, or the OU of your *Apple
   Development* certificate).
2. **⌘R** to run.
3. On the first capture, grant **Screen Recording** (System Settings → Privacy &
   Security → Screen Recording), then relaunch the app.

To verify a build without any signing setup:

```bash
xcodegen generate && xcodebuild -scheme Pinpoint -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

> The fixed `DEVELOPMENT_TEAM` + stable bundle id (`app.croustibat.Pinpoint`) let
> macOS remember the screen-recording grant between builds. If a permission gets
> stuck after an identity change: `tccutil reset ScreenCapture app.croustibat.Pinpoint`,
> then relaunch and re-grant.

## Project structure

```
project.yml                       # XcodeGen config (deps, bundle id, LSUIElement, version…)
Pinpoint/
  PinpointApp.swift               # @main, Settings scene (Capture / Shelf tabs)
  AppDelegate.swift               # menu-bar status item + capture flow
  RegionSelectionController.swift # multi-display overlay + coordinate resolution
  RegionSelectionView.swift       # dimming + rectangle + live dimensions
  ScreenCapture.swift             # ScreenCaptureKit: region (sourceRect) or full screen
  CaptureRegion.swift             # model: target display + rect (points, top-left) + scale
  CaptureRecord.swift /
  CaptureHistory.swift            # recent captures (Application Support + JSON index)
  EditorView.swift                # annotation canvas + side panel
  EditorWindowController.swift    # AppKit window hosting the SwiftUI editor
  Pin.swift / Markup.swift        # marker + arrow/rectangle models
  PinStyle.swift                  # marker styles (disc / pointer / outline)
  Theme.swift                     # vermillon palette
  Exporter.swift                  # annotated PNG render + structured text + clipboard
  SettingsWindowController.swift  # AppKit settings window (works around the macOS 14+ SettingsLink bug)
  ShelfWindowController.swift     # the shelf window
  ScreenshotDetailWindowController.swift  # detail window for a shelf item
  Localizable.xcstrings           # String Catalog (English base, French)
  Shelf/                          # the screenshot library (Models, Services, Stores, Views)
landing/                          # the marketing site (Astro + Tailwind v4, bilingual)
```

## Dependencies

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Sindre Sorhus) — rebindable global shortcuts.

## Release (notarized DMG)

The app icon is **generated** from the design system:

```bash
swift scripts/generate_icon.swift Pinpoint/Assets.xcassets/AppIcon.appiconset
```

A signed Developer ID build + notarization + DMG is produced by `scripts/release.sh`.
One-time setup — store the notarization credentials in a keychain profile:

```bash
xcrun notarytool store-credentials pinpoint-notary \
  --apple-id "<your-apple-id>" --team-id MMJD6CLKNQ \
  --password "<app-specific-password>"   # appleid.apple.com → Sign-In & Security → App-Specific Passwords
```

then:

```bash
scripts/release.sh   # → build/dist/Pinpoint.dmg (signed, notarized, stapled)
```

Then publish the release, bump the Homebrew cask, and update the Sparkle appcast:

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z --latest build/dist/Pinpoint.dmg#Pinpoint.dmg
scripts/update-cask.sh      # → pushes the version + sha256 to croustibat/homebrew-tap
scripts/update-appcast.sh   # → signs the DMG (EdDSA) and adds it to landing/public/appcast.xml
```

Then commit `landing/public/appcast.xml` and redeploy the landing (`vercel deploy --prod`)
so in-app auto-update (Sparkle) sees the new version. The EdDSA private key lives in
the release machine's keychain (paired with `SUPublicEDKey` in `project.yml`); create it
once with Sparkle's `generate_keys`.

## License

[MIT](LICENSE) © 2026 Baptiste Bouillot
