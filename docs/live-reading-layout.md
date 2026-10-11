# 实时页：先读中文，再查看原文

2026-10-11，用户确认奶油棕圆体预览及紧凑空状态并授权接入。阅读布局已随功能提交 `4956d21` 推送至 Mac 分支 `dev0.2.1_261009`，前一集成包为 0.2.1 build 59；公开 Release / Sparkle 仍为 build 17。

## 2026-10-11：正文统一 19 pt，点击后保持字号（本机 build 60）

用户要求中文正文与当前对白同大，并指出点击后文字缩小。原生生产视图失败回归中，中文显示为 23 pt，进入 AppKit field editor 后变为 14 pt；控件沿用了等待提示的默认字体，且 `allowsEditingTextAttributes=NO`。证据为 `.build/reading-font-20261011/before.log` 的 `displayed=23.0 selected=14.0 rich=0`，该字号保持断言退出 2。

`objc/LiveCaptionTranslator.m` 仅将中文正文改为 19 pt，并允许原生选中编辑器保留已有富文本样式。姓名仍为 13 pt，等待提示仍为 14 pt；正文不可编辑，继续支持原生选择、复制与完整换行。`tests/PreviewLayoutTests.m` 使用相同生产视图，覆盖 selectText、原生 mouseDown / mouseUp 追踪、全选写入独立测试剪贴板、同句刷新及退出选中，分别验证有姓名短句和十二行无姓名长译文。显示 / 选中均为 19 pt；未改动玩家剪贴板。

三组 UI 均退出 0：`PreviewLayoutTests`（含宽窄卡片、空状态、字号、复制、点击和缩放）、`DragSelectionTests` 与 `SourceHoverTests`。日志在 `.build/reading-font-20261011/final.log`、`drag.log`、`hover.log`。最新[合成台词预览](../../../../docs/design/live-reading-preview-20261011/production-reading-19pt.png)使用正式视图渲染。

首次 `python3 scripts/debug.py check` 退出 1：前六个模块通过后，同仓库另一项任务更新了 `tests/SpeakerPlateTests.m` 与 `speaker-plate-ocr-noise.json`，源码 / 夹具快照保护主动中断；不能记为完整检查通过。报告 `.build/debug/20261011T112820Z-e0e4bd/summary.json`。应用生产源码没有变化。重跑 `python3 scripts/debug.py check` 退出 1，前五套通过，`ModuleTests` 在新增的姓名牌 OCR 断言「every confirmed plate is metadata; dialogue contains only the spoken body」失败，报告 `.build/debug/20261011T113055Z-2e56c0/summary.json`。该目标只链接 OCR / 内容路由 / 学习模型模块，不编译本轮修改的 `LiveCaptionTranslator.m`；失败发生在另一项任务新加强的断言。未删除或放宽该测试，未将完整核心检查记为通过。

已执行 `FY_BUILD_NUMBER=60 bash scripts/install-app.sh`，双架构构建、dSYM UUID 和安装包签名核对通过，正式应用已重新打开并保持暂停。安装前后 180 项生产文件 SHA-256 无变化；凭据只检查元数据，文件及目录权限、大小、mtime 和 inode 不变，未读取 Key 内容。日志及安装核对在 `.build/reading-font-20261011/install.log`、`installed-verification.json`。本轮字号修补提交至 Mac 开发分支；公开 Release / Sparkle 仍为 build 17。

- x86_64 UUID：`24B99006-5926-3533-9C76-391CC8FBAE2F`
- arm64 UUID：`00B1BE09-A4E4-34DE-A5AC-157E3BF83F61`

实际命令（仓库根）：

```bash
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh PreviewLayoutTests .build/reading-font-20261011/final
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh DragSelectionTests .build/reading-font-20261011/DragSelectionTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh SourceHoverTests .build/reading-font-20261011/SourceHoverTests
python3 scripts/debug.py check
FY_BUILD_NUMBER=60 bash scripts/install-app.sh
codesign --verify --deep --strict /Users/nanami/Applications/译芽.app
```

