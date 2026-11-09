<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. app icon" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">A native Mac screenshot tool for quick captures and annotations.</p>
<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">Download DMG</a> ·
  Apple silicon · macOS 14+
</p>

![Klik. frames a Wikipedia article and marks February 29 with a red rectangle and arrow.](docs/klik-preview.png)

Press **⌥A**, capture what you need, and press **Enter** to copy it. Add rectangles, arrows, pen strokes, text, or freehand pixelation before you paste. Klik. runs in the background without a Dock or menu bar icon.

## Capture a region, a display, or a window

| While capturing | What it does |
| --- | --- |
| **Drag** | Select a region. Drag an edge or corner to adjust it |
| **Click** | Select the entire display under the pointer |
| **Hold Space and click** | Highlight and capture a single window, including the parts covered by other windows |
| **Enter** or **✓** | Copy the annotated image to the clipboard |
| **↓** | Save a PNG to Downloads |
| **Esc** or **×** | Cancel the capture |
| **⌘Z** | Undo the last mark |

To capture a partially covered window, hold **Space** and point at any exposed part of it. Click to reveal its full contents in the editor, ready to mark up or copy. The illustration uses a sample browser and Notes scene.

![Before and after window capture. Notes covers the browser on the left. After selecting the browser window, the full page appears in the editor on the right.](docs/klik-window.png)

## Install and take your first screenshot

1. Download the [latest DMG](https://github.com/TerryZheng233/Klik/releases/latest), open it, and drag **Klik.app** into **Applications**.
2. Open Klik. and press **⌥A**. Grant **Screen & System Audio Recording** access when macOS asks, then reopen Klik. if prompted.
3. Try a capture. The guide explains each toolbar button on screen, then asks whether you want to keep the shortcut or record a new one.

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. disk image with Klik.app on the left and the Applications shortcut on the right" width="520">
</p>

Reopen Klik. from Applications to change the shortcut or choose **Follow System**, **English**, or **简体中文** under **Language**. Select **Practice a Capture…** to replay the guide. The guide and settings follow macOS light and dark appearance.

![The English quick-start screen in light appearance and the Simplified Chinese settings in dark appearance.](docs/klik-interface.png)

To start Klik. at sign-in, add it under **System Settings → General → Login Items → Open at Login**.

## Build from source

Requires Swift 5.10 or later and the macOS 15 SDK or later.

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

The GitHub DMG is ad hoc signed and has not been notarized. macOS may block a downloaded copy on first launch or ask for screen recording permission after an update. Local builds use the sole **Apple Development** identity in Keychain when available. To select an identity explicitly, set `KLIK_SIGN_IDENTITY`. Keep the same identity when updating a locally signed copy to preserve its permissions. [Apple code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

To create the drag-to-install disk image, use [dmgbuild](https://pypi.org/project/dmgbuild/1.6.7/):

```sh
KLIK_SIGN_IDENTITY=- ./build-app.sh .build/distribution
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/distribution/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.13-arm64.dmg
```

Toolbar icons are from [Lucide](https://lucide.dev/icons/). See the [included license](Resources/Lucide/LICENSE).
