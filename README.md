# Easy Paste

Easy Paste is a native macOS clipboard manager focused on a fast, fluid Paste-like experience. It is built with Swift, AppKit, NSPasteboard, Carbon hot keys, SQLite, and local blob storage.

The product goal is simple: copied content should enter history quickly, the panel should open instantly, and paste actions should feel direct and predictable.

## Features

- Global clipboard history for text, links, rich text, and images.
- Paste-style bottom panel with glass background, horizontal cards, search, and Pinboards.
- Fast panel opening with lightweight first-frame rendering and async hydration for images, app icons, and rich previews.
- Quick paste shortcuts:
  - `Command + Shift + V`: open panel
  - `Command + 1...9`: paste the matching card
  - `Command + Shift + 1...9`: paste the matching card as plain text
  - Arrow keys: move selection
  - `Return`: paste selected item
  - `Esc`: close panel
- Plain text mode with `Shift`.
- Rich text preservation for original paste when the source provides RTF or HTML.
- Image cards with pixel dimensions and file size.
- Search tokens such as `type:json`, `type:sql`, `app:Safari`, `pinned`, and `today`.
- Pinboards for grouping clipboard items without changing the main history flow.
- Settings window for theme, shortcut, paste behavior, privacy, history retention, ignored apps, and panel glass opacity.
- Local storage in `~/Library/Application Support/EasyPaste/`:
  - `EasyPaste.sqlite` for metadata and preferences.
  - `Blobs/` for larger image, RTF, and HTML payloads.

## Build And Run

Run from source:

```bash
swift run EasyPaste
```

Run with the panel shown on launch:

```bash
swift run EasyPaste -- --show-on-launch
```

Run with performance logging:

```bash
swift run EasyPaste -- --debug-performance --show-on-launch
```

Performance logs are written to:

```text
~/Library/Application Support/EasyPaste/performance.log
```

## Package App

Build a signed `.app` bundle and zip package:

```bash
./scripts/build_app.sh
```

Outputs:

```text
dist/EasyPaste.app
dist/EasyPaste-beta.zip
```

Install locally:

```bash
cp -R dist/EasyPaste.app /Applications/EasyPaste.app
open /Applications/EasyPaste.app
```

The build script prefers a local Apple Development signing identity. If none is available, it falls back to ad-hoc signing.

## Tests

Run the test suite:

```bash
swift test
```

Current tests cover format detection, formatting helpers, preferences, Pinboards, SQLite/blob migration, blob persistence, retention cleanup, and OCR ordering behavior.

## macOS Permissions

Easy Paste needs Accessibility permission for global shortcut fallback and for sending `Command + V` back to the active application.

Enable it in:

```text
System Settings -> Privacy & Security -> Accessibility
```

Then allow `Easy Paste`.

## Development Notes

- Keep panel first-frame rendering lightweight. Do not synchronously decode images, parse large rich text, or load app icons before showing the panel.
- Keep heavy work async: OCR, image hydration, icon loading, and rich preview enhancement should never block panel opening.
- Prefer SQLite metadata plus blob files for large payloads instead of storing everything in a single JSON file.
- Avoid committing built app bundles or zip files; `dist/` is ignored.

## TODO

- Format paste/output workflow: design and implement a one-hand, low-friction formatting mode for JSON, XML, YAML, SQL, Markdown, and plain text.
