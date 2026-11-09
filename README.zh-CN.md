<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. 应用图标" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">轻量 Mac 截图工具。截完复制，接着用刚才的 App。</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">下载 DMG</a> ·
  Apple 芯片 · macOS 14+
</p>

在「预览」里全屏读 PDF 时，按 **⌥A** 框住想分享的一段，再按 **Enter** 复制。Klik. 会把键盘焦点交回「预览」，接着按 **→** 就能继续翻页。

## 为什么做 Klik.

我用微信截图时，确认后会跳回微信。全屏读文档或玩游戏时，这一下就会打断手头的事。用 Mac 默认的截图快捷键随手分享几张，桌面上又多了几个文件。我想要一个随时叫得出来、用完就收起来的截图工具。

- **截完就能粘贴分享。** 默认复制到剪贴板。想留文件时，再点下载，把 PNG 存到「下载」。
- **标注就在选区旁边。** 矩形、箭头、画笔、文字和马赛克，常用的几样随手就能用。
- **平时在后台。** 要截图时按 **⌥A**，也可以换成自己顺手的快捷键。

![Klik. 框选维基百科的闰年词条，用红框和箭头标出 2 月 29 日。](docs/klik-preview.png)

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

## 让你的 Agent 帮你装

把 `Klik-0.1.13-arm64.dmg` 附给能操作你这台 Mac 的 Agent，再复制下面的提示词。[v0.1.13 Release](https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13) 是私有的。如果打不开链接，可以请邀请你试用的人直接发 DMG 和 SHA‑256 校验文件。

```text
请用我附上的 DMG 帮我在这台 Mac 上安装 Klik. 0.1.13。如果我还没附文件，请从 https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13 获取 v0.1.13 的安装包。打不开就请我提供文件。

1. 确认这台 Mac 使用 Apple 芯片，系统是 macOS 14 或更新版本。如果有 SHA-256 校验文件，请先核对 DMG，校验不符就停止。
2. 打开 DMG，把 Klik.app 复制到「应用程序」，确认版本是 0.1.13，再推出安装盘。如果已经装过 Klik.，替换前先问我。
3. 指导我首次打开。如果 macOS 拦截这个未经公证的版本，请参考 https://support.apple.com/en-us/102445 告诉我怎么操作，由我决定是否打开。保留系统原有的安全设置。
4. 请我按 Option+A，出现提示时由我授予「屏幕与系统音频录制」权限。如果系统要求重新打开应用，请提醒我重开后再按一次 Option+A。
```

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
