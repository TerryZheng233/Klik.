<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. 应用图标" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">Mac 原生截图工具。选中画面，加上标注，按 Enter 就能复制。</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">下载 DMG</a> ·
  Apple 芯片 · macOS 14+
</p>

![Klik. 框选维基百科的闰年词条，用红框和箭头标出 2 月 29 日。](docs/klik-preview.png)

按 **⌥A** 开始截图，按 **Enter** 复制。可以先画矩形、箭头或自由笔迹，也可以添加文字或涂马赛克。Klik. 平时在后台运行，Dock 和菜单栏里都没有图标。

## 截区域、整屏或单个窗口

| 截图时的操作 | 结果 |
| --- | --- |
| **拖动** | 框选一块区域。拖动边缘或角可微调 |
| **单击** | 选中鼠标所在的整块显示器 |
| **按住空格并单击** | 高亮并单独截取一个窗口，包括被其他窗口挡住的内容 |
| **Enter** 或 **✓** | 将标注后的图片复制到剪贴板 |
| **↓** | 把 PNG 保存到「下载」 |
| **Esc** 或 **×** | 取消截图 |
| **⌘Z** | 撤销上一笔标注 |

想截被遮挡的窗口时，按住**空格**，把鼠标移到它露出来的任意一部分。单击后，选区里会显示完整窗口，接着就能标注或复制。下图使用浏览器和备忘录示例演示。

![窗口截取前后对比。左图的备忘录盖住了浏览器，右图选中浏览器后显示完整网页。](docs/klik-window.png)

## 安装与第一次截图

1. 下载[最新 DMG](https://github.com/TerryZheng233/Klik/releases/latest)，打开后把 **Klik.app** 拖到「应用程序」。
2. 打开 Klik. 并按 **⌥A**。按 macOS 提示授予「屏幕与系统音频录制」权限。如果系统要求重新打开，照做后再试。
3. 实际截一张图。引导会在工具栏旁解释各个按钮，截图完成后才问你要保留快捷键还是换一组。

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. 安装盘，将左侧的 Klik.app 拖到右侧的 Applications 快捷方式" width="520">
</p>

从「应用程序」重新打开 Klik.，可以修改快捷键，在「语言」里选择「跟随系统」「English」或「简体中文」，也可以点「练习截图…」再走一遍引导。引导和设置随 macOS 切换浅色或深色外观。

![浅色外观的英文快速入门和深色外观的简体中文设置。](docs/klik-interface.png)

想让 Klik. 登录后自动运行，可以在「系统设置 → 通用 → 登录项 → 登录时打开」添加它。

## 从源码构建

需要 Swift 5.10 或更新版本，以及 macOS 15 或更新版本的 SDK。

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

GitHub 的 DMG 使用临时签名，未经 Apple 公证。macOS 可能限制下载后的首次打开，也可能在更新后重新询问屏幕录制权限。本机钥匙串只有一个 **Apple Development** 签名身份时，构建脚本会使用它。也可以用 `KLIK_SIGN_IDENTITY` 指定身份。更新本机签名版时，沿用同一个身份即可保留授权。[Apple 代码签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

使用 [dmgbuild](https://pypi.org/project/dmgbuild/1.6.7/) 生成拖拽安装的 DMG：

```sh
KLIK_SIGN_IDENTITY=- ./build-app.sh .build/distribution
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/distribution/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.13-arm64.dmg
```

工具栏使用 [Lucide 图标](https://lucide.dev/icons/)。[查看随附的许可](Resources/Lucide/LICENSE)。
