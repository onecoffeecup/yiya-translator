# 译芽 Debug 与回归工作流

每次修复 Bug 前先读本文件。先复现、验证根因、最小修复，再运行回归并报告证据。自动检查验证代码处理与交付；真实设备和用户体验另行验收。

本文件及源码根 AGENTS.md 随 Git 与源码包保留，新 Codex 会话从仓库根进入即可读取。维护者本机的唯一源码为工作区 `.build/yiya-translator-publish-ocj99vs_/fuyi-0.1.0`；其它机器使用正常克隆目录。工作区根仅导航，不能清空包含源码的 `.build/`。

## 数据流与审查基线

完整审查及实施计划见 [架构审查](docs/debug-architecture-audit.md)。关键链路为：

```mermaid
flowchart LR
  T[主线程 timer 与几何复核] --> I[单窗口截图或采集卡最新帧]
  I --> O[工作队列 Vision 裁剪 精读 后处理]
  O --> S[主线程模式与稳定确认]
  S --> D[对白身份与单项缓存]
  S --> U[界面字段稳定与多项缓存]
  D --> H[请求构造 HTTP 解码]
  U --> H
  H --> G[主队列检查运行代次 输入会话 窗口 模式]
  G --> C[对白字幕交付]
  G --> P[几何检查 排版与贴译面板]
```

| 模块 | 入口与职责 |
| --- | --- |
| AppDelegate | `objc/LiveCaptionTranslator.m` 的 `start` / `stop` / `timerFired:` 及翻译、显示编排；不是独立管线框架 |
| 输入 | 窗口 `CGWindowListCreateImage(IncludingWindow)`；`FYCaptureCardInput` 的 AVFoundation 会话、单帧槽与 epoch；QuickTime / OBS 作为显示窗口 |
| OCR | `FYOCRManager` 的 Vision、区域回映、精读与合并、模态过滤、对白与字段稳定 |
| 翻译 | `FYTranslationManager` 的请求构造、15 秒超时、HTTP / JSON 解码、缓存与主线程交付策略；没有独立自动重试队列 |
| 学习状态 | `FYLearningCoordinator` 的句子身份、版本、不完整帧复用及固定阅读；`FYLearningStore` 的 SQLite 持久化 |
| 显示 | `FYWindowManager` / `FYGeometryManager` 的目标与映射；`FYInlineLayout` 的贴译排版；AppDelegate 的字幕、面板、折叠与入口 |
| 诊断 | `FYRuntimeDiagnostics` 元数据内存环；`FYTranslationTrace` 显式启用的文字 JSONL |

对白默认两帧确认，高相似修正三帧；连续同句复用，真正 A→B→A 重新建立身份并请求。失败不缓存，下一周期经过节流可重试：对白 4 秒、界面 1.2 秒。界面字段的确认与保留规则见 [OCR 稳定合同](docs/inline-ocr-stability.md)。

## 快捷命令

以下命令均在源码仓库根执行，需要 macOS 13+、clang / Xcode Command Line Tools 与 Python 3.9+。Debug 不需要接设备、开游戏、填真实 Key、下载 Sparkle 或安装大型平台。

```bash
# 默认核心检查：测试隔离、诊断、模块、生产链路、Replay 与已知缺口
python3 scripts/debug.py check

# 单一场景，默认跑两遍并比较所有检查点
python3 scripts/debug.py replay tests/fixtures/replay/ocr-jitter.json

# 仅 Replay，给全面验收脚本复用；仍检查失败报告和已知缺口
python3 scripts/debug.py check --replay-only

# 元数据统计，不显示对白
python3 scripts/debug.py trace /absolute/private/path/events.jsonl

# 把已授权的文字日志转成私有草稿，需要补 mock 和正确断言
python3 scripts/debug.py import-trace /absolute/private/path/events.jsonl /absolute/private/path/draft.json
```

报告在 `.build/debug/<UTC时间戳>-<随机标识>/`：`summary.txt` 便于阅读，`summary.json` 记录命令、执行状态、源码 / 夹具 / 媒体哈希和日志路径；逐场景 JSON 记录检查点、请求源文、字幕 / 界面交付及失败的预期 / 实际。报告目录 0700，文件 0600；私有 Replay 的报告同样可能包含敏感对白，不提交、不附发布包。虚拟时间变化不等待现实秒数；构建 / 进程超时由 `--timeout` 控制，回调期限默认 5 秒，媒体夹具允许 30 秒冷启动。

`check` 每个场景默认两遍；`--repeat 1` 可缩短局部调试，`--repeat 2` 用于最终证据。正常基线成功退出 0；新回归失败、超时、隔离阻断、输出缺失或重复结果不一致均退出非零。`known_gap_reproduced` 只有失败步骤与预期 / 实际严格匹配登记证据才成立；崩溃或其它失败不能冒充已知缺口。有缺口时总结果是 `baseline_passed_with_known_gaps`，不是全部产品验收通过。直接运行对应已知缺口的 `replay` 仍退出 1。

