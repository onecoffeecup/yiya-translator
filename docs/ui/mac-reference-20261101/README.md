# 译芽 Mac → Windows 界面对照包

日期：2026-11-01。基准：Mac 源码基准分支 `dev_mac_261016`，提交 `cf0ffda`，当前生产 Objective-C / AppKit 视图。本次只提交 Mac / Windows 共用的视觉参考与资源，不修改平台功能源码，不构建安装或发布版本。

Figma：[译芽 · Mac 原版界面 / Windows 1:1 移植基准](https://www.figma.com/design/wRsOJ3322rEwPcnS0QoMPm)。界面按原生视图层级、原生字形矢量和独立装饰图片重建，未将整页截图当作 UI 图层。

本目录为用户于 2026-11-01 明确要求提交并推送的交付副本；本机内部设计探索、归档和临时导出缓存不在提交范围。

## 怎么用

1. 在 Figma 看 `01 六页主界面 · 完整内容` 和 `02 状态分支 · 窄窗 · 浮窗`；进入分组可分别选择控件和字形路径。
   `yiya-mac-ui-reference.fig` 是从该在线文件通过 Figma「Save local copy」导出的本地文件，可直接交给 Windows 开发并导入 Figma。
2. 打开本目录 `index.html`，可切换每个界面的原生截图与分层 SVG，核对 Mac 实际外观。
3. Windows 开发读取 `ui-manifest.json`：它包含全部界面的真实视图层级、相对父视图的 `x/y/width/height`、颜色、字号、字体名、按钮动作、下拉选项和组件身份。`component-text-inventory.json` 可直接检索文案和字体。
4. 图片优先复用 `assets/` 的当前原始 PNG，控件外观见 `assets/native-controls/`。不要从整页截图再次裁图；不要把阅读文字做成运行时图片。
5. 独立导入 Figma 时使用 `figma-import/Figma-page-01-compact.svg`、`Figma-page-02-compact.svg` 和 `Figma-page-00-components-compact.svg`。`compact` 只共享重复的 SVG 字形路径和图片，未降低尺寸或曲线精度。每个界面也有独立 SVG。

在线整页稿保留静态分层；控件页有 521 个主组件，页面中的字形路径和图片不自动具有代码控件的布局或交互逻辑。Windows 应按清单实现真实控件，不把这份静态稿当作已经完成的应用移植。

## 交付范围与边界

- 48 组生产视图截图及分层 SVG；543 个去重后的原生外观单元（含文字、按钮、表单、图标、背景及不同尺寸）。这是实际捕获的外观集合，不是 543 个不同业务控件种类。
- 六个主页面：实时翻译、最近台词、单词学习、运行设置、字幕外观、翻译服务；另有各页完整滚动内容。
- 分支：服务预设/自定义/高级选项、测试等待/成功/失败，字幕两种模式及尺寸展开，词语/语法/句子/复习，选词收藏、按钮普通/悬停/按下/禁用。
- 窄窗：900 pt 与 720 pt；浮窗：字幕、收起小条、查句结果/未分析、AI 空态/对话/发送中、悬停词卡、短贴译、长贴译。
- 画面、台词、收藏、词典解释和服务结果均为明确的合成示例；采集卡和真实游戏内容没有被读取或保存，未使用真实 API Key、学习库或服务 Token。
- 取样范围为应用内容视图，不含 macOS 系统窗口外框、系统权限页面、系统打开/保存/选色面板，也未穷举全部错误与业务状态。已另行补录折叠贴译、完整展开阅读、打开的译文选择列表，以及收藏词条的释义、例句、来源三种组件状态。
- 这些是静态移植基准，未进行 Windows 运行验收，也不代表 Mac 所有回归或设备验收通过。

## 字体与可编辑性

Mac 当前字体为中文 `STYuanti-SC-Regular` / `STYuanti-SC-Bold`，日文 `HiraMaruProN-W4`。Figma 云端没有这三款字体，外观采用 Mac 原生 PDF 导出的矢量字形，能够单独编辑路径；部分 AppKit 系统控件使用独立原生位图保真。这些字形不是普通 Figma TEXT，修改文案时需重新用正确字体排版。

完整文案、字体名和字号均保留在 JSON。在线稿包含 521 个可见外观主组件；其中文字保持原生字形路径，文案编辑时查阅 JSON 并用正确字体重新排版。22 个空白布局单元仍保留在清单中。源字体文件没有被复制或分发。Windows 运行时必须继续使用可选择、复制、换行和输入的原生文字；最终字体的可用性和换行应单独验收。

## Windows 必须保持的布局与行为

| 项目 | Mac 实际值 / 合同 |
| --- | --- |
| 单位 | 1 Mac pt 对应 1 Figma px；Windows 在 100% 缩放下按 1 DIP 对照，再验收系统缩放 |
| 默认截图内容区 | 1320 × 1000 pt，不含 OS 标题栏 |
| 横幅 / 页面头 | 72 / 88 pt |
| 左导航 / AI 侧栏 | 190 / 320 pt |
| 最小内容宽度 | AI 展开 1100 pt；手动收起 720 pt |
| 页面外边距 | 左右 16 pt，上 8 pt，下 16 pt |
| 通用按钮 | 高 34 pt；绘制范围四边内缩 2 pt，圆角为该绘制高度的一半，通常 15 pt |
| 导航按钮 | 166 × 48 pt；导航行间隔 12 pt |
| 中日阅读正文 | 19 pt；姓名 13 pt；等待提示 14 pt |
| 阅读卡片 | 内容短句最小 156 pt；空态最小 104 pt；卡间距 12 pt |
| 原文视口 | 实际栏宽重测换行，最高 190 pt 后内部滚动 |
| 预览画面 | 真正采集数据驱动，完整等比显示，不裁切、不拉伸；最高 480 pt |
| 悬停词卡 | 宽 320 pt；停留约 0.45 秒；不抢焦点，不改变句子身份 |
| 字幕外观 | 参数与预览 1:2，间距 22 pt；窄窗上下排列；共用不透明度滑条最长 260 pt |
| 字幕模式 / 样式卡 | 模式条 50 pt、按钮 40 pt；样式卡 92 pt、样例区 49 pt |
| 字色块 / 跟随样式 | 48 × 32 / 70 × 32 pt |

AI 侧栏只手动开关；拖窗与切页不改变其显隐，收起不销毁聊天视图、草稿和会话。外框尺寸驱动内部画布，不锁死最外层宽度。实时页顺序保持「画面 → 中文翻译 → 当前对白 → 语法」。长贴译超过高度上限时保留卡内滚动，并保留已有折叠、避让及打开列表的身份。

## 配色真值

以 `objc/learning/FYLearningViews.m` 的 `FYAdventureColor` 为准，优先于早期概念图的近似色。

| Token | 值 | Token | 值 |
| --- | --- | --- | --- |
| ink | `#593E2B` | muted / quiet | `#75604E` |
| canvas | `#F9F4EB` | shell | `#F4EEE3` |
| paper | `#FCF9F3` | cream | `#FFF8EC` |
| reading | `#F1E3CB` | ai | `#F8F0E7` |
| leaf / orange | `#CADAA6` | mint | `#E9EDCC` |
| orangeShade | `#B7CB8B` | rim | `#DED0BB` |
| line | `#BAA181` | serviceSuccess | `#48613B` |
| serviceSuccessSoft | `#F0F3E4` | serviceError | `#9C453E` |
| serviceErrorSoft | `#F8EAE4` | | |

## 图片真源

`sakura-cat-v1.png` 和 `AppIcon.png` 是当前源码中的原始文件。九个拆分图直接按 `FYDrawAdventureArt` 中的坐标从 `ui-reference-atlas.png` 裁出，不重绘、不生成新图。猫咪保留透明度，像素插画等比绘制。

| 文件 | Atlas 左上坐标与尺寸 |
| --- | --- |
| nav-live.png | 43,140,65,61 |
| nav-history.png | 48,220,69,61 |
| nav-learning.png | 48,294,70,67 |
| nav-settings.png | 39,400,76,70 |
| nav-appearance.png | 40,486,74,68 |
| nav-service.png | 48,565,73,69 |
| brand-sprout.png | 38,7,87,78 |
| ai-mascot.png | 1438,118,147,109（保留来源，但不能据此替换当前运行时头像） |
| banner-flowers.png | 1382,18,202,60 |

`assets/icons-original/` 是源码保留的早期 SVG 图标，不是当前六枚导航图标的真值；Windows 对照当前原生截图与上述 PNG。当前运行时的一些操作图标由 AppKit / 自绘代码产生，已在原生控件矢量中保留。

## 对应代码

下列路径相对于本 Git 仓库根目录：

| 部分 | 真源 |
| --- | --- |
| 主窗口、导航、三栏、头部、页面挂载 | `objc/presentation/FYMainWindowController.m` |
| 共享字体、色值、按钮、背景、插画、词卡 | `objc/learning/FYLearningViews.m` |
| 实时页 | `objc/presentation/FYLivePageBuilder.m`、`FYLiveReadingRenderer.m` |
| 历史与学习集合 | `objc/presentation/FYCollectionRenderer.m` |
| 运行设置 | `objc/app/FYAppDelegate.m` |
| 字幕外观 | `objc/FYAppearanceUI.inc` |
| 翻译服务 | `objc/FYTranslationServiceView.m`、`FYTranslationServiceSettings.m` |
| 字幕浮窗 | `objc/presentation/FYSubtitlePresenter.m` |
| 查句 | `objc/presentation/FYQuickSentenceRenderer.m` |
| AI | `objc/learning/FYStudyChatView.m` |
| 贴译 | `objc/presentation/FYInlineCardRenderer.m`、`objc/inline/FYInlineOverlayViews.m` |

## 验证记录

隔离导出器直接链接当前生产源码，强制包含 `FYTestIsolation.h`：偏好设置、凭据、网络、数据库和截图边界保持测试隔离；数据库仅位于测试临时目录，未启动真实采集或真实翻译。

已完整生成 48 组截图和 SVG，保留几何、文字和组件清单；验证 SVG 未引用完整 UI 截图。无损 SVG 复用使用标准 `defs/use`，主界面压缩前后本地渲染像素一致。原生屏幕渲染、PDF/Cairo 和 Figma 的抗锯齿仍有差别，未宣称每个像素都完全相同。

这是设计交付，没有修改生产功能源码，因此没有将它记录为 `scripts/debug.py check`、Windows 编译、安装或用户设备体验验收。

Figma MCP Starter 配额在组件阶段用尽，后续通过已登录的 Figma 网页编辑器导入分层 SVG。完整界面以最终导入稿为准，不把中途已上传的零散构造节点当成完整交付。在线导入与审核状态见 `delivery-status.json`。
