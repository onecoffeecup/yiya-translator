# 翻译服务设置组件

2026-10-11，用户要求把「服务设置界面＋预设列表」从主窗口拆出，并按已确认的交互预览接入正式源码。此次开发位于 Mac 分支 `dev0.2.1_261009`；不涉及 iPadOS 或 Windows。

## 维护边界

| 文件 | 职责 |
| --- | --- |
| `objc/FYTranslationServiceSettings.h/.m` | 10 个预设的集中目录；模式、服务地址、翻译模型、各服务的模型草稿和自定义草稿；旧模型配置迁移。仅依赖 Foundation，不读取 Key、不发请求。 |
| `objc/FYTranslationServiceView.h/.m` | 原生表单、服务卡片、模式切换、普通模型输入框、常用模型选择、默认收起的学习模型，以及测试状态和结果展示。通过回调连接宿主。 |
| `objc/FYTranslationManager.h/.m` | 服务地址校验、内部请求适配、HTTP/JSON 解码；继续提供共享翻译缓存、任务归属和交付策略。 |
| `objc/LiveCaptionTranslator.m` | 挂载组件；保存/读取设置与现有私有 Key 文件；编排测试、实时/界面翻译和学习配置同步。旧字段引用和三种旧预设方法保留为兼容入口。 |

以后改表单排版、字段说明或增加预设，优先修改前两个文件。组件没有依赖或导入 AppDelegate；宿主回调捕获弱引用，组件生命周期随主窗口保存。主窗口中的旧字段是同一组原生控件的引用，用于既有运行时和隔离回归，不是第二份界面。

## 玩家交互与保存

- 「选择预设」提供 DeepSeek、OpenAI、GLM、Claude、Gemini、通义千问、Kimi、豆包，以及硅基流动、OpenRouter。预设自动填写服务地址和默认模型；豆包、硅基流动保留空模型，让玩家复制自己的完整模型或接入点 ID。
- 预设模型使用普通 `NSTextField`，可直接输入、粘贴和修改。旁边的「常用模型」是独立选择入口，选择后复制到文本框并回到提示项，文本框继续可编辑；只有一个或没有常用模型时隐藏该入口。
- 「自定义 URL」只填写服务地址、翻译模型和已有 API Key，不显示接口类型。预设地址行的「改为自定义」复制当前地址和已编辑模型；顶部模式切换保留独立草稿。
- 预设模型修改、当前配置方式和自定义草稿保存在已有设置字典。旧设置继续优先迁移非空 `model`，为空才读旧 `realtimeModel`；已保存的地址及有效模型不被预设默认值覆盖。新的空模型保留为空，实际翻译会提示先填写模型，不偷偷替换服务模型。
- API Key 沿用 [本机保存合同](api-key-storage.md)，仍由宿主保存和清空；不进入组件配置字典或普通偏好设置。切换预设不会清空或自动换 Key。测试使用同一翻译模型，结果仍位于服务页，不覆盖游戏字幕。

模型建议来自预设目录，是可编辑的静态默认值；不自动请求模型列表，也不能代替玩家账户的模型权限。各服务地域与 Key 来源见表单说明。

## 内部服务适配

普通地址继续使用 OpenAI 兼容的 `chat/completions`。精确的 `api.anthropic.com` 主机或玩家明确填写的完整 `/messages` 地址使用 Claude Messages；不会根据模型名猜测接口，因而通过 OpenRouter 等平台调用 Claude 仍走平台自己的兼容接口。其他第三方地址需要服务提供 OpenAI 兼容调用；Messages 代理可填写其完整 `/messages` 地址。

