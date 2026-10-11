# 翻译模型统一与服务测试结果归位

2026-10-10，用户确认只保留一个「翻译模型」，供实时字幕、翻译当前界面和测试翻译共同使用；学习模型保留为可选高级设置。

## 根因与修复前证据

原 `testTranslation:` 传 `modelOverride:nil`，请求使用 `modelField`；`translateTextRealtime:` 和长短界面批次另读 `realtimeModelField`。因此两个字段不一致时，服务测试成功不能说明实际实时模型可用。服务测试状态原在左侧导航底部，成功样例还会写入游戏字幕。

先新增生产 HTTP 边界回归，再运行 `bash scripts/run-translation-trace-tests.sh`。修复前退出 2，失败断言为 `realtime subtitles use the same translation model as the service test`。证据保存在忽略目录 `.build/unified-translation-model/before.log`；仅使用合成文字、设置与模拟 HTTP。

## 当前行为

- `objc/LiveCaptionTranslator.m` 删除独立实时模型控件和写入项。实时对白、整屏快照、长短贴译批次和服务测试统一在请求边界解析 `configuredTranslationModel`，保留既有按实际请求模型关闭推理的兼容逻辑、批次超时与服务测试独立任务归属。
- 原「模型名」改名「翻译模型」。旧配置优先保留非空 `model`；仅在其为空时回退旧 `realtimeModel`，均为空时使用既有普通翻译默认值 `gpt-4.1-mini`。保存后只写 `model`，不再写 `realtimeModel`。
- 「学习模型（可选）」收进默认折叠的「高级选项」，空值与翻译请求共用相同回退；非空学习模型保留。服务预设同步学习配置，保留学习覆盖值。
- 服务状态与「测试翻译」按钮同一行，下方标出测试模型，并显示成功样例或完整可选、可复制的错误说明。重复测试、改地址、改模型或改 Key 清除旧结果，过期回调不能回填。测试结果不替换游戏字幕或实时错误说明。
- 用户于 2026-10-11 选择不增加模型冲突确认界面。实际对白字幕、实时界面或手动「翻译当前界面」失败时，现有错误位置首先提示“请前往「翻译服务」，点击「测试翻译」重新检查当前模型服务。”，随后保留原错误原因；字幕只截短原因，不截短指引。成功翻译后清除旧提示。OCR、采集、权限错误沿用原提示，服务测试本身沿用同页错误结果；不会额外发请求、切换模型或清空 Key。
- 模型合并不改变 `VERSION`、Bundle ID 或 Key 保存位置。2026-10-11 后当前源码跨应用版本读取已有 Key，版本只作保存时元数据，完整合同见 [API Key 本机保存约定](api-key-storage.md)；下方 2026-10-10 的测试记录反映当时的同版本行为。

## 本轮验证

