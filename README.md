<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. app icon" width="92">
</p>

<h1 align="center">Klik.</h1>
<p align="center">原生 macOS 截图工具。按一下，框一块，直接粘贴。</p>
<p align="center">
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">下载 DMG</a>
  · Apple silicon · macOS 14+
</p>

![Klik. 的框选与标注工具栏，画面使用合成测试内容](docs/klik-preview.png)

Klik. 平时在后台等候。没有主窗口、菜单栏图标或 Dock 图标。按 **⌥A** 后，屏幕略暗，鼠标变成十字。拖出的选区恢复原亮度，边角可以继续调整。

| 操作 | 结果 |
| --- | --- |
| **⌥A** | 截取鼠标所在的显示器并开始框选 |
| **拖动边或角** | 调整选区大小，鼠标会提示调整方向 |
| **Enter** 或 **✓** | 将带标注的截图复制到剪贴板 |
| **↓** | 将 PNG 直接保存到「下载」 |
| **⌘Z** / **Esc** | 撤销上一笔标注 / 取消截图 |

工具栏提供矩形、箭头、画笔、文字和自由马赛克画刷。矩形、箭头、画笔和文字共用八种颜色。截图保留当前显示器的像素分辨率，每次框选限一块屏幕。

## 安装

1. 从 [GitHub Release](https://github.com/TerryZheng233/Klik/releases/latest) 下载 `Klik-0.1.6-arm64.dmg`。
2. 打开磁盘映像，把 **Klik.** 拖到 **Applications**，然后从「应用程序」打开 Klik.。
3. 按 **⌥A**，按系统提示开启「屏幕与系统音频录制」。如果系统要求重新打开应用，重开后再按一次 **⌥A**。

想在登录后自动启动，可在「系统设置 → 通用 → 登录项」把 Klik.app 加到「登录时打开」。如果 **⌥A** 被其他截图工具占用，先释放该组合键，再重新打开 Klik.。

本 Release 是供私有仓库使用的测试构建，使用临时签名，未经 Apple 公证。在其他 Mac 上，系统可能限制从网络下载的构建直接启动。[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## 从源码构建

需要 macOS 15 或更新版本的 SDK，以及 Swift 5.10 或更新版本。

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

`./build-app.sh /path/to/output` 可指定输出目录。默认使用临时签名。如有 Apple Development 或 Developer ID 签名证书，可通过 `KLIK_SIGN_IDENTITY` 指定。重建后若系统仍显示已授权但无法截图，可移除旧授权条目，再为正在运行的 Klik.app 重新授权。

如需生成同样布局的 DMG，可在构建应用后使用 [dmgbuild 1.6.7](https://pypi.org/project/dmgbuild/1.6.7/)：

```sh
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.6-arm64.dmg
```

应用图标是 **k.** 字标。工具栏使用 [Lucide](https://lucide.dev/icons/)，许可见 [Resources/Lucide/LICENSE](Resources/Lucide/LICENSE)。
