# Debug 基础设施审查与实施计划

审查基线：2026-10-08，唯一维护仓库 `2f5f7ac`，应用版本 0.2.1。此次建设不改变产品行为，不安装或发布应用。

2026-10-08 后续对白延迟修复：对白 timer 改为 0.5 秒，界面保留原配置周期；关闭推理按实际请求模型判断，包含实时模型覆盖。修复前失败与修复后验证见 [对白延迟排查](dialogue-latency.md)。以下数据流表保留原审查基线，已公开的 build 17 尚不包含本轮修复。

## 实际数据流

| 环节 | 当前代码与行为 |
| --- | --- |
| 调度 | `objc/LiveCaptionTranslator.m` 的 `start` 建立 NSTimer，周期为 `max(0.5, intervalSlider)`；`timerFired:` 在主线程复核显示几何，`inFlight` 为真时跳过采集。一个周期覆盖 OCR 和对白翻译返回。 |
| 窗口输入 | `copyFullCapturedImageForWindow:` 使用 `CGWindowListCreateImage(IncludingWindow)` 获取目标窗口自身像素，QuickTime / OBS 是被截图的窗口，不是由应用控制的视频读取服务。没有 ScreenCaptureKit 或单独的“屏幕视频流”模块。 |
| 采集卡 | `FYCaptureCardInput` 使用 AVFoundation 视频输出，独立串行会话队列与帧队列，CoreImage 转像素；只列外接视频设备，不读音频。`FYCaptureCardFrameSlot` 默认最短存帧间隔 0.1 秒，只保留最新帧。timer 仅识别新 frame index；断开、停止、重启增加 session epoch 并清空旧帧。 |
| 几何 | `FYWindowManager` 找显示窗口；`FYGeometryManager` 维护窗口与视频区域映射和代次。QuickTime / OBS 的内容区域定位或用户校准决定采集卡贴译位置。 |
| OCR | 全局工作队列执行 `FYOCRManager` 的 Apple Vision 同步请求，日文 / 英文、fast / accurate 可选；文字最小高度按图像像素换算。支持手动区域裁剪与坐标回映，自动贴合时对符合条件的区域放大精读并合并；模态范围在图像释放前计算。没有图像差分触发门，窗口静止仍按 timer OCR。 |
| 文本与模式 | `sourceTextForItems:blocks:` 对干净源图去重；不能按已有中文缓存删除原文。自动对白 / 界面模式需两次候选确认；对白提取字幕带、过滤按钮和注音，选项走单独贴译。对白稳定通常两帧，高相似真实修正三帧；省略号等无害变体复用身份，恢复原文中断修正候选。 |
| 界面稳定 | 分组、过滤后 `FYInlineOCRFrameStabilizer` 确认字段、文字、位置、换页与漏读。全部有效字段保留，不按全屏块数截断；打开的选择列表 / 阅读卡冻结交互身份。具体合同见 `inline-ocr-stability.md`。 |
| 翻译 | `FYTranslationManager` 构造 OpenAI 兼容 Chat Completions POST，15 秒超时并解码 HTTP / JSON 结果。没有通用自动重试队列；后续 timer 通过节流后重新尝试，失败不缓存。对白节流 4 秒，界面 1.2 秒。实时使用实时模型，界面长短批次可同时请求。 |
| 缓存 | 对白是单项 `FYTranslationCache`，键含运行代次、服务代次、句子身份、版本、原文和提示词。连续同句 / 不完整帧可命中；A→B→A 是新出现，重新请求。界面是按归一化文字与长短类型的多项缓存，最多 4000 项后清空。 |
| 异步与身份 | OCR 和请求回调检查 generation、输入 epoch、显示窗口、模式；贴译还检查几何代次。`FYDeliverTranslationOnMain` 主队列交付前再次检查运行代次。`FYTranslationTaskOwner` 只保存当前 task，替换不取消旧 task；`stop` 取消当前 task。学习协调器用句子 ID / 版本保护当前阅读内容。 |
| 展示 | 对白回到主线程调用 `updateCaptionWindowWithText:status:`，仍经过原有中文净化；界面由 `handleInlineTranslationResult`、`FYInlineLayout` 和面板复用、折叠 / 溢出入口展示。调用 apply 不代表所有面板实际可见。 |
| 学习及外围 | `objc/learning/` 管理 SQLite 历史、收藏、分词、语法与对话；`.inc` 文件组织 AppKit UI，`FYAppUpdater` 负责 Sparkle。Replay 不启动应用生命周期，不读取真实设置、凭据或学习库。 |

## 已有设施