## 诊断记录

普通「运行设置 → 诊断与反馈」只保留最近 5 分钟 / 600 条内存元数据，用户导出才落盘，不含截图、台词、服务地址或凭据。优先用它检查权限、窗口、采集、OCR / HTTP 状态和数字错误码。

需要文字链路时，由用户明确启用：

```bash
python3 scripts/translation-trace.py start --seconds 120
python3 scripts/translation-trace.py status
# 复现完成后及时停止
python3 scripts/translation-trace.py stop
```

默认关闭、最长 300 秒 / 1 MiB，文件在 `/tmp/yiya-text-trace-<UID>/events.jsonl`，控制命令会打印确切路径。`start` 清除上一份日志，保留证据时先在私有目录另存。开关动态生效；停止、过期、达到上限或更换会话后，旧回调不继续写入。命令不会启动应用或请求翻译。

新 schema 2 每行含 `event_id`、时间戳、session、cycle、运行代次、输入类型与 epoch；采集成功后附 `frame_id` / `frame_index`。窗口截图的设备 frame index 为 0，用 frame ID 区分；采集卡额外有设备序号。逻辑 `request_id` 关联缓存到最终交付，独立 `http_task_id` 区分长短批次的实际网络任务。旧 schema 无这些新字段时分析器仍支持基本统计。

| 事件 | 判断的问题 |
| --- | --- |
| `cycle_begin` / `capture` | 有调度但没有帧，还是已经拿到可处理图像 |
| `task` | OCR 已调度、开始或完成；`skip: task_busy` 表示上周期尚未完成，没有取得新帧 |
| `ocr: vision_raw` / `vision_raw_crop` | 应用 Vision 适配器输出、源文本去重之前的观察；已经过适配器长度 / 框大小门，不能当作全部 Vision 候选。crop 坐标仍属于局部图 |
| `pass1_filtered` / `merged` / `modal_scoped` | 源观察去重、精读合并或模态范围是否改变了文字 |
| `inline_grouped` / `inline_stable` | 分组问题还是跨帧确认问题 |
| `mode` / `stable` / `skip` | 模式切换、等待、相同已译、节流、空结果或输入过期的具体原因 |
| `dialogue` / `cache` | 提取对白、完整身份原文、版本以及缓存是否复用 |
| `request_submit` / `http_complete` / `request_complete` | 真正提交、HTTP / 网络数字状态、解码成功或失败 |
| `caption_apply/drop` / `inline_apply/drop` | 是否交付、为什么丢弃；apply 不证明面板实际可见 |

不要打印完整请求、认证头、服务地址、缓存键、提示词或 NSError 描述。trace 对 HTTP 错误只记录状态和数字码，不记响应正文。文字日志不保存画面；旧 `FUYI_DIAG` 会保存最新帧，仅在用户明确授权画面诊断时使用，不能默认启用。完整开关和既有边界见 [文字诊断说明](docs/translation-text-trace.md)。

本轮源码的诊断扩充没有自动进入已安装应用。现场取新日志前需按 README 构建 / 安装，再核对运行二进制 UUID；版本号和 build 相同也不能替代二进制核对。

## Replay 夹具

测试专用驱动 `tests/ReplayTests.m` 调用生产 `timerFired:`。输入图像、Vision 观察和 HTTP 会话可替换；其后的后处理、字段分组、稳定、身份、缓存、请求构造、解码、主队列代次判断及交付都由生产代码执行。它不创建 NSApplication、真实窗口或硬件会话，不加载用户设置 / Key / 数据库。未 mock 的网络会由 `FYTestIsolation` 阻断。

AppKit 终点替换成参数记录器，因此 Replay 验证字幕 / 面板接收到的内容；实际排版和 UI 行为用既有布局 / AppKit 套件及手动验收。`restart` 调用真实 stop，再恢复生产启动用的运行与稳定状态，跳过权限 / UI 启动；`connect` / `disconnect` 使用测试采集卡会话和真实帧槽，不模拟驱动、设备占用或系统授权。

```json
{
  "schema_version": 1,
  "name": "最小对白",
  "mode": "dialogue",
  "source": "window",
  "responses": [{"source": "明日は図書館に行きます。", "translation": "明天去图书馆。"}],
  "steps": [
    {"at_ms": 0, "action": "frame", "text": "明日は図書館に行きます。", "expect": {"requests": 0}},
    {"at_ms": 500, "action": "frame", "text": "明日は図書館に行きます。", "expect": {"requests": 1, "captions": ["明天去图书馆。"], "in_flight": false}}
  ]
}
```

