<p align="center">
  <img src="docs/klik-icon.png" alt="Klik. 应用图标" width="88">
</p>
<h1 align="center">Klik.</h1>
<p align="center">随手截一张，思路不断。</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="https://github.com/TerryZheng233/Klik/releases/latest">下载 DMG</a> ·
  Apple 芯片 · macOS 14+
</p>

在「预览」里全屏读 PDF，读到一段想发给朋友的文字。按 **⌥A** 框住它，再按 **Enter**。图已经在剪贴板里，接着按 **→** 就能翻页。

## 为什么做 Klik.

我喜欢用微信截图。每次确认后，屏幕就切回微信。正看得入神，或者全屏游戏打到一半，这一下就很烦。Mac 默认把截图存到桌面，随手发出去的图越多，桌面上攒下来的文件也越多。

我想要的是一个平时待在后台、按下快捷键就能叫出来的 Mac 小工具。Klik. 的工具栏就在选区旁边。想指出一个细节，可以画个框、拉根箭头或写几个字，旁边还有画笔和马赛克。想留档时，点下载就能把 PNG 存到「下载」。

![用 Klik. 给维基百科的闰年词条加上红框和箭头，标出 2 月 29 日。](docs/klik-preview.png)

## 截一块、截整屏或截窗口

| 怎么操作 | 会发生什么 |
| --- | --- |
| **拖动** | 框选屏幕的一部分。想微调就拖边缘或四角 |
| **单击** | 选中鼠标所在的整块显示器 |
| **按住空格并单击** | 选中一个窗口，连被挡住的部分也能截到 |
| **Enter** 或 **✓** | 把带标注的截图复制到剪贴板 |
| **「下载 PNG」按钮（↓）** | 把 PNG 存到「下载」 |
| **Esc** 或 **×** | 取消截图 |
| **⌘Z** | 撤销上一笔标注 |

想截被挡住的窗口，按住**空格**，把鼠标移到还看得见的地方。点一下，选区里就能看到整个窗口。

![左图的「备忘录」挡住了浏览器的一部分，右图的截图选区里显示完整的浏览器窗口。](docs/klik-window.png)

## 安装 Klik.

1. 打开[最新 DMG](https://github.com/TerryZheng233/Klik/releases/latest)，把 **Klik.app** 拖进「应用程序」。
2. 打开 Klik.，按 **⌥A**。macOS 会提示授予「屏幕与系统音频录制」权限。授权后，如果系统提示重新打开 Klik.，照做后再试。
3. 先练习截一张。引导会在工具栏旁告诉你每个按钮怎么用。截完可以保留 **⌥A**，也可以录一组顺手的快捷键。

<p align="center">
  <img src="docs/klik-install.png" alt="Klik. 安装盘，将左侧的 Klik.app 拖到右侧的 Applications 快捷方式" width="520">
</p>

想换快捷键或切换语言，从「应用程序」再打开一次 Klik. 就能进设置。「语言」里可以选「跟随系统」「English」或「简体中文」。引导和设置都跟随 Mac 的浅色或深色外观。想再走一遍引导，就点「练习截图…」。

![英文的浅色快速入门界面，以及简体中文的深色设置界面。](docs/klik-interface.png)

如果希望登录 Mac 后就能用 Klik.，到「系统设置 → 通用 → 登录项 → 登录时打开」添加它。

## 让 Agent 帮忙安装

把 `Klik-0.1.13-arm64.dmg` 发给能操作你这台 Mac 的 Agent，再贴上下面这段话。[v0.1.13 Release](https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13) 是私有的。如果打不开，请邀请你试用的人把 DMG 和 SHA‑256 校验文件发给你。

```text
请用我附上的 DMG 帮我在这台 Mac 上安装 Klik. 0.1.13。如果我还没附文件，请从 https://github.com/TerryZheng233/Klik/releases/tag/v0.1.13 获取 v0.1.13 的安装包。打不开就请我提供文件。

1. 确认这台 Mac 使用 Apple 芯片，系统是 macOS 14 或更新版本。如果有 SHA-256 校验文件，请先核对 DMG，校验不符就停止。
2. 打开 DMG，把 Klik.app 复制到「应用程序」，确认版本是 0.1.13，再推出安装盘。如果已经装过 Klik.，替换前先问我。
3. 指导我首次打开。如果 macOS 拦截这个未经公证的版本，请参考 https://support.apple.com/en-us/102445 告诉我怎么操作，由我决定是否打开。保留系统原有的安全设置。
4. 请我按 Option+A，出现提示时由我授予「屏幕与系统音频录制」权限。如果系统要求重新打开应用，请提醒我重开后再按一次 Option+A。
```

## 从源码构建

构建需要 Swift 5.10 或更新版本，以及 macOS 15 或更新版本的 SDK。

```sh
swift test
./build-app.sh
open -g .build/Klik.app
```

GitHub 上的 DMG 使用临时签名，未经 Apple 公证。macOS 可能拦住首次打开，也可能在更新后再次询问屏幕录制权限。如果本机钥匙串只有一个 **Apple Development** 签名身份，构建脚本会用它签名。也可以通过 `KLIK_SIGN_IDENTITY` 自己指定。更新本机签名版时，用同一个身份可以保留原来的授权。[Apple 代码签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

用 [dmgbuild](https://pypi.org/project/dmgbuild/1.6.7/) 制作可拖拽安装的 DMG。

```sh
KLIK_SIGN_IDENTITY=- ./build-app.sh .build/distribution
dmgbuild -s Packaging/dmg-settings.py \
  -D app=.build/distribution/Klik.app -D background=Packaging/background.png \
  'Klik.' Klik-0.1.13-arm64.dmg
```

工具栏图标来自 [Lucide](https://lucide.dev/icons/)，[许可文件](Resources/Lucide/LICENSE)随源码附上。
