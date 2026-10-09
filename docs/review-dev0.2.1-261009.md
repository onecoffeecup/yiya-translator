# dev0.2.1_261009 审查处理与验证

日期：2026-10-10。审查基线 `1135505`，正式版基线 `0575588`。本轮先读 AGENTS.md、DEBUG_WORKFLOW.md、维护规则与 OCR 稳定合同；使用合成图像、内存服务和隔离设置验证。没有读取真实凭据、学习库或调用真实翻译 API。

## 逐条判断

| 条目 | 判断与本轮结果 | 理由、证据及边界 |
| --- | --- | --- |
| 0-1 平台拆分 | 要改，已完成 | 从 `1135505` 保留 `ipados-poc`；Mac 分支以 `d9b916d` revert iPad 提交，没有改写历史。iPad 内容在专属分支保留，Mac HEAD 不含 ipados 目录、PoC 脚本和 README 章节。 |
| 0-2 分支规则 | 要改，已完成 | 源码 AGENTS.md 与本机工作区规则均加入 Mac/iPadOS/Windows 独立分支、共享内容独立提交的规则。治理提交单列并应用到两个分支。 |
| 1 布局诊断隐私 | 要改，已完成发布路径修复 | 默认实现为 inert stub，`build-app.sh` 显式定义 `FY_ENABLE_LAYOUT_DEBUG=0`；截图编码、控制文件读取、文字/图像保存及覆盖层仅编译进显式启用的开发诊断版本。合法控制文件、`overlay:false` 的合成回归修复前失败，修复后没有新增任何文件。此处证实的是合法控制可触发保存，没有实施跨进程窃取实测。 |
| 2 短批超时过大 | 要改，已完成 | 请求构造新增显式 `longText`，默认和短批固定 15 秒，仅长正文批次 60–90 秒。四、十二、四十项短批回归，及真实 AppDelegate 长短批次请求检查通过。原 `maxTokens > 240` 确会把四项按钮放宽。混合长短批次仍等待双方；短批先渲染作为后续体验改进，未混入本轮。 |
| 3 隐藏预览高频开销 | 要改，已完成调度修复，实机性能待验 | 窗口可见/最小化/Space/occlusion 检查暂停、恢复 timer，迟到预览再次检查可见性。隐藏时 OCR 入口也不缩放或渲染预览。可见采集卡保留 30 Hz；隐藏/仅 OCR 时在像素转换之前限为 10 Hz。生产帧槽 60 Hz 合成输入分别准入 30/10 帧。没有 Apple Silicon/Intel 真实 CPU、耗电或硬件驱动实测；不能把约 250MB/s 的像素量估算当作实测，也不能认定它是玩家卡顿主因。 |
| 4 忙时不处理新画面 | 暂不改，独立排期 | 原 known gap 仍可复现：C 已到来时 A 仍交付。需拆分 OCR 与翻译在途状态，并定义新句确认、请求取消、身份及交付规则。现有防止重启/切窗迟到交付的保护不等于解决同运行快切。没有真实延迟分解数据，暂不能断言其是所有卡顿的“主要”来源。 |
| 5 运行取消服务测试 | 要改，已完成 | 服务测试独立 owner/代次，开始、切窗、切源、框选变化不取消测试；配置变化、重复测试、退出仍取消旧服务任务。运行改变后只更新服务测试结果，不让测试译文覆盖游戏字幕。四类运行变化、两类服务失效/替换回归通过。原审查的顶部卡住结论缺执行证据；本轮新增暂停后切窗的状态断言，复现服务完成但状态未结束，再补上完成/取消时的暂停状态更新。运行中测试不占用运行状态栏。 |
| 6 两处主线程截图 | 暂不改 | 结论成立，权限探测有同步布尔返回、自动映射有几何提交依赖；改异步需要独立验证授权/映射流程。触发频率低，按清单留作后续。 |
| 7a 隐藏旧设置 | 要改，用户已选择移除，已完成 | 移除间隔滑杆、快速 OCR/等待稳定设置及两种旧预设的生产控件、设置读写与运行影响。固定对白 0.5 秒、界面 1.2 秒、准确 OCR，保持原稳定规则。合成旧设置 `interval=4, fastOCR=true, stableText=false` 不改变生产策略。Replay 的稳定门注入仅存在于隔离测试编译。 |
| 7b 同一帧可能识别两次 | 要改，已完成 | 帧槽同一临界区返回图片及其序号；OCR/预览登记实际拷贝的帧号。合成场景在 tick 看到帧 1 后挂起后台取帧，再注入帧 2，检查登记为 2 且下一 tick 不再识别同帧。 |
| 7c busy trace 事件过多 | 暂不改 | 结论成立；目前每次忙碌 tick 的两条事件也是已知缺口的证据。限时、限量仍生效；后续可增加计数聚合，但需同时维护分析器和 Replay 可观察性。 |
| 7d 死代码 | 部分要改、部分不认同 | 删除无调用的 `isDeepSeekRequest`。`FYTranslationTaskOwner.activeTask` 有生产读写和批次任务登记/释放调用，还由多项回归覆盖，不能按“没有调用方”删除。 |
| 7e 无符号减法可能下溢 | 不认同当前 Bug 判断，不改 | `subtitleBandItems:` 保留源对象的子集并排除空文，两处 small-box 判据一致，所以 `bandSmallBoxes <= smallBoxCount`。当前没有能违反这个不变量的生产输入证据。仅看到无符号减法不足以判定存在下溢；未来若改变两处计数合同，再补失败输入。 |
| 7f 主线程 PNG 编码 | 发布路径已随 1 消除；开发路径暂不改 | 默认/发布构建不会编码 PNG。显式开发诊断仍同步编码；以后若改后台需验证 session 撤销、限量和图像生命周期，不在本轮更改证据采样顺序。 |

