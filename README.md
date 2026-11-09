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

You’re halfway through a PDF in full-screen Preview and come across a paragraph you want to share. Press **⌥A**, drag over it, and hit **Enter**. The image is ready to paste. Press **→** and you’re on the next page.

## Why I made Klik.

I like WeChat’s screenshot tool. After I confirm a screenshot, I end up looking at WeChat again. That’s especially distracting when I’m reading or playing a game in full screen. The Mac’s default shortcut leaves a file on my desktop each time, even for a screenshot I only meant to paste into a chat.

I wanted a small Mac app I could call up for a quick screenshot. Klik. stays in the background and puts the toolbar beside your selection. Draw a box around a detail, point to it with an arrow, or add a few words. There’s a pen and a pixelation brush too. If you want to keep a file, click the save button for a PNG in Downloads.

![A Wikipedia page about leap years with February 29 marked by a red box and arrow.](docs/klik-preview.png)

## Choose what to capture

| Do this | What happens |
| --- | --- |
| **Drag** | Frame part of the screen. Pull an edge or corner to adjust the selection |
| **Click** | Select the whole display under your pointer |
| **Hold Space and click** | Select a single window, including the parts another window covers |
| **Enter** or **✓** | Copy the screenshot with your annotations |
| **Save PNG button (↓)** | Save a PNG in Downloads |
| **Esc** or **×** | Cancel the capture |
| **⌘Z** | Undo your last annotation |

If a window is partly covered, hold **Space** and point to a bit you can still see. Click it and the full window appears in the selection.

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

Attach `Klik-0.1.13-arm64.dmg` to a chat with an agent that can use your Mac, then paste the prompt below. The [v0.1.13 Release](https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13) is private. If you can’t open it, ask the person who invited you to try Klik. for the DMG and its SHA‑256 file.

```text
Help me install Klik. 0.1.13 on this Mac using the DMG I attached. If I haven’t attached it, use the v0.1.13 Release at https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13. If you can’t access it, ask me for the file.

1. Check that my Mac has Apple silicon and runs macOS 14 or later. If the SHA-256 file is available, verify the DMG against it and stop if it doesn’t match.
2. Mount the DMG, copy Klik.app to /Applications, check that the installed version is 0.1.13, and eject the DMG. If Klik.app is already installed, ask me before replacing it.
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

The GitHub DMG is ad hoc signed and hasn’t been notarized. macOS may block it on first launch or ask for screen recording access again after an update. For local builds, the script uses the **Apple Development** identity if there’s exactly one in Keychain. Set `KLIK_SIGN_IDENTITY` to pick one yourself. Use the same identity for local updates to keep the existing permission. [Apple code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

[dmgbuild](https://pypi.org/project/dmgbuild/1.6.7/) makes the drag-to-install DMG.

```sh
KLIK_SIGN_IDENTITY=- ./build-app.sh .build/distribution
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/distribution/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.13-arm64.dmg
```

Klik. uses toolbar icons from [Lucide](https://lucide.dev/icons/). The [license](Resources/Lucide/LICENSE) is included in the repository.
