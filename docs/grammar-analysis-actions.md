# 语法快速分析与按需解释

更新：2026-10-08。首次加入 0.2.0 维护源码，随 0.2.1 发布。本次按钮位置已由用户确认；源码检查与本机安装、公开发布分别记录。

## 使用方式

- 首次分析先显示简短语法说明、接续、词汇与整句结构。字段、原文位置和已有调用接口保持兼容。
- 「展开解释」位于所选语法的简短说明下方，与收藏按钮相邻。点击才补充接续、实际用法及一个原创例句；可收起。同一阅读窗口内、同一句同一项的已完成解释保存在内存，再展开不重复调用。换句、关闭查句或修改服务配置后清除。
- 「深度复核」位于「这一句的语法」标题右侧。仅主动点击时检查整句遗漏与疑点，包含原文和已有条目作对照。等待期间仍可读已有结果和展开解释；失败显示原因并保留已有结果，可重试。
- 复核返回的条目仍经过 schema、原文片段、位置、词内误命中、去重与目录等级校验。新条目补充到原结果；没有返回某项不视为撤回，重复项保留原有详情。此操作不保证找全所有语法，也不强求 N1/N2 数量。
- 复核点击、失败提示和成功结果更新均保留当前滚动位置。结果返回时读取最新位置，保留等待期间的继续阅读；查句重建文档后恢复至新滚动视图，只有内容变短时限制到合法范围。专项原生回归已复现并验证修复。
- 主窗口成功的复核保存至当前句版本的原有分析缓存；查句结果可通过「完整学习界面」带到主窗口。展开解释为临时详情，不改数据库 schema 或首次返回字段。

## 后台请求策略

默认 DeepSeek 学习分析关闭隐藏推理（`thinking: disabled`、`reasoning_effort: none`）；原有已知模型继续请求 JSON，未知服务不增加 JSON 专用字段。保留配置的学习模型，未另指定时跟随翻译模型。

首次提示词按结构类别逐句核对，保留词形扫描候选、排版空白处理、原文映射与目录外结构。原文只通过逐句单元传入；每条解释约 20–40 字，词汇最多 8 项、结构 2–8 段；不通过缩减语法目录白名单限制输出。首次 JSON 输出预算 2800–4200 tokens，单个请求超时 30 秒；这不是保证完成时长。

候选未覆盖、条目少、零条目或短句都不自动触发额外请求。只有模型条目的命中片段无法对应原文，才允许至多一次局部修复；局部修复不能加入无关条目，也不会递归重试。修复失败保留已验证条目。取消仍返回取消状态，不回填旧成功结果。

展开解释单次输出预算 650 tokens。主动复核仅一次请求，不再自动追加片段修复；解析失败由界面保留原结果并显示可重试状态。主窗口、查句的按需解释及复核各有独立请求归属，不能取消实时翻译或 AI 聊天任务。

缓存提示词版本为 8；旧版本分析不当作新策略缓存命中。原有 schema_version=1、词汇、整句说明、结构图和等级出处字段均保留。

## 实现范围

后台：`objc/learning/FYLearningAnalyzer.h/.m`、`FYLearningCoordinator.h/.m`。

原生界面：`objc/FYGrammarActionsUI.inc`、`FYGrammarActionState.h`、`FYWorkspaceUI.inc`、`FYImmersiveUI.inc`，并在 `LiveCaptionTranslator.m` 添加状态及切句清理接入。保持奶油棕圆体与原生文本选择复制。主窗口次要来源/重新分析操作另起一行，避免挤压展开与收藏。

不修改采集输入、OCR 分组、字幕跟踪、翻译请求、贴译排版或 Key 保存机制。

## 验证

`GrammarCoverageTests`：单次快速路径、限定修复、空结果、片段/活用/换行、词内误命中、手动复核合并与去重、失败保护、按需解释范围和请求预算。`LearningTests` 检查原有学习模型、存储及编排兼容。

`GrammarActionsAppTests`：在隔离数据库与合成 Key、mock 请求下操作真实 AppKit 按钮，检查等待、失败保留、重复点击、解释缓存、复核落库、关闭后的晚到结果与原生渲染。列入 `run-checks.sh` 和验收清单；编译通过不得写成运行通过。

2026-10-08 对用户配置的服务执行两段受控测试，均为单次请求：64 字样本 5.33 秒，输入 914 / 输出 983 tokens，返回 5 条语法；19 字样本 2.52 秒，输入 720 / 输出 482 tokens，返回 2 条语法。未建立人工金标准，以上仅反映本次耗时、用量和返回数量，不代表召回率或稳定延迟。请求及凭据不进入文档；原始证据留在本机 `.build/grammar-actions-check/`。

