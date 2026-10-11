# 最近台词只收录已有译文的记录 · 2026-10-11

## 需求与根因

最近台词只展示当前版本已有非空译文的记录。等待翻译、翻译失败、请求取消以及仅含空白的译文均不进入列表，也不占用最近 5 条的额度。旧版留下的无译文记录同样适用。

生产流程在提交翻译前调用 `FYLearningCoordinator.recordText:` / `recordItems:`，先创建句子 ID 和版本并存入学习库；翻译成功的有效回调再调用 `setTranslation:forIdentity:`。原 `fetchRecentSentencesWithLimit:` 没有译文条件，`pruneHistory` 则对全部原文取最近 5 条，因此未完成的请求会显示为「暂无该句译文」，并删除更早的成功记录。

新增无界面回归调用实际 `FYLearningStore`：只创建一条原文，然后读取最近台词。修复前 `bash scripts/run-learning-resilience-tests.sh history` 退出 1，失败断言为 `pending original must not appear in recent history`；预期 0 条，实际包含该条未翻译记录。

## 实现边界

- `objc/learning/FYLearningStore.m` 在每个 SQLite 连接注册 `fy_has_translation`，使用 Foundation 的 Unicode 空白/换行字符规则判断译文是否有内容。查询在排序、LIMIT 之前过滤，所以旧版 NULL、空串、换行、全角空格和不换行空格不会占位。
- 历史保留取最近 5 条有译文的记录；另保留原有最近 5 条原文工作集，供在途请求、重试、原文学习和修正使用。两者的并集最多 10 条，已有固定阅读与句子收藏仍独立保留。工作集中的无译文记录不会成为最近台词。
- 回填译文及追加原文版本时，在原有事务内重新清理；回填、清理或提交失败时一起回滚，不能先丢掉旧历史再把失败当成功。最新版本没有译文时，旧版本的迟到回填不会让它进入列表。
- 现有主控制器的运行代次、内容 revision、输入源、窗口和模式检查继续决定译文是否有效；取消或过期的回调不会回填学习库。没有改变 OCR、对白去重、翻译缓存、请求策略、固定阅读或收藏快照。
- 最近台词空列表提示改为「暂无最近台词，翻译成功后会显示在这里。」既有空记录不需迁移或直接改写，刷新时按新规则过滤；此前已经被旧清理逻辑删除的台词无法凭空恢复。

## 回归覆盖

`LearningStoreResilienceTests` 的 `history` 场景覆盖：无译文/Unicode 空白过滤、成功收录、8 条待处理原文不挤掉已翻译的 5 条、工作集有界、译文回填触发清理、清理故障回滚、当前版本与旧版本隔离、关闭重开，以及旧空白记录在 LIMIT 之前过滤。默认 `all` 场景与 `debug.py check` 会执行这些检查。

`TranslationTracePipelineTests` 使用临时学习库与模拟 HTTP，经实际 timer / OCR 后处理 / 身份 / 缓存 / HTTP 解码 / 主线程交付验证：窗口与采集卡两种输入下 A/B 被取消、C 成功，只有 C 进入历史；A/B 迟到成功回复不增加记录。对白、实时界面和手动界面三条路径分别检查失败不收录、后续成功收录。

`HistoryDedupTests` 与 `HistoryRetentionTests` 的历史夹具补齐合成译文，继续验证去重、收藏、固定阅读、清理和原生页面合同；它们属于桌面套件，本轮仅编译，不视为桌面验收。

## 验证与交付

以下命令在 Mac 分支 `dev0.2.1_261009` 的唯一维护源码执行：

| 命令 | 实际结果 |
| --- | --- |
| `bash scripts/run-learning-resilience-tests.sh history` | 修复前退出 1，复现无译文入列表；修复后退出 0 |
| `bash scripts/run-learning-tests.sh` | 退出 0，学习模块检查通过 |
| `bash scripts/run-translation-trace-tests.sh` | 退出 0，包含新加的临时历史库与有效交付检查 |
| `python3 scripts/debug.py check` | 退出 0，111 项执行记录通过；49 个 Replay 各执行两遍；源码哈希未变，无登记缺口 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh HistoryRetentionTests` | 退出 0，仅编译 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh HistoryDedupTests` | 退出 0，仅编译 |
| `FY_BUILD_NUMBER=52 bash scripts/package-app.sh` | 退出 0，arm64 + x86_64 构建与 dSYM UUID 核对通过 |
| `FY_BUILD_NUMBER=52 bash scripts/install-app.sh` | 退出 0，本机签名与安装通过 |
| `git diff --check` 与变更文档链接检查 | 通过 |

核心报告在本机 `.build/debug/20261011T083804Z-36f6c5/summary.json` / `summary.txt`。安装索引、安装日志和只含凭据文件元数据的核对在 `.build/history-translated-only-20261011/`，不进入 Git 或发布包。所有自动检查使用合成内容、隔离数据库和模拟服务，不读取真实凭据或学习库，不连接采集设备，不消耗真实 API Token。

已安装并打开 **0.2.1 build 52**，位置为 `~/Applications/译芽.app`。安装包、源码构建二进制、已安装二进制及双架构 dSYM 的 UUID 一致，已安装应用 `codesign --verify --deep --strict` 通过。安装前后及打开应用后 API Key 文件的大小、mtime、inode 及 0600/目录 0700 权限均未变，未读取或输出 Key 内容。

修补代码与回归已单独提交为 `54cf83b`（`fix(mac): exclude untranslated sentences from recent history`），所属 Mac 开发分支为 `dev0.2.1_261009`。项目入口、Debug 覆盖、发布说明及检查记录随后同步本次交付状态，源码与文档提交到远端同名开发分支。此次开发分支同步不更新公开 Release 附件或 Sparkle 清单；桌面套件只编译，真实服务与游戏体验尚未验收。

最短手动验收：翻译服务暂时不可用时产生一条新对白，刷新最近台词，应保留此前已翻译记录且没有该条失败原文；恢复服务并让新对白翻译成功，再刷新，应显示原文与对应译文。真实服务、桌面可见性与设备验收不由合成检查推定。