上述点击回归为隔离的 AppKit 事件追踪与合成台词；没有启动真实采集、调用翻译服务或读取玩家学习数据库。最短体验验收：打开本机译芽，在有译文时点击 / 拖选中文正文，再点击其它区域，确认与当前对白正文同大且不缩小。真实服务、设备和所有视觉场景不在本轮验证范围。

## 当前规则与集成验证

阅读顺序为「游戏画面 → 中文翻译 → 当前对白 → 语法」；中文正文 19 pt、日文 19 pt、匹配原文姓名的前缀 13 pt。两卡间距 12 pt，有内容时最小高度 156 pt；空状态最小高度 104 pt，标题位于左上、距顶部 14 pt，等待提示 14 pt，隐藏空原文视口并禁用固定操作。长译文不限制八行，原文视口最高 190 pt 后内部滚动；缩放按实际栏宽重测，保留全部字符、选择索引及固定身份。

AI 侧栏仅手动开关；检查 720 pt 窄窗时先手动收起，展开时保留 1100 pt 最小内容宽度。build 59 集成时的 `PreviewLayoutTests`、相关 UI、111 项核心检查、双架构打包和安装身份核对通过；完整视觉套件的既有徽标失败及正式鼠标待验收范围，统一见[build 59 集成记录](window-resize.md)。下方 build 54 / 55 的命令、超时和 UUID 是各自历史证据，不代表当前安装包，也不把后续通过改写为此前超时已通过。

## build 54 行为与修改范围

`objc/LiveCaptionTranslator.m` 的实时页改为「游戏画面 → 中文翻译 → 当前对白 → 语法」。中文正文由 16 pt 改为 23 pt，日文正文由 20 pt 改为 19 pt；已有姓名前缀使用 13 pt 辅助文字。中文前缀只有与原文姓名一致时才缩小，普通中文短首行继续使用正文大小。

两张独立卡片以 156 pt 为短句最小高度，间距 12 pt。固定／跟随按钮及状态放在原文标题行，原文内部间距收紧。高度按内容增长，中文移除八行上限；原文视口按实际排版宽度和带字体的文本重新测量，最高 190 pt 后仍可内部滚动。一次三行合成样本在 778 pt 栏宽下的实际卡高为中文 156 pt、原文 182 pt；原文包含原生文本内边距与操作区，因此没有强制两卡等高。

原文没有删除、插入或重排字符，选词／拖选索引、固定身份和悬停属性保留。窗口缩放后重新测量原文高度，无需等待下一次 OCR。共享配色、插画、采集画面比例、字幕及设置不变。

## build 54 失败证据与回归

`tests/PreviewLayoutTests.m` 使用真实生产视图与合成数据，追加阅读顺序、字号、姓名索引、短卡比例、末行视口、720 pt 窄窗固定／跟随、十二行长译文、无新 OCR 时缩放重测等断言。

- 改动前的新阅读顺序断言失败，日志 `.build/live-reading-20261011-before.log`。
- 追加的普通中文短首行字体断言在修补前失败，日志 `.build/live-reading-20261011-translation-font-before.log`。OCR 姓名启发式会把纯汉字短行当作姓名；新增原文姓名匹配条件，只限制显示样式，不改动 OCR 或实际文字。
- 最终 `PreviewLayoutTests`、`DragSelectionTests`、`SourceHoverTests`、`WorkspaceStressTests` 均执行通过，包含 200 次页面／缩放交互；日志 `.build/live-reading-20261011-final-<套件名>.log`。
- 首次统一 Debug 因其它任务同时更新 `DEBUG_WORKFLOW.md` 而中断，不能记为通过。修补短首行样式后的最终 `python3 scripts/debug.py check` 返回 0，111 项均为 `passed`，源码和夹具哈希保持不变；报告 `.build/debug/20261011T085311Z-f39382/summary.json`，命令输出 `.build/live-reading-20261011-debug-final2.log`。