上述后台及原生按钮专项测试已运行通过；QuickSentenceAnalysisTests 既有查句回归运行通过，Apple Silicon / Intel 双架构构建通过。构建的既有 7 条未使用函数警告未新增。

2026-10-08 经用户要求，已使用维护源码重新构建并安装到 `~/Applications/译芽.app`，版本 0.2.0 build 10（Apple Silicon / Intel 双架构），旧应用自动备份。签名校验通过并重新打开应用；安装前后的本机凭据文件保持相同，未修改学习数据库。公开 Release 或下载附件未更新。 同日已追加安装复核滚动位置修复；安装后二进制 UUID 与本轮双架构构建一致，凭据文件保持相同。

## 2026-10-14 编排与原生渲染边界

原初次分析/轻量追问/main或quick展开/深度复核与state配置由Foundation `FYGrammarInteractionCoordinator` 维护。七个原field只由此owner保存，两ActionState各自cache/analyzer/generation和quick结果仍原owner；native字段、字体/颜色、滚动保存/恢复与render方法不改。readonly配置container保留原strong字符串局部别名，Key不加入context identity/日志；native学习模型Trim/空才raw fallback、现有transport绑定与各surface reset/cancel顺序不变。

51独立业务与44实际原/新controller同fixtureO0/O2检查通过，包含版本/代次/item/状态指针、任务strongleases、复核失败保留结果、先current gate后busy释放。只注入synthetic services/native actions，不读真实Key或消耗Token。GrammarActionsAppTests及相关UI只编译，真实scroll/渲染/操作按上文另验。详情见 [Mac深度拆分](mac-decoupling.md)。

子批28进一步将原结构图offset/恢复、quick详情刷新与复核scroll保持独立到无状态`FYGrammarScrollRenderer`。实际SDK layout/frame/bounds调用与更新时before/after重新读取保持，原controller保留明确门面，公有依赖已隔离整套应用支持。独立38与实际原/新controller37同fixtureO0/O2通过，五变异失败且恢复通过；相关四UI仅编译。Native属性事实证明原算法/调用顺序，真实鼠标滚动、字体和文档绘制仍按授权桌面步骤验收。源码未安装/发布，收尾证据见本机`batch28-evidence.json`。

子批29将详情/字段、三highlight、局部selection和main/quick actioncontrols六个原Native算法独立为无状态`FYGrammarDetailRenderer`。保留原UTF16/字符/选区/非background属性、canonical适用范围、selected item指针与alpha0.23、facade动态覆写及hover时序；原104pt/3/4行/字体与raw展开解释保持。39独立与37实际原/新controller同fixtureO0/O2通过，8变异失败后恢复通过。模型/视图与两表面状态仍原owner，没有新请求或取消。四相关UI只编译，实际字体布局/鼠标/选择/高亮体验另验；源码未安装/发布，证据见本机`batch29-evidence.json`。

子批30将原busy、结果刷新、清场、页签和followup显隐五算法移至无状态`FYGrammarResultsRenderer`，原Core7与两个ActionState、view/index/tab不复制。保留result局部捕获、main-only reset/cancel、两代次与两次nil/Tab重入、行样式/空态/scroll与页签优先级。96最小与93原/新controller同fixtureO0/O2通过，八变异失败后恢复；首读取时点变异未被弱活性断言检出，原证据留档，只增加原result身份断言并完整重验。四UI仅编译，真实图/操作/窗口体验另验；源码未安装/发布，收尾见本机`batch30-evidence.json`。

子批31把完整card/info/main-quick structure构造移至零状态`FYGrammarPageBuilder`，保留原视图/数组copy/scroll/tab拥有者、原字体/约束/字符/节点映射和weak Host目标。65独立冷/输入guard、旧64/新65实际controller同fixtureO0/O2通过，新增适配额外证明同一Host只读取一次；六变异失败、恢复65通过。合法输入只验证到首native工厂入口后预定停止，没有构造完整图。完整原/新图fixture两opt及五相关UI均只编译；新GrammarPageBuilderUITests已入统一UI清单。真实卡片/布局/按钮/鼠标/字体体验待授权执行，源码未安装/发布，证据见本机`batch31-evidence.json`。

子批32把列表项与详情收藏/删除异步逻辑移入Foundation Core类方法，原Core七字段不变。Native只适配原按钮BOOL、文字和同步index读取；保留先gate后index且数组参数先求值、selected两次读取、既有store/learning分支、原strong source/item/existing租约与不同stale语义。60最小与61实际旧/新controller同fixtureO0/O2通过，七变异失败且恢复通过；原Core和146其它Native方法精确。五UI只编译，真实收藏/数据库/鼠标体验另验；未安装/发布，证据见本机`batch32-evidence.json`。
