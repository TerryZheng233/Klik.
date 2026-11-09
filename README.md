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
| **Double-click** | Copy the selected area. Hold Space and double-click to copy a window |
| **Enter** or **✓** | Copy the screenshot with your annotations |
| **Save PNG button (↓)** | Save a PNG in Downloads |
| **Esc** or **×** | Cancel the capture |
| **⌘Z** | Undo your last annotation |

To capture a partly covered window, hold **Space** and point to any visible part of it. Click to bring the full window into the selection. A magnifier appears while you drag or adjust a selection, helping you line up its edges. If you have multiple displays, move the pointer to the display you want to capture.

Some apps may prevent their windows from appearing in screenshots. On some Macs, this can include WeChat, even when its window is visible on screen.

![A browser window partly covered by Notes on the left. The full browser window appears in the capture editor on the right.](docs/klik-window.png)

## Install Klik.

1. Open the [latest DMG](https://github.com/TerryZheng233/Klik/releases/latest) and drag **Klik.app** to **Applications**.
2. Launch Klik. and press **⌥A**. macOS will ask for **Screen & System Audio Recording** access. After granting it, reopen Klik. if macOS asks you to.
3. Take a practice screenshot. The guide shows you what the toolbar buttons do, then asks whether to keep **⌥A** or record your own shortcut.

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. disk image with Klik.app on the left and the Applications shortcut on the right" width="520">
</p>

Click the **k.** icon in the menu bar to open settings or view recent screenshots. Klik. keeps recent captures on this Mac. Select one to preview it and copy it again, or clear the list. Settings lets you choose a limit of 5, 10, 20, or 50 screenshots and turn on opening Klik. at login. When the limit is reached, the oldest captures are removed.

If **⌥A** is already in use, for example by WeChat, you can choose another shortcut during setup or in settings. The two apps may not be able to use the same shortcut at the same time.

In settings, you can also change the shortcut or pick **Follow System**, **English**, or **简体中文** under **Language**. The guide and settings follow your Mac’s light or dark appearance. To run through the guide again, choose **Practice a Capture…**.

![Klik.’s quick-start guide in English and light mode, alongside settings in Simplified Chinese and dark mode.](docs/klik-interface.png)

## Install with an agent

Attach the DMG and its SHA-256 file to a chat with an agent that can use your Mac, then paste the prompt below. If you do not have the files, provide a link to the release you want to install.

```text
Help me install the Klik. release I attached on this Mac. If I have not attached it, ask me for the release link or files.

1. Check that my Mac has Apple silicon and runs macOS 14 or later. If the SHA-256 file is available, verify the DMG against it and stop if it does not match.
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
