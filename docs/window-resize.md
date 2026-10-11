# 主窗口边缘缩放与实时画面跳变（本机 build 59）

2026-10-11，Mac 分支 `dev0.2.1_261009`，当前本机版本 0.2.1 build 59。公开附件未更新。前半部分保留 build 58 的外框修补证据；最新的实时画面跳变处理与手动侧栏规则见文末。

## 触发条件与根因证据

用户拖动正式应用 build 56 / 57 的右边缘时，宽度不能变化，或松手后恢复。预期为原生窗口边框跟随鼠标，松手保留尺寸，切换页面不改变用户选择的宽度。

此前窗口最外层 `contentView` 有固定宽度约束，优先级 999；进入实时缩放回调后才停用。原生边缘拖动会先计算允许的窗口尺寸，所以开始回调里的停用来不及解除边界限制。真实鼠标诊断中，高度发生变化而宽度仍停在 1320 pt。仅把约束降到 499 虽能打开横向范围，部分页面仍会在松手后被内部布局挤回更小尺寸，因此没有采用这个中间方案。

本机忽略目录中的诊断探针测得：固定宽度约束优先级 501 至 999 时，原生宽度下限和上限都是 1320 pt；499 时范围打开。诊断使用的 AppKit 私有尺寸查询只存在于本机测试产物，没有加入生产代码或永久回归测试。优先级记录为 `.build/window-native-priority-bounds.log`。

永久回归 `MainWindowResizeTests` 不调用缩放开始／结束回调，不停用生产约束，直接以 AppKit 拖动优先级申请外层宽度，再释放申请。将该测试放入 build 56 的冻结源码测试副本，实际请求 1120 pt 仍为 1320 pt，退出码 2；证据 `.build/window-resize-native-boundary-before.log`。源码副本仅作历史复现，维护入口仍是当前仓库。

## 修补逻辑

- `objc/LiveCaptionTranslator.m` 新增 `FYFrameDrivenContentView`。外层窗口仅保留最小尺寸限制，内部页面画布由外层实际 frame 同步宽高；内部固定尺寸约束不再成为原生窗口的上下限。移除实时缩放开始／结束时锁定、释放外层宽度的方案。
- 切换页面时先更新 AI 侧栏适配，并允许顶部说明压缩；保留实时页缩放后重测原文高度的最新改动。
- `objc/FYImmersiveUI.inc` 统一侧栏可展开判断，通常为 960 pt，字幕外观页为 1100 pt，以留出控件空间。用户的侧栏显隐意愿保留，拉宽后恢复。
- `objc/FYAppearanceUI.inc` 将透明度滑块 260 pt 的首选宽度降为低优先级，允许缩到已有的 60 pt 下限。
- `tests/MainWindowResizeTests.m` 覆盖缩窄、拉宽、释放后保持、六页切换、AI 侧栏恢复及程序设置尺寸；注册到 `scripts/run-checks.sh`。翻译服务测试移除人为调用旧缩放回调的两处辅助代码，继续验证真实生产视图。

保留已完成的翻译服务组件、10 个预设、输入模型和列表／链接图标，以及实时阅读卡片的中文优先、空状态高度、原文选词与换行实现。没有整文件覆盖其他聊天的改动。

## 自动检查

以下均已实际执行通过，使用隔离数据；没有连接设备、读取真实 Key／学习数据库或消耗真实 API Token。

| 命令 | 结果与证据 |
| --- | --- |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh MainWindowResizeTests` | 退出 0；`.build/window-resize-final-ui.log` |
| `FY_TEST_ALLOW_UI=1 .build/release/MainWindowResizeTests`（再执行三次） | 均退出 0；`.build/window-resize-final-repeat-{1,2,3}.log` |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh PreviewLayoutTests` | 退出 0；`.build/window-resize-final-PreviewLayoutTests.log` |
| 同上，套件 `SettingsInteractionTests`、`TranslationServiceViewTests`、`WorkspaceStressTests` | 均退出 0；`.build/window-resize-final-<套件名>.log`；压力套件包含 200 次交互 |
| `python3 scripts/debug.py check --timeout 300` | 退出 0；111 项执行记录通过，318 个源码指纹保持一致；`.build/debug/20261011T104307Z-98cf8f/summary.json` |
| `FY_BUILD_NUMBER=58 bash scripts/package-app.sh` | 退出 0；双架构构建及 dSYM UUID 校验通过；`.build/window-resize-build58-package.log` |