Claude 的系统提示放在独立 `system` 字段，使用 `x-api-key` 与 `anthropic-version`，读取返回的 text blocks 并忽略 thinking blocks。不发送新版 Claude 已不支持的 temperature 参数。翻译保持 15 秒短请求和现有长批次超时，学习保持 30 秒、取消代次和完整 JSON 校验；学习遇到 `max_tokens` 截断仍失败。接口依据：[Claude Messages](https://platform.claude.com/docs/en/api/messages/create)、[认证与版本](https://platform.claude.com/docs/en/api/overview)。

预设中的 Sonnet 5.5 使用 `between_tools`，Haiku 5.5 使用 `disabled`；Opus 5.5 保留必须启用的思考。已知的 Claude 5.5 型号设低 effort。官方 GLM 5.3、Kimi K3 和 Gemini 3 型号同样设低 effort，不强行关闭思考；Kimi 省略其不支持的 temperature。需要思考的这些型号，输出总预算为 `max(4096, 请求译文预算 + 2048)`，保持有界，并给最终文本留空间。规则按已知型号和精确官方主机选择（Messages 中的已知 Claude 型号除外），不对未知服务和未知模型猜测参数；这些适配不会出现在玩家表单里。依据：[Claude 思考规则](https://platform.claude.com/docs/en/build-with-claude/thinking)、[GLM 5.3 Flash](https://docs.z.ai/guides/vlm/glm-5.3-flash)、[Kimi 参数](https://platform.kimi.com/docs/api/models-overview)、[Gemini 兼容接口](https://ai.google.dev/gemini-api/docs/openai)。

地址校验与原有 HTTPS/本机回环 HTTP 规则共用，不因新适配而放宽凭据传输限制。预设和回归不读取玩家凭据、不自动测试服务、不消耗真实 API Token。

## 本轮检查

- `AnthropicTranslationTests`：修改前失败于认证/版本头断言，修改后 8 项合成检查通过，覆盖请求字段、超时、多文本块、思考块和畸形返回。
- `TranslationServiceSettingsTests`：63 项通过，涵盖 10 个预设默认型号的实际请求构造、思考预算与参数、旧模型迁移、模型草稿、模式切换、重新读取、空模型保留、无 Key 设置字典及 URL 安全边界。
- `bash scripts/run-module-tests.sh`：通过，包括现有翻译管理、任务取消、Key 保存等回归。
- `bash scripts/run-learning-tests.sh`：通过，新增 Claude 学习的完整/截断 JSON 回归，保留原有学习检查。空模型回归在修改前失败，修复后证明不进入传输层、不自动换模型；原 HTTP、取消与主线程夹具明确提供合成模型，继续验证原分支。
- `bash scripts/run-translation-trace-tests.sh`：通过，旧配置迁移、统一模型、测试取消与状态、字幕隔离及现有生产管线检查保留；当前空模型在翻译与学习配置中都保持为空。
- `bash scripts/build-app.sh`：arm64 + x86_64 构建通过，dSYM UUID 与可执行文件核对通过。后续构建使用此脚本的同一构建逻辑，把输出与模块缓存放进本轮独立目录，避免其它任务的构建覆盖对象文件。
- 用户明确安排本轮桌面时段后，`FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh TranslationServiceViewTests`、`SettingsInteractionTests`、`LocalCredentialSettingsTests` 和 `MainWindowResizeTests` 均执行通过。使用隔离偏好、合成 Key 和临时数据库，不请求翻译服务。服务检查覆盖全部预设、普通文本输入、常用模型复制、草稿恢复、Key 清空，以及 720～1600 宽度的实际布局与尺寸保持；960 宽度同时保留 AI 侧栏，触发表单紧凑排列。
- 原生截图复查发现不存在的 `panel` 主题名会返回黑色，已改为现有 `paper` 色。新增输入背景和卡片像素检查先失败后通过；按钮保持合适宽度，两个模式按钮随页面伸展。窗口测试调用现有 live-resize 委托及 AppKit 拖动优先级，避免用一次 `setContentSize:` 假定尺寸已生效。截图位于 `.build/test-results/TranslationServiceViewTests/`，包含预设、自定义和 720 宽度预设界面，均为原生 AppKit 渲染，Key 为合成值。
- `python3 scripts/debug.py check --timeout 300`：服务实现的隔离源码副本通过全部 111 项执行记录，报告为 `core-accepted-report/summary.json`，副本在检查期间未变化。源目录位于 Documents，签名 OCR 工具曾阻塞在合成图片读取；未修改系统权限，改用相同源码、规则和夹具的临时副本执行同一入口。另一次离线检查遇到 LaunchServices 的 `kevent` 进程等待错误，重试后通过；这些运行失败保留日志，不计为通过。
- 首轮核心报告之后的共享窗口改动为：空闲宽度约束优先级从 1000 改为 999，以及窗口测试追加程序设置尺寸检查。随后按该轮源码重新执行服务/窗口两个原生套件并通过，双架构构建通过。历史日志为 `service-ui-current.log`、`resize-ui-current.log`、`build-current.log`，由 `acceptance-evidence.json` 关联；下方图标补齐记录包含这些窗口改动的最新完整核心结果。

详细日志在本机忽略目录 `.build/translation-service-refactor/`。上述源码与隔离检查阶段未安装或重启正式应用；随后用户授权的本机安装见下方记录。公开附件未更新，真实账户和服务调用未验收。

## 最短手动验收

1. 打开「翻译服务」，切换 GLM、Claude 等预设，直接输入自定义模型名；切换其他预设再回来，确认手填模型保留。
2. 在「常用模型」选择一个建议，再修改文本框，确认仍可输入；切换「自定义 URL」，填写自己的服务地址和模型，确认没有接口类型选项。
3. 收窄、放大窗口并滚动到测试区，确认卡片与字段都在页面内；退出重开后确认配置恢复。需要检查真实服务时，使用玩家自己的 Key 点击「测试翻译」，这一步未由隔离测试代替。

## 预览图标补齐

2026-10-11：用户指出原生截图遗漏了交互预览顶部的图标。对照预览，实际缺少「选择预设」的列表图标和「自定义 URL」的链接图标；测试按钮和模型提示的图标原本已接入。原因是服务组件创建两个模式按钮时只配置了标题，没有配置图片。

修复集中在 `FYTranslationServiceView.m`：以本地矢量轮廓绘制两枚图标，沿用棕色 `ink`、圆头细线和原生按钮居中排列，不依赖网页图标库或主控制器。可见按钮标题继续提供无障碍名称，不给装饰图标增加独立朗读项。没有修改预设、服务请求、Key 保存或模式行为。

`TranslationServiceViewTests` 新增两个模式按钮图标存在及左置检查，修复前明确失败于缺图标断言，修复后通过；同时保留 720 / 960 / 1024 / 1320 / 1600 宽度、模型输入和草稿恢复检查，已人工查看本轮原生截图。日志分别为 `icons-before.log`、`icons-ui.log`，构建及核心结果在 `icons-evidence.json` 中关联。此项最短复查为打开「翻译服务」，确认两个模式标题左侧分别显示列表与链接图形。

本轮继续使用同一独立构建脚本完成 arm64 + x86_64 编译及 dSYM UUID 核对，退出 0，日志为 `icons-build.log`。同源码临时副本执行 `python3 scripts/debug.py check --timeout 300`，全部 111 项执行记录通过，`source_unchanged=true`，报告中的全部 318 个源码、规则及夹具文件哈希与维护仓库当前文件一致；报告复制为 `icons-core-report/summary.json`，总日志为 `icons-core.log`。截图另存为 `service-presets-icons-native.png`、`service-custom-icons-native.png`。未读取真实 Key、请求真实 API、安装或重启正式应用。

## 本机安装

2026-10-11 18:21（Asia/Shanghai），用户明确要求安装后，在唯一维护仓库执行 `FY_BUILD_NUMBER=57 bash scripts/install-app.sh`，退出 0。脚本重新完成双架构构建、资源组装，退出运行中的旧版并备份到 `.build/app-backups/`，签名后安装至 `~/Applications/译芽.app`；版本为 0.2.1 build 57。随后通过 `open "$HOME/Applications/译芽.app"` 重新打开，确认运行进程来自该安装路径。

安装前后与启动后仅检查凭据文件元数据，inode、大小、修改时间、所有者及 0600 权限保持不变，未为验证读取 Key 内容。安装包中没有 credentials 目录或 api-key.json；`codesign --verify --deep --strict` 通过，已安装二进制、构建产物及 dSYM 的双架构 UUID 一致。构建前后，最近核心报告的 318 个源码、规则与夹具哈希仍与维护仓库一致。日志与核对结果分别为 `.build/translation-service-refactor/install-build57.log` 和 `install-build57-evidence.json`。本机安装不替代真实服务调用或玩家体验验收，公开附件未更新。

## 提交前验证

用户随后要求提交。提交范围为服务组件、预设目录、内部请求适配、对应测试和文档，包含服务表单所需的原生窗口缩放支持；同工作区的实时页阅读布局、字幕外观与窗口专项测试继续保留为独立工作。按暂存区内容导出临时测试副本后，`FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh TranslationServiceViewTests` 通过，证明本次服务改动可独立于未提交的实时页代码运行；`python3 scripts/debug.py check --timeout 300` 的全部 111 项执行记录通过，`source_unchanged=true`，317 个源码、规则及夹具哈希与待提交内容一致。证据为 `.build/translation-service-refactor/commit-ui.log`、`commit-core.log`、`commit-core-report/summary.json` 和 `commit-evidence.json`，使用合成配置且没有真实服务调用。
