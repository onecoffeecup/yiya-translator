# Debug 基础设施首版验证记录

日期：2026-10-08。分支 `codex/debug-replay`，在唯一维护仓库实施。此次范围为诊断、Replay、回归与长期规则，不修具体产品 Bug，不安装或发布。

## 实际执行结果

| 检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/debug.py check --repeat 2` | 21 个正常场景各两遍，42 次生产链路 Replay 通过且检查点一致；两项产品缺口各复现两次，严格匹配登记的失败证据。总结果为 `baseline_passed_with_known_gaps`，不是全部产品要求通过。 |
| Debug 工具边界 | 10 项 Python 测试通过：草稿 / 空断言拒绝、时序 / 动作 / 坐标 / 媒体校验、私有输出、日志隐私、进程超时、隔离退出状态、源码包保留规则并排除原始日志与凭据。另有真实 native 失败断言报告测试通过，验证退出 1、步骤和预期 / 实际值。 |
| 现有 headless 检查 | 测试隔离、RuntimeDiagnostics、全部 module 套件、TranslationTrace 单元与生产 timer 集成、DialogueGrammar 检查均通过。没有操作真实设备、读取用户凭据或发送真实翻译请求。 |
| 图片 / 视频 | 合成 PNG 及固定 MP4 指定时间帧，经过真实 Vision 和生产后处理 / 稳定 / 交付链路，各重复两次结果一致；不据此推定其它 macOS、真实游戏或采集卡通过。 |
| 正式应用构建 | `bash scripts/build-app.sh` 成功，产物含 arm64 与 x86_64。现有未使用 helper 警告仍存在；没有安装替换运行版。 |
| UI 套件编译 | `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh InlineTranslationPipelineTests` 与 `CaptureCardInputTests` 编译成功，**没有运行** AppKit / 设备交互断言。 |
| 静态与文档 | Python 编译、shell 语法、`git diff --check`、新工作流及诊断链接检查通过。 |
| CLI 操作 | `debug.py trace` 元数据统计通过；`import-trace` 保留相对帧时间，输出权限 0600，未完成草稿被 Replay 拒绝。 |

本机最终核心报告位于源码根 `.build/debug/20261008T024404Z-d26380/summary.json` 与 `summary.txt`，含精确命令、状态、日志路径、源码 / 夹具 / 媒体哈希、逐场景结果与已知缺口。结束后再次核对当前源码哈希相符。报告与临时 JSONL 不提交或进入发布附件。

## 已确认的产品缺口

- **英文句点被过滤**：期望两个稳定帧后提交一次，实际 0 次。合成文字与真实图片均可观察 raw OCR 保留、extracted 为空；`shouldIgnoreInlineText` 的“有点、无日文字符”分支删除英文。最小目标失败夹具为 `tests/fixtures/replay/known-gaps/english-period.json`。
- **忙时不能保证只展示最新画面**：A 请求保持等待，B / C timer 均被 `inFlight` 阻止采集；随后 A 仍展示。`task_busy`、OCR 次数及字幕检查点提供证据；不能用跨 generation 的迟到响应保护替代同代次快切保证。目标失败夹具为 `known-gaps/latest-frame-while-busy.json`。

单独用 `debug.py replay` 运行上述夹具会失败并退出 1，保留目标行为未满足的事实；核心检查将精确复现单列，不掩盖缺口。后续修复时先读取 DEBUG_WORKFLOW.md，修复后将目标夹具转为普通回归。

## 规则持久化与未验证范围

工作区原 AGENTS.md 追加长期 Debug 规则，既有内容保留；维护仓库根新增 AGENTS.md 与完整 DEBUG_WORKFLOW.md，README 和源码导出白名单均连接这些文件。测试验证导出的源码仍包含两份规则文档，后续克隆或解压源码的新会话可以读取。

真实屏幕 / 相机权限、QuickTime / OBS 设备共享、采集卡驱动与拔插、多屏 / 全屏映射、实际浮窗可见性与遮挡、原生选择交互、长时间运行、其它系统 / 机器及 Intel 实机均未执行。最短手动验收步骤已列入 DEBUG_WORKFLOW.md。无需用户开游戏来验收 Replay 本身；现场体验仍只针对无法自动覆盖的剩余环节。
