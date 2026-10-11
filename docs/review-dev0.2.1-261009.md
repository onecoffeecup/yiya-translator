# dev0.2.1_261009 审查处理与验证

日期：2026-10-10。审查基线 `1135505`，正式版基线 `0575588`。本轮先读 AGENTS.md、DEBUG_WORKFLOW.md、维护规则与 OCR 稳定合同；使用合成图像、内存服务和隔离设置验证。没有读取真实凭据、学习库或调用真实翻译 API。

## 逐条判断

| 条目 | 判断与本轮结果 | 理由、证据及边界 |
| --- | --- | --- |
| 0-1 平台拆分 | 要改，已完成 | 从 `1135505` 保留并上传 `ipados-poc`（治理提交后为 `2f26a06`）；Mac 分支以 `d9b916d` revert iPad 提交，没有改写历史。iPad 内容在专属分支保留，Mac HEAD 不含 ipados 目录、PoC 脚本和 README 章节。 |
| 0-2 分支规则 | 要改，已完成 | 源码 AGENTS.md 与本机工作区规则均加入 Mac/iPadOS/Windows 独立分支、共享内容独立提交的规则。治理提交单列并应用到两个分支。 |
| 1 布局诊断隐私 | 要改，已完成发布路径修复 | 默认实现为 inert stub，`build-app.sh` 显式定义 `FY_ENABLE_LAYOUT_DEBUG=0`；截图编码、控制文件读取、文字/图像保存及覆盖层仅编译进显式启用的开发诊断版本。合法控制文件、`overlay:false` 的合成回归修复前失败，修复后没有新增任何文件。此处证实的是合法控制可触发保存，没有实施跨进程窃取实测。 |
| 2 短批超时过大 | 要改，已完成 | 请求构造新增显式 `longText`，默认和短批固定 15 秒，仅长正文批次 60–90 秒。四、十二、四十项短批回归，及真实 AppDelegate 长短批次请求检查通过。原 `maxTokens > 240` 确会把四项按钮放宽。混合长短批次仍等待双方；短批先渲染作为后续体验改进，未混入本轮。 |
| 3 隐藏预览高频开销 | 要改，已完成调度修复，实机性能待验 | 窗口可见/最小化/Space/occlusion 检查暂停、恢复 timer，迟到预览再次检查可见性。隐藏时 OCR 入口也不缩放或渲染预览。可见采集卡保留 30 Hz；隐藏/仅 OCR 时在像素转换之前限为 10 Hz。生产帧槽 60 Hz 合成输入分别准入 30/10 帧。没有 Apple Silicon/Intel 真实 CPU、耗电或硬件驱动实测；不能把约 250MB/s 的像素量估算当作实测，也不能认定它是玩家卡顿主因。 |
| 4 忙时不处理新画面 | 要改，追加完成实时链路修复 | 先复现原 known gap，再拆分实时采集/OCR 与网络状态；确认新内容后取消旧请求，旧成功、错误、缓存写入及排队显示均受内容代次检查。相同在途内容继续 OCR 且不重复请求；保留稳定规则、真实再现身份与 UI 最新确认坐标。窗口/采集卡/换页/回到原句回归通过。真实游戏延迟幅度、服务耗时与设备体验未测；单次“翻译当前界面”仍按快照完成。 |
| 5 运行取消服务测试 | 要改，已完成 | 服务测试独立 owner/代次，开始、切窗、切源、框选变化不取消测试；配置变化、重复测试、退出仍取消旧服务任务。运行改变后只更新服务测试结果，不让测试译文覆盖游戏字幕。四类运行变化、两类服务失效/替换回归通过。原审查的顶部卡住结论缺执行证据；本轮新增暂停后切窗的状态断言，复现服务完成但状态未结束，再补上完成/取消时的暂停状态更新。运行中测试不占用运行状态栏。 |
| 6 两处主线程截图 | 暂不改 | 结论成立，权限探测有同步布尔返回、自动映射有几何提交依赖；改异步需要独立验证授权/映射流程。触发频率低，按清单留作后续。 |
| 7a 隐藏旧设置 | 要改，用户已选择移除，已完成 | 移除间隔滑杆、快速 OCR/等待稳定设置及两种旧预设的生产控件、设置读写与运行影响。固定对白 0.5 秒、界面 1.2 秒、准确 OCR，保持原稳定规则。合成旧设置 `interval=4, fastOCR=true, stableText=false` 不改变生产策略。Replay 的稳定门注入仅存在于隔离测试编译。 |
| 7b 同一帧可能识别两次 | 要改，已完成 | 帧槽同一临界区返回图片及其序号；OCR/预览登记实际拷贝的帧号。合成场景在 tick 看到帧 1 后挂起后台取帧，再注入帧 2，检查登记为 2 且下一 tick 不再识别同帧。 |
| 7c busy trace 事件过多 | 暂不改 | 结论成立；限时、限量仍生效。追加修复后实时网络等待不再触发 busy skip，采集/OCR 真正忙碌时仍保留两条事件；后续可增加计数聚合，但需同时维护分析器和 Replay 可观察性。 |
| 7d 死代码 | 部分要改、部分不认同 | 删除无调用的 `isDeepSeekRequest`。`FYTranslationTaskOwner.activeTask` 有生产读写和批次任务登记/释放调用，还由多项回归覆盖，不能按“没有调用方”删除。 |
| 7e 无符号减法可能下溢 | 不认同当前 Bug 判断，不改 | `subtitleBandItems:` 保留源对象的子集并排除空文，两处 small-box 判据一致，所以 `bandSmallBoxes <= smallBoxCount`。当前没有能违反这个不变量的生产输入证据。仅看到无符号减法不足以判定存在下溢；未来若改变两处计数合同，再补失败输入。 |
| 7f 主线程 PNG 编码 | 发布路径已随 1 消除；开发路径暂不改 | 默认/发布构建不会编码 PNG。显式开发诊断仍同步编码；以后若改后台需验证 session 撤销、限量和图像生命周期，不在本轮更改证据采样顺序。 |

