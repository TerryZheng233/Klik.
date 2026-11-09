<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. app icon" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">Take a screenshot. Keep your train of thought.</p>
<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/TerryZheng233/Klik./releases/latest">Download DMG</a> ·
  Apple silicon · macOS 14+
</p>

Whether you’re reading a paper, browsing a website, or playing a game, press **⌥A** when you see something you want to capture. Select it, then hit **Enter** or simply double-click inside the selection. Your screenshot is ready to paste, and you can carry on with what you were doing. Klik. also keeps recent screenshots on your Mac, so you can find and copy them again from the menu bar.

## Why I made Klik.

I like how easy it is to take a screenshot in WeChat. But by default, confirming a screenshot brings the WeChat window back to the front, even when I’m in the middle of reading or playing a game. Mac screenshots are saved to the desktop by default, so I kept collecting files when all I wanted was to paste a screenshot.

I wanted a small tool I could use without losing my place. Klik. stays in the background until I need it. Before copying a screenshot, I can draw a box or arrow, add a note, or pixelate part of it. If I want a file, I can save a PNG to Downloads.

![A restaurant booking in Safari selected with Klik., with the dinner time highlighted and example contact details pixelated.](docs/klik-preview.png)

A dinner plan to send to a friend: highlight the time, cover the contact details, and copy.

## Choose what to capture

| Do this | What happens |
| --- | --- |
| **Drag** | Frame part of the screen. Pull an edge or corner to adjust the selection |
| **Click before selecting** | Select the whole display under your pointer |
| **Hold Space and click** | Select a window, including the parts another window covers |
| **Double-click** | Copy the selection when no annotation tool is active. Hold Space and double-click to copy a window |
| **Enter** or **✓** | Copy the screenshot with your annotations |
| **Save PNG button (↓)** | Save a PNG in Downloads |
| **Esc** or **×** | Cancel the capture |
| **⌘Z** | Undo your last annotation |
| **⇧⌘Z** | Redo an annotation you just undid |

To capture a partly covered window, hold **Space** and point to any visible part of it. Click to bring the full window into the selection. A magnifier appears while you drag or adjust a selection, helping you line up its edges. With no annotation tool selected, move the pointer inside the selection and drag to reposition it. If you have multiple displays, move the pointer to the display you want to capture.

Some apps may prevent their windows from appearing in screenshots. On some Macs, this can include WeChat, even when its window is visible on screen.

## Install Klik.

1. Open the [latest DMG](https://github.com/TerryZheng233/Klik./releases/latest) and drag **Klik.app** to **Applications**.
2. Launch Klik. and press **⌥A**. macOS will ask for **Screen & System Audio Recording** access. After granting it, reopen Klik. if macOS asks you to.
3. Take a practice screenshot. The guide shows you what the toolbar buttons do, then asks whether to keep **⌥A** or record your own shortcut.

## Recent screenshots and settings

Click **k.** in the menu bar to find your recent screenshots. They’re stored on your Mac; select one to preview it and copy it again, or clear the list when you’re done. Klik. keeps 10 by default. In settings, you can change the limit to 5, 10, 20, or 50 screenshots. When the limit is reached, the oldest captures are removed.

Settings also lets you turn on opening Klik. at login.

If **⌥A** is already in use, for example by WeChat, you can choose another shortcut during setup or in settings. The two apps may not be able to use the same shortcut at the same time.

In settings, you can also change the shortcut or pick **Follow System**, **English**, or **简体中文** under **Language**. The guide and settings follow your Mac’s light or dark appearance. To run through the guide again, choose **Practice a Capture…**.

## Install with an agent

Paste this prompt into a chat with an agent that can use your Mac and access GitHub:

```text
Help me install the latest Klik. release on this Mac from:
https://github.com/TerryZheng233/Klik./releases/latest

1. Check that my Mac has Apple silicon and runs macOS 14 or later. Find the latest release and download its DMG and matching SHA-256 file. If you cannot access the release or find both files, explain what is blocking you. Verify the DMG against the checksum and stop if it does not match.
2. Mount the DMG, copy Klik.app to /Applications, check that the installed version matches the release, and eject the DMG. If Klik.app is already installed, ask me before replacing it.
3. Guide me through first launch. If macOS blocks the app, show me the relevant Apple instructions and let me decide how to proceed. Leave system security settings as they are.
4. Help me try the capture shortcut and grant screen recording access when prompted. If the shortcut is already in use, help me choose another one.
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
  'Klik.' Klik-build-arm64.dmg
```

Klik. uses toolbar icons from [Lucide](https://lucide.dev/icons/). The [license](Resources/Lucide/LICENSE) is included in the repository.