## 已安排桌面时段的真实鼠标验证

在用户明确批准的桌面测试时段，打开使用生产视图和合成数据的「译芽 · 横向缩放修补隔离测试」。真实鼠标横向拖动产生连续原生尺寸事件，宽度从 720 至 1461 pt；松手保持所选宽度。新结构测得原生宽度范围为 720 至 100000 pt。

用户确认「窗口边框连续，内部侧栏或卡片突然换布局」。这与窄窗口适配触发时收起侧栏、卡片换列相符，本轮保留该适配行为。随后在实际鼠标调整到 905 pt 的隔离窗口中切换实时翻译、字幕外观与翻译服务，三页截图几何宽度均为 905 pt，没有因切页改变外框宽度。

仅保存尺寸、约束和事件元数据：`.build/window-resize-native-fixed-events.jsonl`。没有保存真实画面、对白或 Key。此项是真实鼠标操作的隔离窗口验证，不等同于正式安装包的用户体验验收。

## 本机安装及核对

已备份 build 57，安装并重新打开 `/Users/nanami/Applications/译芽.app` 的 0.2.1 build 58。安装前核对当前 318 个源码指纹仍与完整核心检查一致；安装后签名、版本及二进制 SHA-256 与已验证的签名暂存包一致。

- x86_64 UUID：`1DD47B38-0952-3027-9147-7733FDBE579E`
- arm64 UUID：`2A5244AF-C2D0-3998-8941-B9CDE04FDCC6`
- 安装与启动记录：`.build/window-resize-build58-installed.json`
- build 57 备份：`.build/app-backups/译芽.app.bak.window-resize-20261011-185257`

API Key 仅检查文件元数据；文件 0600、目录 0700、修改时间与 inode 在安装及重新启动后均未变化，未读取内容。正式应用已打开并处于暂停状态，没有在安装核对中启动新采集或服务测试。

## build 58 后续反馈与历史验收边界

build 58 后续正式用户反馈确认外框能连续拖动，但实时画面卡片仍突然变布局。此问题继续处理如下。未在另一台 Mac、真实采集卡或长时间翻译运行中验收。自动检查、隔离窗口拖动与本机安装分别记录，不能互相代替。

当时 build 58 的验收要求为：从右边缘缩窄、拉宽并松手，再切换「字幕外观」「翻译服务」，外框应连续变化且保持尺寸；内部适配切换暂时保留。用户随后明确要求消除实时画面跳变，并选择侧栏只手动开关，最新验收要求改为文末 build 59 的步骤。

## build 59：按用户选择，AI 侧栏仅手动开关

正式 build 58 的外框已连续变化，但用户指出从右下角拖动时「实时画面」卡片仍跳变。新增生产视图回归测得：窗口从 960 缩到 958 pt，AI 侧栏被自动收起，画面宽度从 390 突然变成 708 pt，高度从 219.5 变成 398 pt；测试退出 2，见 `.build/window-preview-continuity-before.log` 与 `.build/window-preview-continuity-root-cause.json`。这是侧栏自动释放 320 pt 导致的几何跳变，原有比例测量正确，外框也没有回缩。

用户明确选择「侧栏只手动开关，拖窗口时保持布局」，因此取消根据窗口宽度自动切换 AI 侧栏的行为，取代 build 58 的侧栏适配方案。`FYImmersiveUI.inc` 只按玩家手动选择显隐；`LiveCaptionTranslator.m` 为外层内容保存可更新的最小宽度约束。侧栏展开时内容最小宽度为 1100 pt，收起时为 720 pt；六页共用同一规则，切页不改变已允许的窗口宽度。从窄窗口手动展开时放宽窗口；仍复用同一聊天视图、会话和草稿。实时画面继续按实际画面比例随工作区宽度变化，最高 480 pt，没有加入缩放动画或延迟更新。