维护者已确认的“原文右侧覆盖自身原文”和对白固定 0.5 秒保持原合同。审查行号以 `1135505` 为准；当前修复后的行号已变化，不能直接用旧行号定位新 HEAD。

## 修复顺序

最初按 0 → 1 → 2 → 5 → 3 执行：服务测试取消边界较局部；预览仍需 Apple Silicon/Intel 性能验收。7a 按用户选择移除，7b 与预览/OCR 链路一并修复。用户指出实时延迟还未解决后，把 4 提到本轮，追加完成生产链路与回归；最初独立排期是实施优先级选择，不能算作处理了该问题。6、7c、开发诊断 PNG 优化与 iPad 五项留在后续阶段。Mac 字体下载等待在 CI 实际复现，已单独修复并验收。

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

## 前轮实际验证与限制（追加修复之前）

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

字体定位期间曾有一次采样脚本接入位置错误导致编译失败，后续独立提交修正；没有改写失败历史。修复源码 `1c4adb2` 的远端 [Headless regression #37971887839](https://github.com/onecoffeecup/yiya-translator/actions/runs/37971887839) 已完成，结论 success。下载的证据 `.build/review-ci-font-pass/20261009T181442Z-5275eb/summary.json` 为 60 passed / 4 known_gap_reproduced，`source_unchanged=true`；ModuleTests 中 LocalFontTests 与 InlineFontStabilityTests 均 0 failures，后者在系统字体下选择 132/140px 几何间隔。此成功仍不表示两个产品缺口已经修复。

本轮源码与本机构建不会自动改变已安装应用，也没有发布新版本/附件。未安排桌面或硬件时段，因此不运行真实截图、摄像头、剪贴板或 UI 测试；Apple Silicon/Intel 的 CPU/耗电、实际多桌面状态和 iPad 真机均未验证。

最短后续手动验收：使用本轮构建，测试服务后立刻开始/切窗，确认服务结果正常且不覆盖游戏字幕；让目标主窗口在显示、最小化、遮挡和其它 Space 之间切换，确认可见时预览恢复、隐藏时不额外截图；分别在 Apple Silicon/Intel 记录相同窗口/采集卡输入下可见及隐藏状态的 CPU/耗电。实时 A→B→C 快切在合成链路已通过，真实游戏仍需核对新画面识别不中断、迟到 A/B 不回填；再检查 A→B→A 再现身份、错读恢复及界面换页/位置移动。

## 2026-10-10 追加：实时识别与网络等待分离

15 秒为普通/短批请求失败上限，返回即可处理，不是固定等待 15 秒；此数值沿用既有通用容错，没有真实服务耗时测量支持另设数字。降低超时只会更早失败，不能使服务更快。已修复的确定根因是 `inFlight` 原来同时覆盖采集、OCR 与 HTTP：慢回复阻止后续 OCR，旧画面回复仍能交付。

`LiveCaptionTranslator.m` 实时 OCR 结束即释放其忙碌状态；网络单独记录内容代次、操作数与确认坐标。新内容经原稳定门确认后取消旧任务；传输入口防止旧结果写缓存，字幕和排队面板防止迟到交付，旧回包不释放新 OCR 状态。相同在途内容持续识别但不重复请求；UI 位置变化沿用请求并使用最新确认位置。A→在途 B→A 经原身份规则建立真实再现，取消记录不再施加 4 秒节流。服务测试独立隔离；显式“翻译当前界面”单次快照保持原完成流程。

新增检查使用原 AppDelegate、实际生产帧槽、Mock HTTP 与 Replay，仅替换输入和最终视图调用。修复前 `bash scripts/run-translation-trace-tests.sh` 退出 2（网络占有 OCR busy）；原 known-gap Replay 退出 1（C 到来后 A 仍展示，报告 `.build/debug/20261010T003402Z-2b47b1`）。补测 UI 请求的坐标归属先退出 2，再修复绑定，避免旧请求借用新未完成 OCR 的几何代次。`cancelled-dialogue-recurrence.json` 修复前退出 1（预期第三次请求，实际两次；`.build/debug/20261010T005043Z-95b6e0`），局部修复后两遍通过（`.build/debug/20261010T005111Z-374af1`）。

原 `latest-frame-while-busy` 失败目标已升级为普通 `latest-frame-while-translating`，保留 C 确认后不得交付 A 并加强重复帧、取消、迟到成功/错误断言；另新增采集卡、UI 换页、取消后真实再现回归。`fast-switch-busy` 保留稳定门并检查单帧错读不取消、恢复帧打断候选。Replay 等待条件只等待实际 OCR，不再因已有挂起 HTTP 而跳过新识别完成。

| 实际命令 | 追加修复最终结果 |
| --- | --- |
| `python3 scripts/debug.py replay tests/fixtures/replay/cancelled-dialogue-recurrence.json --repeat 2` | 退出 0，两遍通过。 |
| `bash scripts/run-translation-trace-tests.sh` | 坐标保护修复后单独退出 0；最终源码又由统一 Debug 执行通过。 |
| `python3 scripts/debug.py check` | 退出 0；`.build/debug/20261010T005145Z-e2b48b/summary.json`，68 passed / 2 known_gap_reproduced，`source_unchanged=true`。模块、Trace、Replay 均通过；两条已知失败仅为英文句点的两遍复现。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 退出 0；dSYM UUID 核对通过，arm64 `6F3A6619-3486-3F2E-BB54-26CE02D81A68`，x86_64 `5CA60685-0552-3672-971D-4CC4BFCDD6AA`。未安装。 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh InlineTranslationPipelineTests` | 退出 0，仅编译。 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh DisplayTargetFollowTests` | 退出 0，仅编译。 |

远端 CI 在提交后另行核对，结果与链接在任务交付中报告；前文字体 CI 是历史证据，不能代表本次源码。没有请求真实 API、运行真实游戏/设备/UI 或测量玩家延迟，不能承诺固定几秒出译文；没有安装应用或发布附件。最短验收仍为前段列出的快切、恢复和界面换页场景。

## 2026-10-10 追加：英文句点误删

触发：英文对白或界面文字包含句点，例如合成原文 `Welcome to the test garden.`。实际 OCR 保留文字，但 `shouldIgnoreInlineText` 的“含点且无日文字符”提前返回删除整行，稳定后请求仍为 0；期望一次请求并显示译文。修复前重跑旧目标退出 1（预期 1、实际 0，`.build/debug/20261010T021942Z-c54e7d`），新增生产过滤检查退出 2（`.build/english-punctuation-filter-before.log`）。

局部修复移除上述提前删除，保留原来的逐字符纯标点/符号/空白判断；英文句号和省略号可以与实际文字共存，日文 `え……` 等仍保留。短碎片、按钮与其它已有过滤规则未改。没有增加句长阈值、字词白名单或另一套模拟算法。修改位于 `objc/LiveCaptionTranslator.m`；两条过滤路线和三种框宽的英文/日文/纯标点检查加入 `TranslationTracePipelineTests.m`。

原 `known-gaps/english-period.json` 升级为普通 `english-period.json`，保留原一请求目标并增加源文、字幕及重复帧去重；新增 `english-inline-period.json`，验证英文界面句点经真实分组、确认、批次请求与交付，旁边纯 `......` 块不进入请求。两个原登记缺口现均作为普通回归通过；历史失败记录仍保留，不能由此推断全部真实设备体验已验收。

| 实际命令 | 本次结果 |
| --- | --- |
| `python3 scripts/debug.py replay tests/fixtures/replay/english-period.json --repeat 2` | 退出 0，两遍通过；`.build/debug/20261010T022258Z-5d0f69`。 |
| `python3 scripts/debug.py replay tests/fixtures/replay/english-inline-period.json --repeat 2` | 退出 0，两遍通过；`.build/debug/20261010T022337Z-8b48db`。 |
| `bash scripts/run-translation-trace-tests.sh` | 新检查修复前退出 2；修复后退出 0，原有实时/预览/请求隔离回归同时通过。 |
| `python3 scripts/debug.py check` | 在本次索引快照执行，退出 0，72 passed / 0 known gaps，`source_unchanged=true`；模块、离线采集卡、布局、Trace、Replay 均通过。报告 `.build/english-punctuation-snapshot/.build/debug/20261010T022623Z-24a102/summary.json`。其 261 项源码/夹具/媒体哈希逐项与提交索引一致。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 退出 0；dSYM UUID 核对通过：arm64 `104396BF-649B-3287-B423-C173B4636F50`，x86_64 `432250A3-9843-33CA-96F7-46CFEC78BC4E`。未安装。 |
| `git diff --check` | 退出 0。 |

并行的其它 OCR 工作先后新增 `tests/OCRStrategyBenchmark.m` 与 `scripts/run-ocr-strategy-benchmark.py`，源码目录的前两次统一检查因此按源不变规则中止，退出 1，结果 `incomplete`（`.build/debug/20261010T022424Z-58fc7f`、`20261010T022530Z-af4df6`），不算通过。保留这些工作文件，使用 `git checkout-index --all --prefix=.build/english-punctuation-snapshot/` 导出只含本次待提交修改的索引快照后，完整检查通过；基准文件未混入本次提交。

远端 CI 在提交后单列核对，并在交付中提供结果链接。本次没有安装、重启应用、调用真实服务或运行真实游戏/UI/设备。最短后续验收：用本次构建选英文，对含句号或省略号的完整对白核对译文；同时确认纯省略号不产生翻译请求、日文 `え……` 不漏句，再检查界面含句号文字的贴译。现场验收与自动回归分别记录。

## 2026-10-10：N1–N4 Nit 复核

2026-10-11 后续补充：另一处字幕停滞由首遍稳定、二次精读交替识别引起，发生在请求前，需独立于 N1 修复。已补逐块结果选择、精读稳定恢复与上下文隔离，35 帧历史双遍观察回放两遍通过；完整核心检查本轮退出 0（普通 Replay 66 passed、N2 2 known_gap_reproduced），双架构构建通过，未安装/发布。该新结果不改写下文上一轮的失败记录，详情见 [精读结果选择与验证](ocr-refinement-stability.md)。

本次范围为 Mac 的请求取消时机、隐藏精读设置及重复忙碌赋值。工作区中同时有其它外观、几何和 OCR 基准修改，全部保留；最终验证使用固定提交 `21de5646252fc6189ce6546660f68ae1b40ca1fd` 加本次五个文件的补丁，位于 `.build/nit-review-scoped-pwuju7yq/`。没有把整个工作区标为已验证。精确补丁和散列见该目录的 `nit.patch`、`nit-snapshot.json`、`verification.json`；末次核对确认本次代码和测试适配仍在工作区，额外并行修改未覆盖它们。

- **N1 属实，已局部修正。** A 已显示、B 在途，单帧再次读到 A 时，原 `timerFired:` 的已显示文本分支在稳定门之前调用 `invalidateContentTranslation`。新增 [pending-dialogue-single-frame-recurrence.json](../tests/fixtures/replay/pending-dialogue-single-frame-recurrence.json) 修复前第 4 步取消次数预期 0、实际 1（`.build/debug/20261010T145906Z-8823ed`）。修复仅将 `sameTextAsRendered` 置为 NO，经过原稳定门后由 `beginContentTranslation` 取消 B。新用例开启稳定门，检查单帧 A 保留 B、恢复 B 复用请求并打断候选、连续两帧 A 确认新身份、随后 B 不受已取消尝试的节流影响，以及迟到 B 不覆盖字幕。新用例与原 `cancelled-dialogue-recurrence` 均两遍通过；原用例继续覆盖关闭稳定门的隔离边界。
- **N2 当时没有直接覆盖，该轮补了已知失败。** 既有界面用例覆盖整页切换、长短批次乱序及几何复用，没有覆盖未变长正文旁的小块变化。原 `known-gaps/inline-long-batch-unrelated-change.json` 保持长正文 HTTP 在途，只改变独立时钟块；前两帧没有取消，第三帧确认后长批次被取消并重发，请求总数由 2 增至 4。第 4 步仍要求取消次数 0，实际 1，修复前报告 `.build/debug/20261010T145934Z-fb44fe`，该轮末次 Replay 两遍均为 `known_gap_reproduced`。当时未改调度，不能把该轮失败写成修复通过。2026-10-11 后续已局部修正并转为 [普通回归](../tests/fixtures/replay/inline-long-batch-unrelated-change.json)，见下方追加记录；历史失败证据保留。
- **N3 已固定开启。** 删除 `recognitionCard` 对旧复选框的创建、`saveSettings:` 的 `autoFitRegion` 写入和 `loadSettings` 的读取。生产 `autoFit = YES`，保留原精读面积判断。旧控制属性与读取只在 `FY_TEST_ISOLATED_CREDENTIAL_STORE` 内供测试隔离下游边界；目标跟随测试自行创建合成开关。正式二进制核对未包含旧属性名、偏好键和控件标题。
- **N4 已删除 9 处重复赋值。** 仅清理实时 OCR 主回调统一释放之后的 `self.inFlight = NO`。采集失败、同代次过期 OCR 和手动识别的必要释放保留；相关迟到 OCR/重启所有权回归通过。

以下命令在固定提交补丁快照执行：

| 实际命令 | 本次结果 |
| --- | --- |
| `python3 scripts/debug.py check --replay-only --timeout 300` | 退出 0，64 passed / 2 known_gap_reproduced，`source_unchanged=true`；仅 Replay 基线通过。报告 `.build/nit-review-scoped-pwuju7yq/.build/debug/20261010T151903Z-0527d1/summary.json`。包括新/旧 N1、界面及采集卡在途、真实合成图片/视频 Vision 场景各两遍。 |
| `bash scripts/run-module-tests.sh` | 退出 0；几何、OCR 后处理/配置、字段稳定、字体、翻译与任务取消模块通过。 |
| `bash scripts/run-translation-trace-tests.sh` | 退出 0；生产翻译链路、四种迟到 OCR 重启组合、在途界面几何复用、独立预览和凭据排除通过。 |
| `python3 scripts/layout-debug.py check` | 退出 0，132,686 断言通过；`.build/nit-review-scoped-pwuju7yq/.build/layout-debug/run-ddd86b07/summary.json`。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 退出 0，二进制与 dSYM UUID 一致：arm64 `D51A49DD-83B9-31A7-AE12-ADCD651E289E`，x86_64 `1D401062-086C-3476-9705-5683D1F85D2A`。 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh DisplayTargetFollowTests` | 退出 0，`COMPILED_ONLY`，不算 UI 执行通过。 |
| `python3 scripts/debug.py check` | **未通过**；固定快照的离线检查并行用例超过默认 180 秒，报告 `20261010T150558Z-ac30cf`。 |
| `python3 scripts/debug.py check --timeout 300` | **未通过**；离线检查的并行子命令仍在内部 120 秒期限超时，报告 `20261010T150946Z-7e53d4`。 |
| `FY_CAPTURE_CARD_BUNDLE_ID=com.nanami.yiya.nit-review-ocr-check python3 scripts/debug.py check --timeout 300` | **未通过**；Fast 用例的 `open -W` 报 `initial call to kevent() failed: No such process`，并行用例仍超时，报告 `20261010T151429Z-abcdd3`。所有报告在固定快照的 `.build/debug/` 下。 |
| `git diff --check` | 工作区退出 0。 |

整套核心检查失败停在 `CaptureCardOfflineTests`，不能由模块、Replay 或构建通过替代。对前一次超时的合成 OCR 进程采样，调用栈停在 Apple Vision/TextRecognition 的信号量等待，证据 `.build/nit-review-scoped-pwuju7yq/.build/offline-probe-sample.txt`；尚未证明完整根因。失败后仅终止本次遗留的合成 OCR 进程，没有关闭玩家应用或修改系统配置。

另外保留两次准备失败：原工作区检查因并行源码变化中止为 `incomplete`（`.build/debug/20261010T150201Z-430c48`）；初次从活动文件复制的快照混入了未配套的界面代码，缺少 `FYAppearanceUI.inc` 及相关类型，编译/离线检查失败（`.build/nit-review-snapshot-oqqce610/.build/debug/20261010T150329Z-68c2f4`）。最终改为从固定提交逐项应用本次补丁；这些失败没有算作通过。

本轮未安装、重启正式应用、推送或发布；真实 API、设备和桌面体验未执行。最短后续验收：使用本次构建，让 A 显示后保持 B 翻译在途，短暂单帧返回 A 再恢复 B，核对没有重发 B；再连续两帧返回 A，核对确认后才切换并取消旧 B。N2 仍需在有长正文和分钟变化小块的真实页面核实实际等待影响。

## 2026-10-11：N2 无关短字段变化保留在途长正文

触发条件为实时界面长正文 HTTP 仍在等待，旁边独立时钟的小改动通过原三帧稳定门。重新执行原失败夹具 `python3 scripts/debug.py replay tests/fixtures/replay/known-gaps/inline-long-batch-unrelated-change.json --repeat 1 --timeout 300`，退出 1，第 4 步取消次数仍为预期 0、实际 1；报告 `.build/debug/20261011T051317Z-700345/summary.json`。根因是整页文本/逐项键序列失配后调用 `beginContentTranslation`，由 `invalidateContentTranslation` 取消所有实时任务，未区分仍未改变的长批。

局部修正在 `LiveCaptionTranslator.m` 的 `beginInlineContentTranslation:items:trace:`、`translateInlineLongItems:...` 与 `FYTranslationTaskOwner cancelTasksExceptTask:`。实时界面的全部长正文键及重复次数不变时，保持原长 HTTP 任务和传输内容修订，更换界面计划序号，只取消过期短批。新计划复用同一长批结果，按源键及出现次数写入当前输出位置；旧短回复不得写缓存或交付。长正文增删/改字/类别变化、停止、重启、切窗/源/模式或服务变化仍走原作废边界。失败不缓存、可重试，长短全部完成后仍一次性交付，不改变混合对白/选项和单次手动快照。

原 N2 夹具已转为普通 `inline-long-batch-unrelated-change.json`，原取消断言保留，并追加连续两次时钟变化、原长批仅一次请求、长批先返回等待最新短批及最终当前内容交付。另新增 5 条普通 Replay，覆盖长批失败重试、真正正文变化/过期短成功及长错误、前置短字段移除后的索引变化、不同位置同文长字段的独立结果槽、停止重启。`TranslationManagerTests` 补齐保留/替换任务及迟到旧完成不释放新 owner 的检查。本轮复核抓到初版键映射把重复源的第二结果写成第一结果；保留 `duplicate-before.json` 的失败，再按出现次数匹配后通过，未放宽产品断言。

工作区还有其它聊天的姓名牌改动，验证使用 `.build/inline-batch-retention-20261011/snapshot/` 的固定完整源码快照，包含原有修改和本轮补丁；本轮没有修改姓名牌算法。最终检查及正式构建使用同一快照，末次核对全部 298 个源码/脚本/夹具/规则/媒体散列与现役工作区一致。资料包为既有公开 reference.sqlite，仅补入测试快照，未读取玩家学习库或 Key。

| 实际命令 / 检查 | 结果 |
| --- | --- |
| `FY_CAPTURE_CARD_BUNDLE_ID=com.nanami.yiya.n2-retention-20261011-ocr python3 scripts/debug.py check --timeout 300` | 退出 0，99 条记录全部 passed；11 项核心套件、Replay 构建/失败报告检查及 43 场景各两遍（86 条）通过，0 项登记缺口，source_unchanged=true。报告 `snapshot/.build/debug/20261011T052646Z-0f0435/summary.json`。 |
| `bash scripts/run-module-tests.sh` | 退出 0；请求 owner 新回归包含在 TranslationManagerTests 的 74 条断言中；日志 `module-tests-final.log`。 |
| `bash scripts/run-translation-trace-tests.sh` | 退出 0；在途对白、UI 最新几何、重启 OCR 所有权、独立服务测试和凭据排除均通过；日志 `translation-trace-final.log`。 |
| 六个 N2 相关场景单独经最终 Replay 可执行文件运行两遍 | 全部通过且检查点一致；命令和逐场景结果保存于 `targeted-final.json` 及对应 JSON / log，完整核心检查再次运行这六个场景。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 退出 0，双架构编译链接及 dSYM UUID 核对通过；每架构仅原有 7 条 unused-function 警告，无新增警告。日志 `release-build-complete.log`。 |
| `git diff --check` | 退出 0；文档与普通 Replay 路径已同步。 |

以上相对证据路径均在 `.build/inline-batch-retention-20261011/`。统一证据索引为 `verification.json`，记录源散列、实际 UUID、失败历史和未执行范围。首次完整快照检查在 Accurate 离线 OCR 子进程的 120 秒期限超时（`snapshot/.build/debug/20261011T052316Z-8f5feb`），其余五项离线测试通过；使用独立测试 bundle ID 重跑后六项及全部核心检查通过，没有修改离线 OCR 代码，也不据重跑通过推断最初超时的完整根因。最早的工作区模块检查还遇到同时新增的姓名牌用例失败；后续固定快照中的当前用例已通过，该处修正不属于本轮 N2。

准备失败亦保留：首次正式构建因快照未含忽略的公开资料库而停止，补入既有资料包后成功；早期字段顺序夹具的两段被正常分组为一段，随后改为不同列，并以真实字段移除检查旧/新结果索引；初版重启夹具误以为 Replay 会清空已确认字段，按现有重启边界修正输入期望。详见 verification.json 的失败记录，不把这些准备失败算作通过。

修复验证阶段未安装、启动真实采集、调用真实翻译服务、读取真实凭据、提交、推送或发布。合成检查验证未重发原长请求、当前结果映射及旧交付保护，不证明真实服务的计费、等待时长或实际面板显示。最短现场验收：安装包含此补丁的构建后，在长正文等待期间让独立时钟变化，确认正文能正常返回并显示当前时钟；再改正文或翻页，核对旧正文不覆盖新页。其它设备、Intel 实机与长期运行仍单列。

### 本次独立提交核对

本次暂存基于 `ec63a75`，只包含 N2 处理、请求 owner、6 个 Replay 和相关文档。用 `git checkout-index --all --prefix=.build/inline-batch-retention-20261011/commit/snapshot/` 导出实际待提交版本，执行 `FY_CAPTURE_CARD_BUNDLE_ID=com.nanami.yiya.n2-commit-20261011-ocr python3 scripts/debug.py check --timeout 300`，退出 0，85 条记录全部 passed，36 场景各两遍（72 条），0 项登记缺口，source_unchanged=true；11 项核心套件包含模块和翻译交付检查。报告 `commit/snapshot/.build/debug/20261011T053716Z-3f5f4b/summary.json`。该提交的测试数量与上方完整工作区快照不同，因暂存未包含其它聊天新增的场景。

同一索引另导出 `commit/build-snapshot/`，补入既有公开 reference.sqlite 后执行 `ARCHS='arm64 x86_64' bash scripts/build-app.sh`，退出 0，双架构编译链接及 dSYM UUID 核对通过；每架构仍为原有 7 条 unused-function 警告。日志 `commit/build.log`，统一索引 `commit/verification.json`。最终只补充这段文档记录，生产代码和夹具与已验证索引一致。未安装或推送；实机验收范围仍按上方最短步骤单列。
