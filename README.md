# Easy Paste

<p>
  <strong>English</strong> |
  <a href="./README.zh-CN.md">简体中文</a>
</p>

Easy Paste is a native macOS clipboard manager focused on a fast, fluid Paste-like experience.

## For Users

### Requirements

- macOS 13.0 or later.
- Universal app: supports both Intel and Apple Silicon Macs.

### Install

Open the installer:

```text
dist/EasyPaste-installer.pkg
```

Follow the installer and Easy Paste will be installed to `/Applications`.

### Permission

Easy Paste needs Accessibility permission to listen for fallback shortcuts and send `Command + V` to the active app.

```text
System Settings -> Privacy & Security -> Accessibility -> Easy Paste
```

### Features

- Clipboard history for text, links, rich text, and images.
- Paste-style bottom panel with glass background, horizontal cards, search, and Pinboards.
- Fast first-frame rendering with async image, icon, and preview hydration.
- Quick paste: `Command + Shift + V`, `Command + 1...9`, `Command + Shift + 1...9`.
- Plain-text paste mode with `Shift`.
- Rich text preservation when the source provides RTF or HTML.
- Image cards with dimensions and file size.

## For Developers

### Run

```bash
swift run EasyPaste
swift run EasyPaste -- --show-on-launch
swift run EasyPaste -- --debug-performance --show-on-launch
```

Performance log:

```text
~/Library/Application Support/EasyPaste/performance.log
```

### Test

```bash
swift test
```

### Package

```bash
./scripts/build_app.sh
```

Outputs:

```text
dist/EasyPaste.app
dist/EasyPaste-installer.pkg
```

Verify the Universal binary before release:

```bash
lipo -info dist/EasyPaste.app/Contents/MacOS/EasyPaste
```

Expected architectures: `x86_64 arm64`.

### Storage

```text
~/Library/Application Support/EasyPaste/
```

- `EasyPaste.sqlite`: metadata and preferences.
- `Blobs/`: image, RTF, and HTML payloads.

## TODO

- Format paste/output workflow for JSON, XML, YAML, SQL, Markdown, and plain text.
