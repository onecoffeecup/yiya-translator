# 行首省略号身份稳定 · 2026-10-11

用户在最近台词重复收录修复之后追加核对行首省略号。直接调用生产函数的合成探针确认：连续行首点号可忽略，但点号间夹空白时扫描提前结束，引号后点号不属于原行首扫描范围；帧比较又在共享函数之前删除换行，因此后续行的行首点号与漏识别点号仍可能产生不同键。

预期无害 OCR 点号数量、字符和空白变化，以及行首点号偶发漏识别，复用一个连续对白身份、在途请求和历史显示条目。原始台词与译文快照保留；问号、数字、否定、正文词语、引号类别变化以及 A→B→A 仍分别处理。不扩大到删除所有句中省略号或复用所有历史身份。

## 生产修正

- [FYLearningModels.m](../objc/learning/FYLearningModels.m)：逐行先去空白，再扫描行首装饰点号；保留开引号/括号，仅在后接日文时忽略其中的行首点号，保护括号内小数和非日文记号。已有句中/行尾点号归一继续有效。
- [LiveCaptionTranslator.m](../objc/LiveCaptionTranslator.m)：日语对白在行边界仍存在时生成共享比较键，再用于稳定、在途匹配、节流及已译比较；不改请求原文、学习原文或界面字段的比较键。
- [FYContentRouter.m](../objc/FYContentRouter.m)：日语比较接受非空单字键，避免行首点号去掉后的一字回复永远无法积累稳定确认；空键不构成对白。英文和界面比较保持原长度及相似度门。

学习身份、固定阅读、历史分组与帧门仍共用一个生产比较函数，没有新增模拟算法、角色白名单、数据库删除或迁移。原先提前展平且已经丢失行边界的字符串无法反推出行首；修正在真实生产入口保留边界，而不是猜测句中哪些点号曾位于行首。

## 回归证据

- `bash scripts/run-learning-tests.sh`：新增回归在修复前退出 1，失败于夹空白/引号后/漏识别行首点号应共用身份键；修复后退出 0。验证旧行首变体只显示一张卡、连续收录只持久化一条、译文与固定原文保持不变。日志位于私有忽略目录 `.build/leading-ellipsis-20261011/learning-before.log` 与 `learning-after.log`。
- `python3 scripts/debug.py replay tests/fixtures/replay/leading-ellipsis-history.json --repeat 1`：修复前第 2 步预期 `translation_pending`，实际进入 `waiting`，报告 `.build/debug/20261011T064907Z-4aaa52/`。同一生产 timer 链路的修复后 `--repeat 2` 两遍 31 步通过，报告 `.build/debug/20261011T065026Z-4fe835/`；点号变化期间一个请求/身份、零取消，原文不变；问号变化和真实回现分别提交。
- `bash scripts/run-module-tests.sh`：退出 0，包含开引号/括号与点号变体、纯标点空键、单字键、七组语义区别检查，以及原 OCR、布局、翻译和任务检查。日志 `.build/leading-ellipsis-20261011/modules.log`。随后追加嵌套括号、引号前点号和半角假名断言，由最终统一检查再次验证。
- `python3 scripts/debug.py replay tests/fixtures/replay/leading-ellipsis-short-reply.json --repeat 2`：两遍 7 步通过，报告 `.build/debug/20261011T065156Z-5de690/`。仅剩一字的真实生产比较键仍两帧确认、只提交一次、保留在途请求和原文。
- 最终 `bash scripts/run-learning-tests.sh`：退出 0，日志 `.build/leading-ellipsis-20261011/learning-final.log`。
- 最终在维护目录执行 `python3 scripts/debug.py check --timeout 300`：退出 0，105 项记录全部通过，结果 `passed`。报告 `.build/debug/20261011T065323Z-896a65/summary.json`，包含 162 条内容路由断言、离线 OCR、学习持久化、生产翻译链路、布局及所有 Replay 各两遍；既有 N1、取消对白回现、混合选项和中间行省略号回归继续通过。304 个源码/媒体散列与最终文件一致，索引 `.build/leading-ellipsis-20261011/verification.json`。

全部新夹具使用合成日文与合成译文，隔离数据库和 HTTP，不保存新的真实画面、对白、译文或凭据；没有启用现场诊断。

## 交付范围

用户随后明确要求安装，已从同一维护源码运行 `FY_BUILD_NUMBER=49 bash scripts/install-app.sh`，双架构构建、组装及本机签名退出 0，安装到 `~/Applications/译芽.app` 并启动，版本为 **0.2.1 build 49**。构建、组装包、安装包和 dSYM 的两架构 UUID 一致：arm64 `485D4E02-D7BE-3971-AC38-90374BD8AE83`，x86_64 `C9F91019-9787-3E67-AD1E-9BC283ACDDFF`；`codesign --verify --deep --strict` 通过，运行进程路径属于该安装包。API Key 只核对文件与目录元数据，安装和启动前后均不变，未读取或输出 Key。安装索引及日志在私有忽略目录 `.build/leading-ellipsis-20261011/installation.json` 和 `install.log`，304 个已测源码/媒体散列仍一致。

本轮维护分支为 Mac 开发分支 `dev0.2.1_261009`，公开发布附件未更新。最短手动验收：让一条带行首省略号的多行对白静止，确认字幕更新且最近台词不会反复新增；推进一条实质不同的对白，确认正常更新。自动回放和本机安装不等于实际 OCR 准确率、服务耗时或桌面可见性验收。