顶层 `stable` 默认 true，`auto_fit` / `auto_mode` 默认 false；默认固定路线以单独测试对白 / 界面，`auto_mode:true` 才走生产自动模式判定。`language` 为 `ja` / `en`，`scope` 为左上原点的归一化区域。帧 `blocks` 使用 `text` 与 `[x,y,w,h]`，原点左下；只有 `text` 时使用字幕位置合成框。所有夹具必须有明确产品断言，草稿不能执行为通过。

帧也可用 `image:"assets/frame.png"`，或 `video:"assets/input.mp4", video_ms:500`。路径相对夹具；不同时提供文字 / blocks 时调用真实 Vision、区域及模态处理。合成 PNG / MP4 已附带，用 `vision-image.json` / `vision-video.json` 验证。媒体哈希写入报告；跨 macOS / Vision 版本不承诺逐字与坐标完全相同，需复核预期，不能据此放宽真实产品要求。`tests/GenerateReplayMedia.m` 可重建这些合成资源，无网络、无截图、无设备。

| 动作或响应字段 | 用途 |
| --- | --- |
| `frame` | 新图像 / 新采集卡 frame；可加 `capture_failed:true` 或数字 `ocr_error` |
| `tick` | 保持输入再调 timer；采集卡没有新帧时应跳过 |
| `advance` | 推进虚拟时间并释放到期响应；时间单调且小于 300 秒 |
| `release` + `request` | 按零起始 HTTP 提交索引释放 `hold:true` 的响应，控制乱序 |
| `window` / `mode` | 改显示窗口 ID / 固定模式，检查旧结果丢弃 |
| `restart` / `disconnect` / `connect` | 改运行代次 / 输入会话并验证迟到响应 |
| `cache_probe` | 清帧级去重门，再走原缓存路径；不是模拟真实用户动作 |
| `translate` | 直接调用生产请求入口，用于补充并发交付测试 |
| response `translation` / `status` / `raw_body` / `error_code` | 合成成功译文、HTTP 错误、解码错误、网络超时 |
| response `release_at_ms` / `hold` | 到指定虚拟时间返回，或保持等待手动 release；省略则当前时间返回 |

`expect` 可断言 `requests`、`sources`、`captions`、`inline`、`errors`、`in_flight`、`pending`、`cancel_calls`、`ocr_calls`、`mode`、`drops`、`events` 等，也可用 `has_reason` / `caption_contains`。responses 按实际提交顺序对应；额外请求、未使用的 mock 或结束仍有待处理任务均失败。不要把生产算法或正确结果复制进 mock；mock 只描述服务边界。

导入日志生成 `draft:true`：保留所选阶段的相对帧时间；需选择模式、输入源，填写服务 mock 和用户预期断言后删除 draft。`modal_scoped` 已是后处理结果，不能恢复前面丢掉的观察；精读可能产生同 cycle 多条 `vision_raw`，需人工辨别。截断日志不能作为完整场景导入。既有 `InlineOCRFrameReplayTests` 仍用于资料页专项历史回放，不作为通用 Replay。

## 当前覆盖与产品缺口

| 场景 | 自动断言 |
| --- | --- |
| 静止与重复 | 两次确认后一次请求 / 字幕，后续静止帧仍 OCR 且不重复翻译 |
| OCR 抖动 | 一两帧近似错字不替换；恢复原文打断候选；省略号变体保留身份 |
| 快切现状 | 忙时没有新 OCR / 请求，空闲后处理 C；明确不能保证 A 返回时画面仍是 A |
| 乱序 | 重启后 C 先返回、A / B 后返回，只有 C 展示；同代次长短批次逆序完成后仍正确归位 |
| A→B→A | 三次真实出现建立不同身份并提交三次；连续身份的 cache probe 复用成功译文 |
| 翻译失败 | 超时、429、无效 JSON 释放 inFlight；节流内不重试，到期后恢复并缓存成功结果 |
| 输入中断 | 截图失败保留上一条、恢复后处理新对白；采集卡断开作废旧 epoch，重连后的新帧恢复 |
| 窗口 / 模式过期 | 迟到结果有丢弃原因且不更新旧字幕 |
| 界面 | 字段确认、缓存复用及长短批次乱序映射；真实布局由既有模块与 UI 套件验证 |

`known-gaps/english-period.json` 以“应提交英文对白”为断言，当前实际提交 0 次；trace 显示原始 OCR 存在而 extracted 为空，根因证据是 `shouldIgnoreInlineText` 的“含点且无日文字符”分支。本次保留失败证据，不修该产品 Bug。

