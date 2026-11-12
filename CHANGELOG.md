# Changelog / 更新日志

Changes are listed newest first. / 按版本从新到旧记录。

## 0.1.22 — 2026-11-13

**English**

- Refresh settings, capture controls and previews with flat buttons, consistent corners and alignment, and a more compact settings window.
- Bend arrows by dragging the middle handle, double-click text to edit it, and scroll to adjust the current tool or selected mark. In a long screenshot preview, hold Option while scrolling to adjust a mark.
- Select, move, or delete a cover stroke. Delete individual captures from the recent screenshots menu.
- Move PNG and TIFF encoding, file preparation, and history image loading to the background. Process OCR requests one at a time and reuse identical frames during scrolling capture.

**简体中文**

- 更新设置、截图工具栏和预览，使用无描边按钮、统一圆角和对齐规则，设置窗口随内容收紧。
- 拖动箭头中点可弯曲箭头，双击文字可编辑。滚动可调整当前工具或选中标注，长图预览中按住 Option 再滚动进行调整。
- 可选中、移动或删除遮盖笔迹，也可以在最近截图中删除单张图片。
- 将 PNG 和 TIFF 编码、保存准备和历史图片加载移到后台。OCR 请求依次处理，滚动截图复用完全相同的帧。

## 0.1.21 — 2026-11-11

**English**

- Capture long and wide screenshots by scrolling vertically or horizontally. Klik. stitches the view as you scroll, even when you reverse direction on the same axis.
- Annotate stitched screenshots before copying or saving at full resolution. The Circle tool is also available in regular captures and the OCR view.
- Use the new olive-and-cream palette across the app. The scrolling capture prompt follows the Mac’s light or dark appearance.
- Hold Shift while selecting to capture a square. The selection shows its live pixel dimensions in the top-left corner.
- Clear screenshot history directly in the menu by clicking **Clear All**, then the red **Confirm** button.

**简体中文**

- 支持纵向和横向滚动截长图。Klik. 会边滚动边拼接，也支持在同一轴上反向滚动。
- 可在复制或保存前直接标注长图，保留原始像素尺寸。普通截图和 OCR 界面也新增了圆形标注工具。
- 全应用采用橄榄绿与奶油白配色，滚动截图提示窗跟随 Mac 的浅色或深色外观。
- 按住 Shift 可框选正方形，选区左上角会实时显示像素尺寸。
- 在历史菜单里点击「**清空**」，再点红色「**确认**」，即可清空截图记录。

## 0.1.20 — 2026-11-10

**English**

- Recognize text locally and edit or copy the results beside the capture, while continuing to annotate the image. Refresh recognition with confirmation before replacing edited text.
- Add pixelated, soft-brush, and manually color-picked cover modes; adjust brush size with the scroll wheel. Hold Shift for straight brush strokes, square rectangles, and snapped arrows.
- Pick annotation colors from the capture with a live color preview, including previously completed marks.
- Choose the default save folder, turn off new screenshot history, and receive clearer save feedback.
- Improve capture focus, OCR interaction, toolbar consistency, pointer feedback, and settings layout.

**简体中文**

- 在本机识别文字，在截图旁编辑或复制识别结果，同时继续标注图片。重新识别前会确认是否替换编辑过的文字。
- 增加像素、柔和笔刷和手动取色覆盖模式，可用滚轮调整粗细；按住 Shift 可以画直线、正方形和角度吸附的箭头。
- 从截图和已完成的标注中选取标注颜色，并实时预览取色结果。
- 支持选择默认保存位置、关闭新截图历史，并改进保存反馈。
- 改进截图焦点、OCR 交互、工具栏一致性、光标反馈与设置布局。

## 0.1.19 — 2026-11-09

**English**

- Verify update packages with an independent Ed25519 signature and retain a backup until the new version confirms startup.
- Allow repeated ad hoc builds in the same output directory.
- Let an input method handle Escape while composing text, instead of cancelling the screenshot.

**简体中文**

- 使用独立的 Ed25519 签名验证更新包，待新版确认启动后再清理旧版备份。
- 允许在同一输出目录重复构建临时签名版本。
- 输入法正在组合文字时，Esc 交由输入法处理，不再直接取消截图。

## 0.1.18 — 2026-11-09

**English**

- Download and install an available update from Settings, then restart Klik. The installer is removed after the update.
- Give settings buttons and dropdowns a consistent appearance and alignment.

**简体中文**

- 在设置中发现新版本后，可直接下载安装并重启 Klik，更新后不会留下安装包。
- 统一设置中按钮和下拉菜单的外观与对齐方式。

## 0.1.17 — 2026-11-09

**English**

- Move boxes, arrows, text, and pen marks after drawing. Resize boxes with their handles and adjust arrows by dragging either endpoint.
- Press Enter once to finish editing text, then again to copy the screenshot.
- Updated the selection colours, simplified shortcut settings, and aligned the menu and settings controls.
- Ask for confirmation before clearing recent screenshots, and check for updates from settings.

**简体中文**

- 框、箭头、文字和画笔标注可以拖动；可拖动矩形边角调整大小，或拖动箭头端点调整长度和方向。
- 输入文字时，按一次 Enter 确认文字，再按一次复制截图。
- 统一选区配色，简化快捷键设置，并对齐菜单和设置中的控件。
- 清空最近截图前会先确认，也可以在设置里检查更新。

## 0.1.16 — 2026-11-09

**English**

- Added a redo button for annotations and the ⇧⌘Z shortcut. Making a new annotation clears the redo history.
- The pointer changes to an open hand inside a movable selection and a closed hand while dragging it. Resize pointers remain available at the edges and corners.

**简体中文**

- 标注工具栏新增重做按钮，也可以按 ⇧⌘Z 重做。添加新标注后，之前撤销的操作将无法重做。
- 鼠标移到可拖动的选区内时显示张开的手，拖动时显示握住的手；边缘和角落仍显示调整大小的光标。

## 0.1.15 — 2026-11-09

**English**

- Added a menu bar icon with settings and locally stored recent screenshots. Preview, copy again, or clear them, and choose a limit of 5, 10, 20, or 50 captures.
- Added an option to open Klik at login and a magnifier for selecting or adjusting capture edges.
- Improved capture across displays, capture of the Klik menu, shortcut setup, and returning to previous work.

**简体中文**

- 新增菜单栏图标，可打开设置和本机保存的最近截图。截图可以预览、重新复制或清空，保留数量可选 5、10、20 或 50 张。
- 新增登录时启动选项，以及框选和调整边界时的放大镜。
- 改进了多显示器截图、Klik 菜单截图、快捷键设置和截图后继续工作的体验。

## 0.1.14 — 2026-11-09

**English**

- Double-click a selection to copy it, or hold Space and double-click a window. Enter and the copy button remain available.
- Unmarked captures retain their source colour profile. Clicking outside a window while holding Space keeps the capture open.

**简体中文**

- 双击选区即可复制；按住空格双击窗口也可以直接截图并复制。Enter 和复制按钮仍然可用。
- 未标注的截图保留原图色彩配置；按住空格点到窗口外时，截图界面会保持打开。

## 0.1.13 — 2026-11-09

**English**

- Added selection of individual windows, including covered portions, by holding Space and clicking.
- Introduced a hands-on first-run guide and English and Simplified Chinese interfaces.

**简体中文**

- 按住空格点击可以截取单个窗口，包括被其他窗口遮住的部分。
- 新增实际截图引导，并支持英文和简体中文界面。
