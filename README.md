<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. app icon" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">Take a screenshot. Keep your train of thought.</p>
<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">Download DMG</a> ·
  Apple silicon · macOS 14+
</p>

Whether I’m reading a paper, browsing a website, or playing a game, I can press **⌥A** when I see something I want to share. I select it, hit **Enter**, and the screenshot is ready to paste. Then I can carry on with what I was doing.

## Why I made Klik.

I like how easy it is to take a screenshot in WeChat. But after each capture, I find myself back in WeChat, even when I’m in the middle of reading or playing a game. Mac screenshots are saved to the desktop by default, so I kept collecting files when all I wanted was to paste an image into a chat.

I wanted a small tool I could use without losing my place. Klik. stays in the background until I need it. Before copying a screenshot, I can draw a box or arrow, add a note, or pixelate part of it. If I want a file, I can save a PNG to Downloads.

![A Wikipedia page about leap years with February 29 marked by a red box and arrow.](docs/klik-preview.png)

## Choose what to capture

| Do this | What happens |
| --- | --- |
| **Drag** | Frame part of the screen. Pull an edge or corner to adjust the selection |
| **Click** | Select the whole display under your pointer |
| **Hold Space and click** | Select a single window, including the parts another window covers |
| **Double-click** | Copy the selection when no annotation tool is active. With no selection, copy the display |
| **Hold Space and double-click a window** | Capture and copy the window |
| **Enter** or **✓** | Copy the screenshot with your annotations |
| **Save PNG button (↓)** | Save a PNG in Downloads |
| **Esc** or **×** | Cancel the capture |
| **⌘Z** | Undo your last annotation |

To capture a partly covered window, hold **Space** and point to any visible part of it. Click to bring the full window into the selection.

![A browser window partly covered by Notes on the left. The full browser window appears in the capture editor on the right.](docs/klik-window.png)

## Install Klik.

1. Open the [latest DMG](https://github.com/TerryZheng233/Klik/releases/latest) and drag **Klik.app** to **Applications**.
2. Launch Klik. and press **⌥A**. macOS will ask for **Screen & System Audio Recording** access. After granting it, reopen Klik. if macOS asks you to.
3. Take a practice screenshot. The guide shows you what the toolbar buttons do, then asks whether to keep **⌥A** or record your own shortcut.

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. disk image with Klik.app on the left and the Applications shortcut on the right" width="520">
</p>

Open Klik. again from Applications to change the shortcut or pick **Follow System**, **English**, or **简体中文** under **Language**. The guide and settings follow your Mac’s light or dark appearance. To run through the guide again, choose **Practice a Capture…**.

![Klik.’s quick-start guide in English and light mode, alongside settings in Simplified Chinese and dark mode.](docs/klik-interface.png)

To have Klik. ready when you sign in, add it under **System Settings → General → Login Items → Open at Login**.

## Install with an agent

Attach `Klik-0.1.14-arm64.dmg` to a chat with an agent that can use your Mac, then paste the prompt below. The [v0.1.14 Release](https://github.com/TerryZheng233/Klik/releases/tag/v0.1.14) is private. If you can’t open it, ask the person who invited you to try Klik. for the DMG and its SHA‑256 file.

```text
Help me install Klik. 0.1.14 on this Mac using the DMG I attached. If I haven’t attached it, use the v0.1.14 Release at https://github.com/TerryZheng233/Klik/releases/tag/v0.1.14. If you can’t access it, ask me for the file.

1. Check that my Mac has Apple silicon and runs macOS 14 or later. If the SHA-256 file is available, verify the DMG against it and stop if it doesn’t match.
2. Mount the DMG, copy Klik.app to /Applications, check that the installed version is 0.1.14, and eject the DMG. If Klik.app is already installed, ask me before replacing it.
3. Guide me through the first launch. If macOS blocks this unnotarized build, show me the Apple instructions at https://support.apple.com/en-us/102445 and let me decide whether to open it. Leave system security settings as they are.
4. Ask me to press Option+A and grant Screen & System Audio Recording access when prompted. If macOS asks for a restart, have me reopen Klik. and try Option+A again.
```

## Build from source

Use Swift 5.10 or newer and the macOS 15 SDK or newer.

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

If iCloud Drive or another sync service adds Finder metadata that breaks signature verification, pass an unsynced output directory to `./build-app.sh`, such as `./build-app.sh "$(mktemp -d /tmp/klik-build.XXXXXX)"`.

The GitHub DMG is ad hoc signed and hasn’t been notarized. macOS may block it on first launch or ask for screen recording access again after an update. For local builds, the script uses the **Apple Development** identity if there’s exactly one in Keychain. Set `KLIK_SIGN_IDENTITY` to pick one yourself. Using the same identity for local updates helps retain the existing permission. [Apple code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

To make a drag-to-install DMG, use [dmgbuild](https://pypi.org/project/dmgbuild/1.6.7/).

```sh
KLIK_SIGN_IDENTITY=- ./build-app.sh .build/distribution
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/distribution/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.14-arm64.dmg
```

Klik. uses toolbar icons from [Lucide](https://lucide.dev/icons/). The [license](Resources/Lucide/LICENSE) is included in the repository.