实际命令（在本仓库根执行）：

```bash
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh PreviewLayoutTests .build/live-reading-20261011/PreviewLayoutTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh DragSelectionTests .build/live-reading-20261011/DragSelectionTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh SourceHoverTests .build/live-reading-20261011/SourceHoverTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh WorkspaceStressTests .build/live-reading-20261011/WorkspaceStressTests
python3 scripts/debug.py check
FY_BUILD_NUMBER=54 bash scripts/install-app.sh
```

较大范围的 `PixelAdventureUITests` 停在普通贴译长卡的「已选中」标记断言。使用本次修改前的 `LiveCaptionTranslator.m` 副本、相同模块和隔离环境复跑，仍在同一断言失败，因此不宣称整套 UI 通过，不把这项既有失败计为本次修复；原始与基线日志分别为 `.build/live-reading-20261011-PixelAdventureUITests.log`、`.build/live-reading-20261011-PixelAdventure-baseline.log`。基线源码与编译产物只留在忽略的 `.build/`，没有覆盖现役源码。

## build 54 本机安装与未验证范围

最终安装日志 `.build/live-reading-20261011-install-final.log`。arm64 + x86_64 构建、dSYM UUID 核对及安装包签名验证通过；安装目标为 `~/Applications/译芽.app`，旧安装由既有脚本备份。应用已打开，原生辅助功能树确认「中文翻译」位于「当前对白」之前，固定／跟随入口在原文区，状态为已暂停。

发布构建、dSYM 与本机已安装二进制的 UUID 一致：arm64 为 `4FC5D220-F428-35E1-93BE-2599EFD096B8`，x86_64 为 `BEDFC2D3-781A-3D87-BEC1-300CB599BFE6`。最终代码 SHA-256：`LiveCaptionTranslator.m` 为 `97889102e7324bc3feee2dd5e96ff2814b48e2c69bdd6a0c664bcf7288c2a3c7`；`PreviewLayoutTests.m` 为 `c06bbe3e41ed9a136c07e9cd35adf6bcda9de9f791437c93d9c88e91a0590e60`。

专项 UI 检查使用临时数据库、合成对白及 mock 服务；不读取真实 Key、用户学习库或采集设备，不请求真实翻译 API。附件中的真实游戏画面未收入本仓库、应用包或发布附件。

尚未用实际采集卡对白或另一台 Mac 验收。最短体验检查：开始实时翻译，确认中文先显示；拖选原文后让游戏前进一句，确认固定内容保留，再点「跟随最新」；缩窄再放宽窗口，确认文字换行、末行及原文卡高度正常。此处属于玩家体验验收，不能由自动检查代替。

## 2026-10-11 追加：空状态标题回到左上

用户确认空状态预览并授权实施。触发条件是实时页尚无对白 / 译文；此前两卡至少 156 pt 且内部纵向 stack 为 Fill，标题行吸收多余高度，中文标题实测距顶部 47.5 pt。`PreviewLayoutTests` 先增加实际生产视图断言，修复前退出 2，日志 `.build/empty-reading-20261011/before.log`；不是横向居中或字体问题。

局部修补 `objc/LiveCaptionTranslator.m`：阅读卡片末尾加入可伸展空白，内容保持自身高度，中文标题顶部间距恢复 14 pt。空状态最小卡高 104 pt，等待提示为 14 pt 辅助棕圆体；无原文时显示等待识别提示，隐藏空阅读视口及选词说明，固定按钮禁用。原文出现后恢复视口、选词说明、固定操作和 156 pt 最小高度；收到译文恢复 23 pt 正文，姓名前缀和原文字符索引沿用已有规则。译文尚在途时显示小字号等待提示。