视觉规范及提示词同步到工作区 `docs/design/pixel-adventure-spec.md` 与 `pixel-adventure-prompt.md`。保留最新阅读卡片与翻译服务功能。其它设置组件原有的窄宽换行／换列规则仍保留，本次用户指定的修补对象是实时画面及 AI 侧栏。

新增回归在旧 960 pt 阈值和新 1100 pt 最小宽度附近反复申请相邻尺寸，检查画面宽高连续、展开侧栏不会自行关闭、手动关闭后不会因拉宽重开；同时改变宽高以覆盖右下角缩放，检查窄窗手动展开及六页保留尺寸。已有窄窗测试改为先手动收起侧栏，继续验证真实的 720 / 980 pt 尺寸，不将被最小宽度约束拦住的请求算作窄窗检查。独立翻译服务组件的 400 pt 紧凑表单检查仍保留。

| 实际命令 | 最终结果 |
| --- | --- |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh MainWindowResizeTests` | 退出 0；`.build/window-preview-manual-final-MainWindowResizeTests.log` |
| `FY_TEST_ALLOW_UI=1 .build/release/MainWindowResizeTests` | 复跑退出 0；`.build/window-preview-manual-final-repeat.log` |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh PreviewLayoutTests` | 退出 0；`.build/window-preview-manual-PreviewLayoutTests.log` |
| 同上，`SettingsInteractionTests`、`TranslationServiceViewTests`、`WorkspaceStressTests` | 均退出 0；`.build/window-preview-manual-<套件名>.log`；200 次工作区交互包含真实窄窗范围 |
| 同上，`ImmersiveLearningTests` | 初轮仍假设三栏可缩到 1000 pt，因新最小宽度而失败；改为先手动收起后继续验证 1000 → 1150 pt 的尺寸增长，最终退出 0；`.build/window-preview-manual-final-ImmersiveLearningTests.log` |
| `python3 scripts/debug.py check --timeout 300` | 最终退出 0；111 项执行记录通过，318 个源码指纹与最终代码一致；`.build/debug/20261011T110528Z-d35613/summary.json` |
| `FY_BUILD_NUMBER=59 bash scripts/package-app.sh` | 退出 0；双架构构建和 dSYM UUID 核对通过；`.build/window-preview-manual-build59-package.log` |

完整 `PixelAdventureUITests` 未通过，停在「a selected long card must show the 已选中 badge」。在临时测试副本中恢复并核对两个生产文件及该测试的 build 58 源码哈希后，同一断言也失败；见 `.build/window-preview-build58-visual-baseline.log`。这是已有失败，不将完整视觉套件计为通过，也未扩展修改该徽标功能。

已备份 build 58，安装并重新打开正式 0.2.1 build 59。安装前核对最终源码指纹；安装后版本、签名、SHA-256、双架构 UUID 与已验证暂存包一致。正式 UI 已操作「收起 AI 伙伴」「展开 AI 伙伴」，确认聊天内容显隐正确，两次操作保持 1320 pt 窗口宽度；没有启动采集或新服务请求。安装及启动后 API Key 文件权限、目录权限、mtime 与 inode 保持不变，未读取内容。

- x86_64 UUID：`A7232CA2-47C7-3C8A-AF2D-0373093AA58F`
- arm64 UUID：`936BB822-444B-371E-8BE3-14B61357D93C`
- 安装与核对：`.build/window-preview-build59-installed.json`
- build 58 备份：`.build/app-backups/译芽.app.bak.preview-manual-20261011-190730`

正式 build 59 的真实鼠标体验仍待用户确认。最短验收：在实时页从右下角缩窄、拉宽，侧栏应保持当前状态、实时画面连续等比变化；展开时拖至 1100 pt 会停在最小宽度。点击「收起 AI 伙伴」后可继续缩到 720 pt，拉宽也不会自动展开，需再点按钮。另一台 Mac、Intel 实机、真实采集卡与长时间运行未在本轮验收。