| 命令 | 结果与范围 |
| --- | --- |
| `bash scripts/run-translation-trace-tests.sh`（修复前） | 退出 2；新增请求一致性断言复现失败 |
| `python3 scripts/debug.py check`（最终代码） | 退出 0，`outcome=passed`、`source_unchanged=true`；72 项检查，含模块、隔离、采集卡离线、生产翻译链路、布局及 30 个 Replay 场景各两遍 |
| 合成 `LocalAPIKeyStoreTests` 无窗口执行 | 退出 0；18 项检查，覆盖同版本多次读取、重建保留、版本变化、私有权限、失败保留和清空 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh SettingsInteractionTests` | 退出 0；仅编译，不表示原生 UI 已执行 |
| `FY_TEST_COMPILE_ONLY=1 bash scripts/run-tests.sh` | 退出 0；仅编译，不表示原生 UI 已执行 |
| `python3 tests/DistributionTests.py` / `python3 tests/UpdateDistributionTests.py` | 退出 0；6 / 17 项检查 |
| `bash scripts/package-app.sh` | 退出 0；0.2.1 build 39，arm64 + x86_64，dSYM UUID 对应 |
| `git diff --check` | 退出 0 |

核心报告：`.build/debug/20261010T083030Z-8d27ff/summary.json`。专项、编译和构建日志在 `.build/unified-translation-model/`。

新增请求与状态回归位于 `tests/TranslationTracePipelineTests.m`，覆盖所有翻译入口的一致模型、旧配置迁移和保存、学习回退与覆盖、预设、模型编辑取消旧测试、404 失败与重试、运行/暂停时游戏字幕隔离。同版本 Key 测试将合成凭据写入模拟本机存储，禁止再次写入，再保存模型配置；成功证明模型调整不依赖凭据重写，也不把 Key 写入普通设置。

`tests/SettingsInteractionTests.m` 增加按钮与状态同页并排、唯一翻译字段、高级学习项折叠/展开、可选择文本及 720/1320 宽度的原生布局断言。现阶段仅编译；实际执行与安装待用户安排桌面时段。真实 Key、真实 API、设备和游戏体验未测试；没有推送或公开发布。

### 本机手动验收包

用户询问如何验收后，核对发现 `dist/译芽.app` 为未签名组装包，不能以其构建成功代替可启动交付。工作区路径中签名两次报 `resource fork, Finder information, or similar detritus not allowed`，包括清除扩展属性后仍失败；未据此修改签名检查或用户安装。

使用安装脚本已有的 `ditto --noextattr --noqtn` 方式复制到本机缓存的独立目录，再完成固定 Bundle ID / designated requirement 的 ad-hoc 签名。`codesign --verify --deep --strict` 退出 0，Info.plist 为 0.2.1 build 39。可打开的验收包位于 `/Users/nanami/Library/Caches/com.nanami.fuyi-build/service-model-acceptance-9nwgvC/译芽.app`；未替换 `~/Applications/译芽.app`，也未自动启动或访问真实凭据。用户先退出旧版，再打开此包；此包共用原 Bundle ID 的本机设置、Key 与学习数据，不是数据隔离环境。

## 最短手动验收

1. 同版本安装后打开「翻译服务」：已有 Key 自动恢复，只显示一个翻译模型，学习模型在高级选项中。
2. 点击测试翻译，核对按钮旁状态、下方模型与示例译文；填错翻译模型后重测，核对同页错误提示，恢复正确模型后可重试。
3. 运行中测试服务、暂停后再测试，核对游戏字幕仍保留原内容；修改模型时旧测试结果立即作废。
4. 缩窄窗口到 720 pt，检查按钮、状态和错误说明换行，没有横向溢出；无需重复采集卡或全部游戏验收。

## 2026-10-10：补齐预览中的原生图标和结果样式

用户验收指出原生服务页比网页预览简陋，缺少测试按钮播放图标、成功勾和模型信息的视觉层次。源码证据：`translationCard` 使用普通 `NSButton` 和数行无背景标签；共享 `FYWorkspaceButton` 的自绘逻辑也只绘制标题，没有处理 `NSButton.image`。原生视觉尚未完整实现，不是模型请求不一致。

先在真实服务请求链路回归中要求模型提示注明「与实时字幕一致」，并增加成功／失败语义颜色与结果可见性的断言。修复前 `bash scripts/run-translation-trace-tests.sh` 退出 2：`service test explicitly identifies the shared realtime model beside its results`，记录在 `.build/service-page-polish/before.log`。

- `FYLearningViews` 新增 20 pt 原生矢量小图标，包含播放、模型、圆圈勾、圆圈感叹号与时钟；共享圆体按钮支持左侧图片的实际绘制和宽度，不改变既有无图按钮及导航插画。
- 服务测试区使用浅草绿主按钮、同排图标与状态文字、小模型图标和一致性说明、独立圆角结果框。成功使用 `serviceSuccess` / `serviceSuccessSoft`，失败使用 `serviceError` / `serviceErrorSoft`；保留奶油背景、原生选择和完整换行。
- `presentServiceTestState:error:result:` 统一空闲、等待、成功和失败的视觉状态；等待中禁用按钮，重试清除旧结果，修改服务设置恢复空闲。凭据文件读取／保存失败同样显示可见的红色错误框，保留原文件；过期回包不能恢复旧图标或旧底色。
- `TranslationTracePipelineTests` 用参数记录控件观察生产回调更新的图片、按钮状态、语义颜色、卡片底色及隐藏状态，不重写请求逻辑；新增保存失败后错误仍可见且合成原 Key 保留。`SettingsInteractionTests` 检查实际主题按钮、图标、结果卡和 720／1320 pt 下图标位置，并为成功／失败截图使用生产呈现方法。

验证：专项无界面回归退出 0；最终 `python3 scripts/debug.py check` 退出 0，报告 `.build/debug/20261010T110320Z-4d886f/summary.json`，72 项记录全部通过，`source_unchanged=true`；`FY_TEST_COMPILE_ONLY=1 bash scripts/run-learning-app-tests.sh SettingsInteractionTests` 退出 0，仅编译；`bash scripts/package-app.sh` 退出 0，双架构 0.2.1 build 39，dSYM UUID 匹配；`git diff --check` 退出 0。构建只有已有的 7 条未使用函数警告，无新增 UI 编译警告。日志在 `.build/service-page-polish/`。

本轮新的已签名验收包：`/Users/nanami/Library/Caches/com.nanami.fuyi-build/service-ui-acceptance-gydqrW/译芽.app`，`codesign --verify --deep --strict` 退出 0。二进制 UUID：x86_64 `6D156F6C-5E14-324B-B626-849AE80F700D`，arm64 `FC53CDC9-E600-3447-88C7-48EC3C820420`。这是图标修订后的包；前文 `service-model-acceptance-9nwgvC` 为上一轮仅统一模型的历史验收包。

未安装、未启动正式应用、未读取真实凭据或调用真实 API；版本仍为 0.2.1，同版本自动读取 Key 的合同未变。实际原生桌面布局和外观尚未验收，已向用户请求明确桌面测试时段，未收到回答前不启动 UI 套件。最短验收只需打开新包的「翻译服务」页：检查播放图标和模型行，测试正确／错误模型，观察勾／感叹号与结果底色，并缩窄窗口检查换行。