- clang + Foundation / AppKit 原生可执行测试，无 XCTest 工程或第三方测试平台；Python 标准库辅助分发、验收与报告。
- `FYTestIsolation.h/.m` 替换偏好、网络、截图和数据库入口；漏接 mock 的网络会退出 86。`FYTestCaptureCardInput` 使用真实生产单帧槽，不打开硬件。
- `FYRuntimeDiagnostics` 内存保留 5 分钟 / 600 条白名单元数据，用户导出才落盘；`FYTranslationTrace` 默认关闭，显式短时启用才写 OCR 与译文 JSONL，权限 0700 / 0600，最长 300 秒 / 1 MiB。
- `TranslationTracePipelineTests` 已调用真实 timer、缓存、HTTP 解码、字幕交付；但输入、响应和断言写死在测试里。`InlineOCRFrameReplayTests` 是特定资料页日志检查，不是通用 Replay。
- `run-module-tests.sh`、`run-translation-trace-tests.sh`、`run-isolation-tests.sh` 可无窗口运行；`run-checks.sh` 含大量桌面 / 剪贴板测试。`run-acceptance.py` 已有超时、锁、源码哈希、逐步报告与“仅编译不算通过”的约束。

## 风险与验收边界

1. `inFlight` 使长请求期间的新对白没有被 OCR；A 请求返回时画面可能已到 C，但目前无法识别这个变化。本次先建立反映现状的忙时跳帧测试，不暗改调度，也不声称达到“任何快切始终只显示最新画面”。是否采集与翻译解耦、取消旧对白请求，需要独立产品决定。
2. 同代次内允许选项 / 长短批次请求并行，逻辑 request ID 可关联多个 HTTP task；诊断需要独立 HTTP task ID，才能准确区分重复提交与批次并发。
3. 当前 trace 缺少明确的采集完成、原始 OCR 边界及忙时跳过事件；上游丢字可能被误判成 Vision 失败。扩充白名单和调用点，保持开关关闭时不构造文本数组。
4. 调用 show / apply 的无窗口断言验证交付参数和状态，不证明真实遮挡、位置、权限、设备共享、快切体验或长时间运行正确。
5. Vision 的结果随 macOS / Vision 版本变化。OCR 文本回放要求确定性；图片回放执行真实 Vision，应记录系统版本、检查预期子串，不能要求跨系统逐字相同。
6. 用户的日志、录屏和台词只留私有目录；测试仓库仅保存合成内容。没有用户启用诊断就不保存画面或台词，报告不自动复制输入与认证数据。

## 分阶段建设

1. **审查与计划**：保存本审查作为基线，单独提交。
2. **诊断补齐**：沿用现有 JSONL，增加 schema / 事件身份、帧关联、采集与 OCR 异步状态、忙时跳过、原始 OCR、HTTP task 关联，完善隐私和关闭开关测试。不换日志系统。
3. **最高优先级 Replay**：新增测试专用 headless 驱动器，JSON 场景描述 OCR 帧、虚拟时间、延迟 / 指定顺序响应、输入失败与会话切换；真实 timer、后处理、稳定、身份、缓存、请求构造、解码和交付继续由生产代码执行。通过一个默认行为不变的时间方法控制节流。首版支持文字序列和图片帧序列，视频可用系统 AVFoundation 抽帧作为图片输入，不引入 ffmpeg 依赖。
4. **核心回归**：静止、重复、OCR 抖动、快切（现状与限制）、异步乱序、A→B→A、超时 / HTTP / 解码失败及恢复、输入中断；增加界面分组与缓存回放。逐步断言请求 / 展示 / 错误 / 丢弃状态，未满足的更强产品要求明确列出。
5. **统一入口与报告**：少量 `scripts/debug.py` 命令完成 headless 核心检查、单场景回放、日志统计；复用验收 runner 的超时 / 源码哈希与日志输出。生成 JSON 和可读摘要，记录执行范围、失败步骤与预期 / 实际，不调用真实 API。
6. **长期规则**：工作区根 AGENTS 追加要求，维护仓库新增可随克隆生效的 AGENTS，详细 `DEBUG_WORKFLOW.md` 放维护仓库，工作区根文档只跳转。README、已有全面检查与源码导出入口连接新文件。最小步骤分开提交，不自动安装、推送或发布。

## 之后再按真实问题扩展

首版不建立服务端、数据库平台、持续录像或通用 GUI 自动驾驶。先用合成场景证明闭环；后续每个 Bug 增加最小夹具及根因证据。真实日志可转换成 Replay 帧，转换后由维护者补预期断言；日志本身不能自动推导正确产品行为。
