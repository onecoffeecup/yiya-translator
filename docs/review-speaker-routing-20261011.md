# 姓名栏与混合路由六条审查记录

2026-10-11，Mac 分支 `dev0.2.1_261009`。审查对象为姓名排除提交 `163e48f` 和混合路由提交 `a6ad14b`。先逐条判断，再对需要修改的项新增失败回归或核对调用证据，分别提交。

本轮修改已在源码中完成验证；未打包、安装、推送或公开发布。本机只读核对仍为 **0.2.1 build 67**，这些新提交尚未进入已安装应用。源码检查、已安装版本及用户体验的状态分别见[维护记录](project-maintenance.md)。

## 六条判断与提交

| 审查意见 | 判断 | 理由与处理 | 提交 |
| --- | --- | --- | --- |
| 1：句尾粘连按钮没有缺口记录 | 改 | 既有 Replay 支持精确登记失败，最小文字夹具成本低；记录功能缺口，继续保留正常句尾，不恢复易误杀的截断启发式。 | `64c3316` |
| 2：画面边缘姓名栏采样失败 | 改 | 正文与姓名底色采样都遇到越界即失败；底边正文和左边紧字框分别复现。跳过越界点，并要求至少 60% 网格点有效。 | `223f66f` |
| 3：姓名栏剥除连带删去自报姓名 | 改 | 两个录入方向均在原实现失败；同一个比较键最多解释一行姓名栏，后续同名正文应保留。 | `82a45df` |
| 4：同帧重复计算分离对白区域 | 部分改 | 默认生产链路实际计算三次，关闭诊断时仍会求值日志参数。只移除这次无用计算；模式判定与分流仍各算一次，不加缓存或状态。 | `4ebd835` |
| 5：裸数字阈值 | 不改 | `FYContentRouter.m` 没有既有常量区，当前风格为局部阈值与注释；为这些数值单独建立命名体系收益有限。数值保持原样。 | 无 |
| 6：语言设置直接读 UI 控件 | 部分改 | 两条生产调用链均回到主队列，没有当前线程故障。给过滤入口补主线程约定，保留接口与语言读取时机。 | `54cfec0` |

五个提交的说明均注明对应审查意见编号，只影响 Mac 分支。

## 第 1 条：登记仍失败的产品行为

`dialogueTextWithoutTrailingButton:` 在 `a6ad14b` 后只 trim。单独识别的按钮可按几何过滤，但同一个 OCR item 中的 `思い出した。使用` 没有按钮角色边界，当前请求仍带 `使用`。输入文字本身不能证明这两个字属于控件，因此不恢复旧截断。

新增[已知缺口夹具](../tests/fixtures/replay/known-gaps/fused-trailing-button.json)，走生产 timer、稳定、路由和请求构造；mock 只提供合成译文。第二帧在零起始 step 1 断言请求 `sources` 应为 `["思い出した。"]`，实际为 `["思い出した。使用"]`；`known_gap` 精确登记步骤、消息、预期和实际。同时补充[OCR 稳定合同](inline-ocr-stability.md)说明。

统一检查两遍均严格匹配该失败，登记的产品缺口从 0 增至 **1**。两条 `known_gap_reproduced` 是同一夹具重复执行，不是两个缺口，也不表示已修复。没有验证真实画面的控件角色分离。

## 第 2 条：越界点不再否决全部证据

`FYPlatePixel` 对超出 `[0,1)` 的坐标返回 NULL，没有钳制。旧 `FYPlateBodyHasDistinctBackdrop` 在扩边正文采样遇到 NULL 即返回 NO。复用合成图片的 `EmbeddedImage` / `EmbeddedBox`，让正文下边缘贴画布底部，原代码在标记姓名栏的断言失败；日志 `speaker-before.log`。

`FYPlateDominantColor` 有相同问题。把姓名字框完整保留在左边缘，只让用于确认底色的扩边越界；正文采样已修、底色采样仍为旧实现时，该断言继续失败，日志 `speaker-dominant-before.log`。这是区分两处采样根因的局部对照，不另建生产算法。

修改[FYOCRManager.m](../objc/FYOCRManager.m)的两个采样函数：NULL 点跳过，不计入比例分母；7×9 网格至少 60% 有效，即至少 38 点。姓名底色 55% 同色门和正文 80% 差异门仍按有效点计算，颜色容差保持原值。

[SpeakerPlateTests.m](../tests/SpeakerPlateTests.m)新增 8 条断言，覆盖底边正文、左边紧字框、正文保留和有效样本不足反例，最终共 49 条通过。上方及右侧外部边界仍要求 10 点全部可见且至少 8 点不同；姓名框本体被截断或缺少这些边界证据时仍可能不确认。本轮不声称覆盖所有贴边几何、透明姓名栏或真实游戏样式。

## 第 3 条：保留正文里的自报姓名

旧 `FYDialogueBodyExcludingLabels` 从首行起持续剥除所有匹配 keys 的行，导致姓名栏和正文首行同为 `青木` 时剥除两行，破坏两次录入之间的正文比较。

[LearningTests.m](../tests/LearningTests.m)用两个隔离 store 验证生产 `recordDialogueText:excludingSpeakerLabels:`：

| 录入方向 | 原实现实际行为 | 修复后实际行为 |
| --- | --- | --- |
| 先录入 `青木\n青木\nそう呼んでください。`，标签为空；再录入 `青木\nそう呼んでください。`，排除标签为青木 | 错误复用旧身份，源文仍有两行青木，持久化仅 1 条。 | 返回新身份，源文为一行青木加正文，保留旧快照，持久化 2 条。 |
| 先录入一行青木加正文并确认标签；再录入两行青木加正文，标签为空 | 错误创建新身份，源文有两行青木，持久化 2 条。 | 复用已确认纯正文身份，源文不变，版本仍为 1，持久化 1 条。 |

