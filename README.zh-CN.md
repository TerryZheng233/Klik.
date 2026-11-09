<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. 应用图标" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">原生 macOS 截图工具。按一下，框一块，标好就能粘贴。</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">下载 DMG</a> ·
  Apple 芯片 · macOS 14+
</p>

![在 Safari 中用 Klik. 框选维基百科闰年词条的一段说明，并圈出 2 月 29 日。网页为合成演示。](docs/klik-preview.png)

Klik. 平时在后台等候。按截图快捷键后拖动框选，边角可继续微调。你可以画矩形、箭头或自由笔迹，也可以加文字、涂马赛克。按 **Enter** 把标注后的截图复制到剪贴板，就能回到原来的应用直接粘贴。

## 安装和开始使用

1. 下载[最新 DMG](https://github.com/TerryZheng233/Klik/releases/latest)，打开后把 **Klik.app** 拖到 **Applications（应用程序）**。
2. 从「应用程序」打开 Klik.。两步引导会介绍基本操作，并让你保留 **⌥A** 或录制自己的快捷键。
3. 按截图快捷键。首次截图时，按 macOS 提示授予「屏幕与系统音频录制」权限。如果系统要求重开应用，照做后再试一次。

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. 安装盘：将左侧的 Klik.app 拖到右侧的 Applications 快捷方式" width="560">
</p>

## 选一组顺手的快捷键

以后想改键，从「应用程序」重新打开 Klik. 即可。如果新组合键被占用，Klik. 会提示换一组，并保留当前生效的快捷键。

![Klik. 的两步新手引导：先了解基本操作，再保留 Option+A 或录制自定义快捷键。](docs/klik-guide.png)

*上图为 0.1.7 的简体中文引导。*

## 语言和外观

从 0.1.8 起，Klik. 默认跟随系统语言。重新打开 Klik.，在「语言」里可即时切换「跟随系统」「English」或「简体中文」。引导和设置会随 macOS 切换浅色或深色外观。

![浅色外观的英文快速入门和深色外观的简体中文设置。](docs/klik-interface.png)

## 截图时可以做什么

| 操作 | 结果 |
| --- | --- |
| **⌥A**（默认） | 在鼠标所在的显示器上开始框选 |
| **拖动选区边缘或角** | 调整选区大小 |
| **Enter** 或**绿勾 ✓** | 将标注后的图片复制到剪贴板 |
| **↓** | 把 PNG 保存到「下载」 |
| **Esc** 或**红叉 ×** | 取消这次截图 |
| **⌘Z** | 撤销上一笔标注 |

矩形、箭头、画笔和文字共用八种颜色。截图在本机处理，保留该显示器的像素分辨率，每次框选限一块屏幕。后台运行时没有 Dock 或菜单栏图标。

想要登录后自动运行，可在「系统设置 → 通用 → 登录项 → 登录时打开」添加 Klik.app。

## 从源码构建

需要 Swift 5.10 或更新版本，以及 macOS 15 或更新版本的 SDK。

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

私有仓库的 Release 使用临时签名，未经 Apple 公证。macOS 可能限制下载后的首次打开，换了构建版本后也可能需要重新授权屏幕录制。[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

构建应用后，可用 [dmgbuild 1.6.7](https://pypi.org/project/dmgbuild/1.6.7/) 生成相同布局的 DMG：

```sh
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.7-arm64.dmg
```

工具栏使用 [Lucide 图标](https://lucide.dev/icons/)。[查看随附的许可](Resources/Lucide/LICENSE)。