维护者已确认的“原文右侧覆盖自身原文”和对白固定 0.5 秒保持原合同。

## iPad PoC 判断

本轮仅保留分支并核实源码，五项均暂不实施，作为 `ipados-poc` 下一阶段的任务。该阶段尚未进入设备构建/采集验收，不将未经类型/设备验证的修复混入 Mac 分支。

- 帧时长：认同应改。`1 / targetFPS` 的有理数舍入在范围端点存在风险。应保留所选 frame-rate range 的精确 duration，并选择支持的时间值；直接用 `minFrameDuration` 会选择该范围的最高 fps，不能无条件把“安全 duration”当作“保持 30 fps”。[Apple 的帧时长约束](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration)明确非法支持范围会抛出异常。未复现真实设备崩溃。
- 多任务相机：认同需处理，但“不设置就永远中断”应改为条件结论。先检查 `isMultitaskingCameraAccessSupported`，支持时显式启用；不支持时给出恢复全屏指引，不能无条件设置或保证所有分屏/台前调度硬件均可用。[Apple 的支持条件](https://developer.apple.com/documentation/avfoundation/avcapturesession/ismultitaskingcameraaccesssupported)需按目标设备核对。
- macOS 类型检查：认同检查入口有平台错误。当前 Apple macOS SDK 的 `AVCaptureSessionPresetInputPriority` 明确 `API_UNAVAILABLE(macos)`；完整 Xcode 也不会让 macOS SDK 获得 iOS API。应保留跨平台 primitives 的 host 测试，把 CaptureService 类型检查移到 iPhoneOS/iOS Simulator SDK。原验证文档记录的模块冲突会遮住此错误；本机没有 iPhoneOS SDK，未做成功类型检查。
- 停滞后启动：认同按钮语义需改。现有 guard `session == nil` 会让重复启动只发布状态；当前提示已有“暂停后重新启动”，下阶段可禁用无效启动或提供明确重启操作，并测会话释放和 epoch。
- 720p OCR：认同补充分析。PoC 尚未接 OCR；Mac 准确模式按 48px/图像高度计算 Vision 最小文本高度，720p 时约 0.067。但 Vision 参数不是严格字高硬截断，不能仅据该值断言某设备对白必然无法识别。接入前用合成及授权真实小字图像测试分辨率和识别参数。

## 修改位置与回归

- `objc/FYInlineLayoutDebug.m`、发布/布局测试构建脚本及 `tests/LayoutDebugReleaseTests.m`：默认/发布构建禁用，合成布局检查显式启用。新负向检查纳入模块与统一 Debug。
- `objc/FYTranslationManager.[hm]`、`objc/LiveCaptionTranslator.m`、`tests/TranslationManagerTests.m`：显式请求类别、短批 15 秒及长批 60–90 秒。
- `objc/LiveCaptionTranslator.m`、`objc/FYCaptureCardInput.[hm]`、`tests/TranslationTracePipelineTests.m`：服务 owner/代次、可见性调度、生产帧槽频率、原子取帧身份及旧设置失效。
- `tests/InlineTranslationPipelineTests.m`、`tests/DisplayTargetFollowTests.m`：更新隔离边界到新请求签名及测试专用稳定门；只编译，不将其记录为 UI 执行通过。

## 实际验证与限制

修复前新增最小回归分别失败：合法控制文件可开启截图；四项短批 timeout 超出 15 秒；开始/切窗取消服务测试；隐藏预览仍截图；旧设置使界面间隔为 4000ms。失败记录留在本机 `.build/review-*-before.log`（布局与请求构造失败为命令输出）。没有用独立模拟算法替代生产处理。

| 实际命令 | 结果 |
| --- | --- |
| `bash scripts/run-module-tests.sh` | 退出 0；包括新增发布诊断负向检查，TranslationManager 74 项、任务 ownership 40 项及相关 OCR/几何模块通过。 |
| `bash scripts/run-translation-trace-tests.sh` | 最终退出 0；四类运行变化、服务配置/重复测试、真实长短请求、隐藏/恢复/迟到预览、10/30Hz 生产帧槽及原子帧身份检查通过。 |
| `bash scripts/run-headless-checks.sh` | 最终退出 0；内部实际运行 `python3 scripts/debug.py check`，64 条记录：60 passed，4 known_gap_reproduced（两个缺口各两遍）；`source_unchanged=true`。最新直接命令 `python3 scripts/debug.py check` 同样退出 0，报告 `.build/debug/20261009T181219Z-639368/summary.json`。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 最终退出 0，双架构构建与 dSYM UUID 核对通过。arm64 `EA59FDB2-9C64-34BA-A13C-A46586B3B071`，x86_64 `D84C828C-8666-3F0E-B468-D3408C8412B3`。未安装。 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh InlineTranslationPipelineTests` | 退出 0，COMPILED_ONLY；未执行 UI。 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh DisplayTargetFollowTests` | 退出 0，COMPILED_ONLY；未执行 UI。 |
| `git diff --check` | 退出 0。 |
| `xcrun --sdk iphoneos --show-sdk-path` | 退出 1，iPhoneOS SDK 不存在；developer directory 为 CommandLineTools。未运行 iPad 构建/真机。 |

统一结果为 `baseline_passed_with_known_gaps`。`english-period` 仍预期请求 1、实际 0；`latest-frame-while-busy` 仍预期不交付旧字幕、实际交付测试译文甲。未将它们改成接受错误行为的通过测试。远端 CI 与本机检查单列：已核对 `1135505` 的最新 [Headless regression #37948533571](https://github.com/onecoffeecup/yiya-translator/actions/runs/37948533571)，结果 failure，`ModuleTests` 超过 180 秒，最后完成的子套件为 InlineTextPolicyTests；后续增加阶段标记和超时堆栈采样，在 [08a7889 的运行 #37970164403](https://github.com/onecoffeecup/yiya-translator/actions/runs/37970164403) 确认 InlineFontStabilityTests 在 `NSFont fontWithName:` → `TDownloadableFontManager::Download` → `DownloadFontsForProperties` 等待系统字体下载。“本分支跑过一次通过”不能代表审查 HEAD 通过。

为满足 Mac 分支 CI 验收，本轮还修复了这个实际复现的字体等待问题：`objc/FYLocalFont.h` 共用于主题与贴译，在调用 AppKit 名称匹配前检查 [CoreText 可用字体列表](https://developer.apple.com/documentation/coretext/ctfontmanagercopyavailablepostscriptnames())，缺失字体使用现有系统字体回退，不下载或分发字体。已安装圆体的字体和大小不变。可用名称在当前进程内缓存，运行期间新安装字体需重开应用。新增 `LocalFontTests` 的缺失名称匹配断言先失败、修复后通过；实际主题/贴译选字一致与日文字体链也检查通过。`InlineFontStabilityTests` 保留 17pt 跨帧稳定、折叠恢复、主动改到 21pt 和新场景 19pt 的断言，改为用真实生产布局寻找当前字体的换行边界，避免可选字体缺失时固定几何夹具误报。本机圆体与系统字体两种路径均通过，统一 Debug 和双架构构建在此改动后重跑通过。采样期限仍将真正超时判为失败，未屏蔽测试。

字体定位期间曾有一次采样脚本接入位置错误导致编译失败，后续独立提交修正；没有改写失败历史。远端修复后的 Headless regression 将以实际完成的运行结果另行记录。

本轮源码与本机构建不会自动改变已安装应用，也没有发布新版本/附件。未安排桌面或硬件时段，因此不运行真实截图、摄像头、剪贴板或 UI 测试；Apple Silicon/Intel 的 CPU/耗电、实际多桌面状态和 iPad 真机均未验证。

最短后续手动验收：使用本轮构建，测试服务后立刻开始/切窗，确认服务结果正常且不覆盖游戏字幕；让目标主窗口在显示、最小化、遮挡和其它 Space 之间切换，确认可见时预览恢复、隐藏时不额外截图；分别在 Apple Silicon/Intel 记录相同窗口/采集卡输入下可见及隐藏状态的 CPU/耗电。A→B→C 快切仍是失败目标，不把它列为本轮已修。