失败日志 `learning-before.log` 同时包含两个方向；修复后日志 `learning-final.log` 分别为 `same_identity=0` 与 `same_identity=1`。修改[学习协调器](../objc/learning/FYLearningCoordinator.m)：复制比较键到可消耗集合，每剥一行就移除该键，每个键最多剥一行，签名和其他调用点保持不变。原 `TestSpeakerExcludedHistory` 与整个学习套件仍通过。

这验证录入、身份和合成持久化行为；未迁移、清理或改写真实用户数据库，也未把自动检查算作最近台词的现场验收。

## 第 4 条：只减少关闭诊断时的第三次计算

`looksLikeUIFrame:` 与分流各调用一次 `separatedDialogueItemsInItems:`。此外，主循环给 `FuyiDiagLog` 传入 `LooksLikeUIFrame(ocrBlocks)`；C 函数参数先求值，诊断函数内部的提前返回不能阻止这次计算。

[TranslationTracePipelineTests.m](../tests/TranslationTracePipelineTests.m)临时计数真实生产类方法，运行完整 `TraceCycle` 后恢复原实现。原代码输出 `Mixed routing calculation count: 3` 并失败，日志 `routing-count-before.log`；修复后为 2，且同一帧字幕交付成功。

修改[LiveCaptionTranslator.m](../objc/LiveCaptionTranslator.m)：用已有 `FuyiDiagEnabled()` 包住诊断统计和日志调用。没有修改路由签名、引入状态或记忆化。开启诊断时仍有额外计算，未做耗时基准或声称明显提升帧率。

## 第 5、6 条：保留风格与调用边界

第 5 条未改生产文件或测试；相关模块回归继续使用原数值验证。本轮没有为可读性进行无关重构。

第 6 条修改 `LiveCaptionTranslator.m` 中 `shouldIgnoreInlineText:...strict:` 与 `filteredInlineTextItems:` 的注释，明确过滤读取 `languageControl`，必须在主线程调用。实时 OCR 与手动界面 OCR 的两个生产入口均在 `dispatch_get_main_queue()` 回调内；此前后台 OCR 的 `languageSegment` 快照属于另一个时点，不据此改变过滤接口。统一检查与生产链路回归通过；没有新增运行时线程断言，也未验证假设中的后台调用。

## 实际执行与结果

以下为代码审查期间已执行的命令，文档同步没有重新运行它们。模块与生产链路的独立最终检查在隔离 checkout 完成，随后提交进入目标分支；最终统一入口和学习／历史检查在目标分支执行。桌面历史检查已获用户授权，使用临时学习库。

| 命令 | 实际输出与退出状态 | 私有证据 |
| --- | --- | --- |
| `bash scripts/run-module-tests.sh` | 退出 0；OCRPostprocessingTests 274、ContentRouterTests 200、SpeakerPlateTests 49 条断言全部通过。 | `module-isolated-final.log` |
| `bash scripts/run-learning-tests.sh` | 退出 0，`Learning tests passed`；两个新增录入方向及原历史排除断言均通过。 | `learning-final.log` |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh HistoryDedupTests` | 退出 0，OCR dialogue deduplication／options／corrections／genuine changes／five-record retention 通过。 | `history-dedup-final.log` |
| `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh HistoryRetentionTests` | 退出 0，`History retention tests passed (12 checks)`。 | `history-retention-final.log` |
| `bash scripts/run-translation-trace-tests.sh` | 退出 0，`TranslationTracePipelineTests` 通过；关闭诊断时计数 2，生产字幕正常交付。 | `translation-trace-isolated-final.log` |
| `python3 scripts/debug.py check` | 退出 0，`baseline_passed_with_known_gaps`；168 条记录中 166 条 `passed`、2 条 `known_gap_reproduced`，产品缺口 1 个，`source_unchanged=true`。 | `.build/debug/20261011T141946Z-f2f2a5/summary.json` |

表中单项日志位于本机忽略目录 `.build/review-six-20261011/`，提交清单与命令核对在该目录的 `verification.json`。真实资料不进入 Git 或发布包；此处只记录合成案例和统计结论。

最初隔离环境的 `debug.py check` 在 `CaptureCardOfflineTests` 的并行强制重建阶段超时（180 秒），退出 1，未记为通过。最终目标分支的默认统一入口通过该套件。最终报告记录检查时工作树的 380 个源码／脚本／夹具／媒体散列；当时存在其他任务的未提交检查脚本，报告验证的是该工作树，不能把整个报告说成只对应这五个提交。文档更新只核对内容、链接和证据，不算新的核心、桌面或设备验收。

## 线上影响与最短手动验收

源码提交不会改变已经安装或公开分发的应用。本轮未安装、未发布，当前无需为这些提交重新验收现用 build 67。以后安装包含本轮提交的版本时，第 2、3 条会改变边缘姓名栏确认和同名正文的身份处理；第 4 条减少默认路径的一次诊断计算，第 1、6 条仅补缺口与调用约定，第 5 条未改。

安装新版本后，做两组定向检查即可覆盖本轮主要体验边界：

1. 用常玩的游戏让对白框贴底边或左边，确认独立姓名栏被排除；再推进一条短对白和正文中提到人名的对白，确认文字完整。
2. 找姓名栏和正文首行同名的自报姓名句，确认原文、译文及最近台词保留正文中的名字；推进后再查看最近列表，确认没有带两行同名的新版本或重复身份。

build 66 已获用户确认的历史验收保持其原范围，不因这轮源码回归自动扩展。真实设备、其他游戏样式、Intel 实机、另一台 Mac 和长时间运行尚未在本轮验证；句尾粘连按钮仍是明确登记的未修复缺口。