`known-gaps/latest-frame-while-busy.json` 以“画面已到 C 后不能应用 A”为断言，当前会应用 A。`inFlight` 阻止 B / C 被采集；日志中 `task_busy` 和 OCR 次数给出证据。是否解耦采集 / 翻译、取消旧请求及如何管理并发，应在后续独立修复中落实。现有代次保护不能证明此更强要求已满足。

## 标准 Bug 修复协议

1. **复现**：记录触发条件、实际 / 预期、应用二进制 UUID、输入源和发生时间。先看已有日志、测试和最小 Replay；尽量减少再次开游戏。新增最小失败夹具，不把历史测试的通过记录当成本轮复现。
2. **定位**：按同一 session / cycle / frame / request / HTTP task 追踪输入、raw OCR、后处理、稳定、缓存、响应和展示；区分没采集、没识别、被过滤、等待、缓存、请求失败和结果被丢弃。
3. **验证根因**：证明故障首次出现在哪个边界，给出原始观察与失败断言。证据不足时写“尚未确认”，补诊断或下一次最短采样；禁止按症状直接猜改代码。
4. **最小修复**：局部修正并保持已有产品合同；有必要的设计选择先列待确认项。回归必须覆盖同一生产逻辑，不能靠删除测试或接受错误输出获得通过。
5. **自动验证**：新增夹具修复前失败 / 修复后通过；运行相关模块和 `debug.py check`。OCR / 布局改动追加相应专项，UI 改动在明确的桌面测试时段运行 AppKit 套件。记录命令、退出码、源码哈希及报告；源码变化后先前报告不代表最终代码。
6. **报告**：根因及证据；文件与关键逻辑；新增 / 修改回归；实际执行及结果；已知缺口、未验证范围与风险；是否需要手动验收及具体最短步骤。使用“该场景自动验证通过”，不无证据宣称彻底修复。

## 相关检查与常见排查

```bash
bash scripts/run-module-tests.sh
bash scripts/run-translation-trace-tests.sh
bash scripts/run-diagnostics-tests.sh
bash scripts/run-dialogue-grammar-tests.sh
# 先准备完整验收，UI 只编译；不占桌面、不等于 UI 通过
python3 scripts/run-acceptance.py
# 已安排桌面测试时段后，执行相关真实 AppKit 测试
FY_TEST_ALLOW_UI=1 scripts/run-learning-app-tests.sh InlineTranslationPipelineTests
# 全套 UI / 剪贴板验收，仅在安排好的时段运行
python3 scripts/run-acceptance.py --ui
```

所有产物与日志保留在忽略的 `.build/` 或测试私有临时目录。全面检查入口已接入 Replay；旧套件和布局断言继续使用，不另建依赖平台。

| 现象 | 先检查 |
| --- | --- |
| 一直没有译文 | 当前构建、权限、显示窗口、capture；采集卡 frame index 是否增长，是否只是 busy 或无新帧 |
| 少半句 | raw → pass1 → merged → modal → extracted；干净源图不能按已有译文过滤原文 |
| 一句重复请求 | logical ID / HTTP task 是否长短批次；cache miss、身份 / 版本、失败重试或 A→B→A 是否属于既定行为 |
| 旧字幕覆盖 | generation / epoch / window / mode 的 drop；同代次 busy 期间画面变化目前是已知缺口 |
| 贴译闪动或错位 | inline_grouped / inline_stable 的块和位置；几何代次、映射与布局；最后核对真实面板 |
| 测试超时 | 看该步骤日志、native failure 与 task 状态；首次 Vision 初始化可用媒体夹具的回调期限，不把超时当通过 |

## 最短手动验收清单

只在自动测试覆盖不到的范围请求用户验收，列出具体画面 / 动作，不让用户重复全套。

- 本轮构建与安装二进制 UUID 一致；启用诊断的运行版确实包含新调用点。同版本真实 Key 只检查是否已配置及文件权限，不输出内容。
- QuickTime / OBS 静止对白停留、A→B→C 快切、A→B→A；核对实际字幕内容、时机和遮挡。快切缺口解决前不能标为通过。
- 采集卡首次相机授权、QuickTime 共用、停止释放、拔插重连；窗口输入屏幕录制权限、关闭 / 重建目标、多屏 / 全屏投影的映射。
- 界面菜单 / 长正文、窗口移动 / 缩放、字体设置、折叠及打开的选择列表；核对实际位置、可见性、原生选择 / 复制与交互身份。
- 按该 Bug 的最短步骤恢复失败，必要时连续运行；30 分钟稳定性、另一台机器、Intel 实机及其它 macOS 单列，不由合成检查推定。

本次建设只更新源码和自动化，没有安装、改变版本、推送或发布；无需为了验证 Replay 启动游戏。后续现场取证仅针对剩余设备 / 体验范围。
