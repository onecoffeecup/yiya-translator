# 内容路由模块

2026-10-11 将已有对白与贴译规则提取到 FYContentRouter。本轮是保持行为的模块化：没有调整 UI 优先级、阈值、跨帧确认、空字幕带退回、词表或请求取消策略。

完整规则和待审查边界见 [对白与贴译判定规则](dialogue-inline-mode-rules.md)。模块化不代表这些边界已经修复。

当前追加状态：2026-10-11 的引用词缺失修补已进入本机 0.2.1 build 51，用户确认该句复测正常。首遍完整引用的保护属于 `FYOCRManager`；同一行横向短片段的收录、排序和串接属于 `FYContentRouter`。下文 build 44 的检查与安装保持历史记录，最新验证见 [引用词修复](ocr-refinement-quotation.md)。

## 职责

| 位置 | 负责内容 |
| --- | --- |
| [FYContentRouter.h](../objc/FYContentRouter.h) 与 [FYContentRouter.m](../objc/FYContentRouter.m) | 整帧模式判定、模式候选状态、对白字幕带、姓名与注音、对白与选项分流、正文过滤、同句与对白稳定策略、轮询及同文重试间隔 |
| [FYOCRManager.m](../objc/FYOCRManager.m) | Vision、区域映射、双遍合并与精读结果选择、完整源图独立姓名栏角色证据、源观察去重、弹窗范围、通用文本稳定计数和界面字段跨帧跟踪 |
| [LiveCaptionTranslator.m](../objc/LiveCaptionTranslator.m) | 按原顺序调用规则，处理采集会话、交互面板、在途请求、缓存、学习身份、取消及迟到交付、实际窗口显示 |
| [FYLearningModels.m](../objc/learning/FYLearningModels.m) | 共享对白比较键和学习模型；比较键通过纯函数回调提供给路由模块，不复制算法 |

规则模块不发起采集、Vision 请求、网络、窗口操作或凭据读写。它接收共享 OCRTextItem；公开头文件只依赖 Foundation、CoreGraphics 及模型前向声明。实现使用 OCR 模型和既有空白归一化函数，不引入新的 OCR 或学习数据库。

每个主控制器各持有一个 FYContentRouter。模块的 modeStability 与主控制器原有 detectedModeSegment、candidateModeSegment、candidateModeHits 访问器共用同一份状态，没有新增第二套候选计数。该状态仍在原串行调用上下文使用。

## 输入与输出

- modeDecisionForItems:fallback: 返回本次原始分类和原因，不能将它与两次确认后的已提交模式混淆。
- observeModeForItems:locked: 返回已确认模式；锁定时不推进或清空候选。主循环继续保留原来的面板锁定闸门和测试覆盖入口。
- dialogueRouteForItems:optionsCanPasteInline:filterObserver: 返回 bandItems、dialogueItems、optionItems、dialogueText、speakerLabelOnly 和 usedFullFrameFallback，允许对白与选项两组同时非空。
- 空对白数组仍按旧行为使用整帧文本提取；采集卡映射不可用仍只使用字幕带，不单独贴选项。
- filterReasonForText 返回保留或过滤原因；模块不写日志，主控制器的可选观察回调保留原有纯标点诊断，仍只输出文字长度。
- isSameSubtitleText、isStableText 显式接收模式、是否日语、已显示文本和比较键，不读取界面语言控件或全局应用状态。日语路径复用 FYDialogueComparisonKey；英文路径不使用该回调。
- 路由结果复制数组，但保留 OCR 项身份；不修改输入文字、框或元数据，不发出翻译任务。

原因标识为诊断与审查服务，例如 ui_evidence、dialogue_band、central_fragment、mode_locked、dialogue_with_options、full_frame_fallback。它们不是新增产品模式，也不是用户界面文案。

## 保持的边界