新增生产视图回归覆盖 720 / 1320 pt 宽窗的标题位置、两空卡高度、14 pt 提示、禁用操作，以及空状态 → 等待译文 → 译文 → 新空会话；原有长句、选词、固定 / 跟随与无新 OCR 缩放检查继续执行。短句实际原文卡高可随标题控件和内容增长，不强制等高。

实际命令：

```bash
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh PreviewLayoutTests .build/empty-reading-20261011/PreviewLayoutTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh DragSelectionTests .build/empty-reading-20261011/DragSelectionTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh SourceHoverTests .build/empty-reading-20261011/SourceHoverTests
FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh WorkspaceStressTests .build/empty-reading-20261011/WorkspaceStressTests
python3 scripts/debug.py check
```

本轮日志统一位于 `.build/empty-reading-20261011/`。上述 UI 测试使用既有隔离机制、合成数据和临时学习库，不读取真实 Key、不连接采集设备或发起真实翻译请求。用户之前已明确安排当前桌面测试时段。真实游戏的空状态到首句体验尚未在本轮验收；最短检查是打开实时页确认标题左上，开始翻译后确认原文阅读与固定操作恢复，中文译文保持较大的正文。

本轮最终四组 UI 套件全部执行通过，日志为上述目录的 `<套件名>.log`，包含新增空状态回归与 200 次工作区交互。`python3 scripts/debug.py check` 已实际执行，但在 `CaptureCardOfflineTests` 的强制重建并行核对中超时退出 1，不能记为完整核心检查通过。此前五项离线子测试通过；正向并行子进程在 120 秒后超时，报告 `.build/debug/20261011T091442Z-bc76a3/summary.json`。对子进程采样显示停在 `FYCheckLoadImage → CGImageSourceCreateWithURL → ImageIO → __open`，尚未进入 OCR，更未创建实时页面；系统读取阻塞的完整原因未确认。采样保留在 `.build/empty-reading-20261011/offline-timeout-sample.txt`，仅清理本轮两个超时合成检查子进程，未修改离线算法、扩大文件权限或停止其它任务。

已执行 `FY_BUILD_NUMBER=55 bash scripts/install-app.sh`，本机 0.2.1 build 55 安装、双架构 / dSYM UUID 与签名检查通过。安装日志 `.build/empty-reading-20261011/install.log`，核对结果 `.build/empty-reading-20261011/installed-verification.json`。现有凭据仅检查元数据；文件 / 目录权限、大小和修改时间保持不变，未读取内容。正式应用已打开，辅助功能树和当前空状态截图确认中文标题左上、提示使用辅助字号、两卡收紧及固定按钮禁用；未开始真实采集或翻译。公开附件未更新。

并行任务在安装包构建后又更新了 `LiveCaptionTranslator.m` 的翻译服务模型配置方法、`FYLearningAnalyzer.m` 和 `FYTranslationServiceView.m`；本轮空状态修改保持不变。当前工作区整文件哈希不能等同于已安装产物的源码哈希。安装包身份以二进制 / dSYM UUID 和本机实际空状态核对为准，不把其它后续修改宣称为已安装或已验证。

UUID: 27132D8C-558D-3959-99D7-6E5B76BA438C (x86_64) /Users/nanami/Applications/译芽.app/Contents/MacOS/LiveCaptionTranslator
UUID: 84A2DF00-BD72-306E-9958-6607868403AC (arm64) /Users/nanami/Applications/译芽.app/Contents/MacOS/LiveCaptionTranslator

记录时的工作区相关文件 SHA-256（不是已安装产物源码标记）：
- `objc/LiveCaptionTranslator.m`：`fabe8c1e6800c30bfc1dcfdb79e47400db354d307c55f367ebddbd9338f48070`
- `tests/PreviewLayoutTests.m`：`ec04a4db6c99e70422a2bbb534335b33140e2298311bf5b7288986d43a27b55d`
