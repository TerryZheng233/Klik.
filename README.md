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

I wanted a small tool I could use without losing my place. Klik. stays in the background until I need it. Before copying a screenshot, I can draw a box or arrow, add a note, or pixelate part of it. Drag boxes, arrows, text, and pen marks to reposition them. Adjust a box using its handles, or drag an arrow’s endpoints to change its length and direction. When adding text, press Enter once to finish editing and again to copy. If I want a file, I can save a PNG to Downloads.

![Illustration of a restaurant booking selected with Klik., with the dinner time highlighted and example contact details pixelated.](docs/klik-reservation-green.png)

A dinner plan to send to a friend: highlight the time, cover the contact details, and copy. This illustration uses fictional booking details.

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

Klik. currently supports **Apple silicon Macs running macOS 14 or later**. The download does not support Intel Macs.

1. Go to the [latest release](https://github.com/TerryZheng233/Klik./releases/latest). Under **Assets**, download the file ending in **`arm64.dmg`** (expand Assets if needed), not the `.sha256`, `.sig`, or source code files.
2. Open the DMG, then drag **Klik.app** into **Applications**. Open Klik. from Applications. If macOS says it can’t verify the app, see [If macOS blocks Klik.](#if-macos-blocks-klik) below.
3. The first-run guide will appear. Press **⌥A** or click **Start Practice**. When prompted, allow **Screen & System Audio Recording**; if macOS asks you to reopen Klik., do so and return to the guide.
4. Follow the guide to select and copy a screenshot, then keep **⌥A** or choose another shortcut. After setup, you can press your shortcut, drag to select an area, press **Enter** to copy, and paste with **⌘V**.

### If macOS blocks Klik.

The GitHub release is ad hoc signed and **has not yet been notarized by Apple**, so macOS may say it cannot verify that Klik. is free of malware. If you downloaded Klik. from this repository, are confident it has not been altered, and decide to open it:

1. Dismiss the warning, then open **System Settings → Privacy & Security**.
2. Scroll down to **Security** and find the message that Klik.app was blocked. Click **Open Anyway**, then follow the system prompts. You may need your Mac password or Touch ID.
3. Open Klik. again if it does not start automatically. The button may only appear after you have tried to open the app and may be available for a limited time.

These steps create an exception for the app. If you don’t see the option, or your Mac is managed by a school or employer, it may not be available. If macOS says the app is damaged or will harm your computer, do not open it; check the download and see [Apple’s instructions for opening apps safely](https://support.apple.com/en-us/102445).

### If screenshots don’t work

- **Screen recording permission:** Open **System Settings → Privacy & Security → Screen & System Audio Recording** and allow Klik. If it isn’t listed, try starting a screenshot first. If it still isn’t listed, use the **+** button and select **Applications → Klik.app**. Restart Klik. if prompted. macOS may ask for permission again after an update.
- **Shortcut conflict:** If **⌥A** is already used by another app, use **Start Practice** in the first-run guide, then choose another shortcut. You can also change it later via **k. → Settings → Change Shortcut**. Both apps may not be able to use the same shortcut at the same time.
- **A window is missing:** Some apps restrict screen capture. On some Macs, WeChat windows may not appear even when visible on screen.

## Recent screenshots and settings

Click **k.** in the menu bar to find your recent screenshots. They’re stored on your Mac; select one to preview it and copy it again, or clear the list after confirming. Klik. keeps 10 by default. In settings, you can change the limit to 5, 10, 20, or 50 screenshots. When the limit is reached, the oldest captures are removed.

Settings also lets you turn on opening Klik. at login and check for updates. When a new version is available, you can install it directly from Settings and restart Klik. Starting with 0.1.19, Klik. verifies an independent update signature before installing.

In settings, you can also change the shortcut or pick **Follow System**, **English**, or **简体中文** under **Language**. The guide and settings follow your Mac’s light or dark appearance.

![Illustration of Klik. settings in English light mode and Simplified Chinese dark mode.](docs/klik-interface.png)

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

## License

Klik. is available under the [MIT License](LICENSE). Toolbar icons are from [Lucide](https://lucide.dev/icons/) and retain their [own license](Resources/Lucide/LICENSE).