1. 整帧 UI 仍优先于对白判定；混合分流仍只在对白路线内调用。
2. 模式仍使用全部合并 OCR，整帧界面分组仍使用弹窗筛选结果。
3. 正文过滤仍在模式判定之后，对白文本稳定仍在混合分流之前。
4. 主控制器保持几何、分组、已显示同文、在途同文、节流和稳定门的执行顺序。
5. 仅在 beginContentTranslation 或模式、输入等原有作废边界取消任务；没有把取消移动到路由模块。
6. 打开的选择列表和阅读卡保护、源观察身份、缓存以及真实显示的责任没有转移。
7. 混合选项仍不经过整帧界面的字段稳定器。模块提取没有修正短英文过滤或 N2 整批取消；N2 后续在主控制器和请求 owner 中局部修正，见 [在途长正文规则](inline-ocr-stability.md#在途长正文与独立短字段)，不改变此模块职责。

FYOCRManager 的原内容规则类方法保留为转发接口；主文件中旧 C 测试入口也转发到 FYContentRouter。规则实现只有一份，旧接口不保留算法副本。

scripts/lib-sources.sh 将新实现纳入发布、生产链路、OCR、离线采集检查和测试的公共源码清单，防止出现测试使用新规则而发布构建漏掉模块的情况。

## 检查

后续同行片段回归已将 `ContentRouterTests` 扩充到 181 项断言：两种映射入口、行首/中/尾、观察乱序、对白与远处选项并存，以及姓名栏、注音、多行和不同位置反例。`dialogue-horizontal-quoted-fragment.json` 走完整生产主循环，验证窄片段进入实际请求及学习原文，静止六帧只形成一个身份和一次请求；修复前该原文断言失败。本机 build 51 对应统一核心检查 111 项记录通过，详见上方追加记录。以下计数属于初次模块提取时的历史检查。

新增 [ContentRouterTests.m](../tests/ContentRouterTests.m) 直接测试生产模块：34 条断言覆盖同时输出对白和选项、映射不可用、整帧退回、文字与几何不变、过滤原因与诊断回调、候选模式锁定、独立状态、日英同句判断、两帧与三帧稳定及原间隔。

新增 [mixed-dialogue-options-auto-mode.json](../tests/fixtures/replay/mixed-dialogue-options-auto-mode.json) 走生产主循环与自动模式：两次观察后同时请求两个选项和一段对白，持有两个 HTTP 回复，先交付对白再交付选项，静止帧不追加请求。断言包括请求源文、字幕、原位贴译、待回包索引和取消次数。服务和 AppKit 终点均为隔离测试边界，不连接真实服务、游戏窗口或设备。

迁移前的 OCRPostprocessingTests 为 228 条断言通过，迁移后同样通过。19 个原 OCR 策略方法逐字保持；整帧分类只将既有返回值封装为含原因的结果。机械比对记录在忽略的 .build/content-router-refactor-20261011/mechanical-review.json。

已执行的最终检查：

- `python3 scripts/debug.py replay tests/fixtures/replay/mixed-dialogue-options-auto-mode.json --repeat 2 --timeout 300`：两遍通过；报告 `.build/debug/20261011T044432Z-e5be70/`。
- `python3 scripts/debug.py check --timeout 300`：退出 0，85 项记录通过，2 项为既有 N2 缺口的重复复现，状态 `baseline_passed_with_known_gaps`。模块中的 228 条 OCR 断言和 34 条路由断言、采集卡离线检查、生产链路、布局和全部 Replay 均执行；283 个源码、脚本和夹具散列在检查期间保持不变。报告 `.build/debug/20261011T044625Z-da957c/summary.json`。
- `bash scripts/build-app.sh`：退出 0，arm64 和 x86_64 正式构建均编译链接成功，二进制与 dSYM UUID 核对通过。日志 `.build/content-router-refactor-20261011/release-build.log`。主文件仍有 7 条原有未使用辅助函数警告，没有新增路由模块编译警告。
- `git diff --check`：通过。规则稿链接、当前源码位置和散列已同步；共享源码清单检查通过。

模块提取与上述自动检查没有调用真实翻译接口或连接采集设备。测试终点验证交付数据，不证明真实浮窗已验收。

## 本机安装

2026-10-11 按用户要求执行 `CODESIGN_IDENTITY=- ARCHS='arm64 x86_64' bash scripts/install-app.sh`，退出 0，安装到 `~/Applications/译芽.app`，版本 0.2.1、build 44。构建号来自 Git 提交数；本轮未提交，构建号保持不变。

已核对安装应用、打包产物、正式二进制及 dSYM 的双架构 UUID 一致，签名严格校验通过；安装后 283 个源码、脚本与夹具散列仍匹配上述核心检查。安装前后本机 API Key 文件与目录元数据保持不变，没有读取或输出真实 Key 内容。应用已打开，主窗口显示「已暂停」和「开始翻译」，未启动采集或翻译。记录在忽略的 `.build/content-router-install-20261011/installation.json` 与 `install.log`。

本轮未提交、推送或公开发布，实机验收仍待用户测试。最短检查：开始翻译，查看对白与选项同时出现时的字幕和贴译，再切到纯菜单并返回对白，确认切换与原来一致。


## 后续修复：独立姓名栏错读

现场追加：build 61 的 extracted 已去掉姓名，学习身份却把旧姓名作为完整源文补回。当前主循环向学习层传递确认角色，同正文清理和短暂漏认分别有生产 Replay；该修补不改变普通残缺帧与选项规则，详见 [对白姓名排除](dialogue-speaker-exclusion.md)。

当前合同追加：用户于 2026-10-11 要求对白不包含说话人姓名。所有已确认独立姓名栏统一从对白文本和比较中排除，已知姓名也不再随正文送往翻译 / 学习；正文提到的人名仍保留。紧字框与半透明正文的像素确认已补充。以下“明确姓名继续参与身份”及 build 44 记录保留历史含义，当前验证见 [对白姓名排除](dialogue-speaker-exclusion.md)。

模块提取后，用户报告未知姓名栏的 OCR 错读进入正文，导致翻译多出无关词，同一正文占据多个最近台词。已授权文字采样与生产 Replay 共同定位了入口；真实文字及数据库检查结果只在本机私有目录保存。

日语实时链路在双遍合并、完整源图坐标回映后，由 `FYOCRManager` 用已有源图验证独立填色姓名栏。只复制观察并标记角色，不改文字或框；`FYContentRouter` 负责在对白正文中排除标记为姓名栏、但不满足现有明确姓名规则的行。主控制器在对白稳定、在途及已显示比较前使用同一排除规则，因此错读变化不会再次创建请求和学习身份。明确姓名继续参与原文及身份，不能把不同人物的同文合并。

没有正向像素证据时保持原行，普通假名、英文、重复字符和短对白不会单凭文字形状被排除。源图与局部裁剪坐标不混用。普通背景、无界色块与姓名栏下短对白有反例测试；透明或纹理姓名栏等未验证情形沿用旧规则。本修复不调整整帧 UI 优先、选项分流、两帧模式确认或学习库五条保留策略；同工作区的 N2 后续修复独立记录在上文链接。既有历史记录不自动删除或改写。

新增 [SpeakerPlateTests.m](../tests/SpeakerPlateTests.m) 33 条断言，以及 [speaker-plate-ocr-noise.json](../tests/fixtures/replay/speaker-plate-ocr-noise.json) 的十帧加一次显式回包的生产主循环回归。后者修复前第二帧的完整请求源文断言失败，修复后验证在途时未知姓名栏变化只请求一次且不取消、回包正常交付、学习原文纯净、不同明确姓名同文保留三个身份。此前专项两遍通过记录在 `.build/debug/20261011T051421Z-0f3fd0/`；最终统一检查与本机安装另行记录。

### 姓名栏修复的最终验证与安装

- 最小失败回归：`python3 scripts/debug.py replay tests/fixtures/replay/speaker-plate-ocr-noise.json --repeat 1 --timeout 300`，修复前请求原文断言失败；报告 `.build/debug/20261011T050725Z-03edc5/`。
- 最终专项：`python3 scripts/debug.py replay tests/fixtures/replay/speaker-plate-ocr-noise.json --repeat 2 --timeout 300`，包含在途变化与显式回包，两遍通过；报告 `.build/debug/20261011T052231Z-97a1d6/`。
- 统一入口：`python3 scripts/debug.py check --timeout 300`，退出 0，99 项记录全部通过，状态 `passed`。包含 33 条姓名栏检查、原 228 条 OCR / 34 条路由检查、采集卡离线 OCR、生产链路、布局及全部 Replay；298 个源码/媒体散列全程不变。报告 `.build/debug/20261011T052728Z-195c57/summary.json`。该当前工作区还包含另一任务独立修复的 N2，详见其记录；早前模块提取的 85 项通过、2 项缺口是历史状态。
- 既有用户附件在内存中验证：截图实际姓名栏的三组 OCR 框均得到角色标记，原观察不变；没有保存新画面。该像素检查不等于安装后真实 OCR 和浮窗验收。
- `CODESIGN_IDENTITY=- ARCHS='arm64 x86_64' bash scripts/install-app.sh` 退出 0，安装到 `~/Applications/译芽.app`，0.2.1 build 44。双架构构建、dSYM 及严格签名检查通过；安装、打包、正式二进制与 dSYM UUID 全部一致：arm64 `4DF17C31-776F-310C-9EFB-C5E9652CF508`，x86_64 `4B9786BE-424A-3396-95A8-A164036C3783`。保留 7 条原有主文件未使用函数警告，没有新增姓名栏/路由编译警告。
- 安装及打开后，298 个检查散列仍匹配。本机 Key 只核对文件和目录元数据，安装及打开前后保持不变，没有读取或输出 Key 内容。应用已打开，显示「已暂停」「开始翻译」，未代用户开始采集或发翻译请求。记录在忽略的 `.build/history-speaker-diagnosis-20261011/installation.json` 与 `install.log`。

本轮只更新本机，未提交、推送或更新公开附件。文字诊断保持关闭；旧错误历史没有删除或改写。最短实机复验：点击开始翻译，让未知姓名栏与正文停留；确认当前原文只有正文、翻译不再多出姓名栏错字，静止不再新增重复条目。再推进一条正常短对白及明确姓名对白，确认正常显示。实际请求耗时、真实 OCR 稳定性与桌面表现仍待用户测试。
