# 译芽 · Yiya!

**Mac 开发分支 `dev0.2.1_261009`：姓名排除及最近台词修补 `163e48f` 已推送，本机已安装 0.2.1 build 66，用户复测确认本轮通过。** AI 侧栏只手动开关，展开 / 收起时最小内容宽度为 1100 / 720 pt；拖动和切页保持显隐选择。实时页先读中文，再查看原文，空状态收紧；中文与当前对白正文统一 19 pt，点击选中保持字号；翻译服务支持 10 个预设、自定义 URL 与可直接输入的模型名。行为与证据见[窗口缩放](docs/window-resize.md)、[阅读布局](docs/live-reading-layout.md)、[服务组件](docs/translation-service-settings.md)。

build 59 集成代码的新增缩放回归、五组相关 UI、111 项核心检查及双架构打包通过，安装身份已核对。完整视觉套件仍有修改前已复现的「已选中」徽标失败，正式 build 59 的真实鼠标体验、设备及跨机器验收待完成。本轮字号修补的三组原生 UI 回归通过，完整核心结果见[阅读布局记录](docs/live-reading-layout.md)，本轮字号修补提交至 Mac 开发分支。当前交付与规则入口见[维护约定](docs/project-maintenance.md)。

2026-10-11 本机 build 66 追加最近台词修补：历史代表选择曾把纯正文当作缺行，重新显示带姓名的旧记录；现保存确切版本的姓名栏证据，正文完整对应时选择纯正文原文、译文及点击身份。学习套件及 121 项核心记录通过；正式应用重启后，最近列表、点击打开后的原句及恢复运行的实时页均已观察到不带姓名，用户随后复测确认通过并授权提交、推送。正文正常提到的人名与旧快照保留。完整检查、安装身份和现场范围见 [对白姓名排除记录](docs/dialogue-speaker-exclusion.md)。本轮 Mac 修补已提交并推送为 `163e48f`。

同一 build 61 已按确认的预览接入「查看原句」悬停词卡：停留约半秒显示读音、词义与来源，原文保留原生选择、复制及自然换行。新增查句悬停回归、五组相关原生 UI 回归和 115 项核心执行记录通过；本轮查句悬停提交至 Mac 开发分支，真实游戏体验待确认。行为、命令与安装证据见[阅读布局记录](docs/live-reading-layout.md)。

**公开版本仍为 [v0.2.1 正式版](https://github.com/onecoffeecup/yiya-translator/releases/tag/v0.2.1)（2026-10-08，build 17）。** 开发分支推送与本机安装没有更新 Release 附件或 Sparkle 清单。build 17 的 55 步完整本机回归和独立应用手动升级验收通过；新开发版的安装不能替代公开更新或跨机器验收。

0.2.1 已提供「译芽 → 检查更新…」，首次手动安装后可通过 Sparkle 安装后续公开版本。开发源码及本机 build 66 已跨版本保留 API Key，公开 build 17 从不同版本升级时仍使用旧重填规则。机制见[自动更新](docs/automatic-updates.md)和[Key 保存合同](docs/api-key-storage.md)，已发布内容和验证范围见[发布说明](docs/发布说明.md)及[检查记录](docs/发布检查结果.md)。

在游戏里，读懂日语。一个 macOS 实时字幕翻译与日语学习工具。

译芽截取指定窗口的文字区域，在本机用 Apple Vision 识别日文或英文，再调用你配置的翻译接口，把中文显示在悬浮字幕窗里。它最初是为了通过采集卡和 QuickTime 玩日文乙女游戏而做的。

已提供 Apple Silicon + Intel 双架构构建；实际体验主要在作者的 Mac 上验证。需要 macOS 13 或更高版本、屏幕录制权限，以及你自己的翻译服务 API Key。此版本免费，接口调用费用由服务商从你的账户收取。


## 可以做什么

- 实时翻译对白；默认自动识别整画面，可调整字幕字号、透明度和配色。独立姓名栏确认后只翻译下方对白，正文里提到的人名保留；机制与验证见 [对白姓名排除](docs/dialogue-speaker-exclusion.md)。
- 可启用「仅翻译手动框选区域」，同时限制实时翻译和当前界面识别；框选层对准游戏画面，Esc 可取消。详见 [识别范围使用说明](docs/识别范围.md)。
- 「字幕外观」切换长对白字幕与界面贴译，分别选择黑底白字、白底黑字、粉底深字或译芽花境，并在同页查看即时示例。字号、字色和尺寸分别保存，背景不透明度共用；短译文的长卡高度随实际文字收紧。详见 [字幕外观](docs/subtitle-appearance.md)。
- 识别输入源可选「窗口截图」或「采集卡」：采集卡直接读外接采集设备，绕开 QuickTime 录制条对台词的遮挡；字幕仍显示在你选中的 QuickTime／OBS 窗口上。详见 [采集卡输入](docs/采集卡输入.md)。
- 用「翻译当前界面」识别菜单、选项和公告；也可开启实时贴译。
- 查看最近台词、固定原句、点击或拖选词语、按需分析语法及追问 AI。
- 当前开发源码的「翻译服务」提供预设与自定义地址，预设模型名仍可自由输入；界面和预设列表独立维护。实现、迁移与验证范围见 [服务设置组件](docs/translation-service-settings.md)。
- 语法先返回简短分析；「展开解释」按需补充所选条目的用法与例句，「深度复核」主动补查整句，失败保留已有结果。见 [语法分析与按需解释](docs/grammar-analysis-actions.md)。
- 收藏词语、语法和句子，保留语境并进行遮义复习。
- 在收藏词详情里离线查看词典读音、英文释义、日文例句及社区 JLPT 参考等级。

## 项目截图

以下为译芽界面展示，游戏画面与示例文字不属于译芽自带内容。

![译芽界面截图 1](docs/images/screenshots/yiya-01.png)

![译芽界面截图 2](docs/images/screenshots/yiya-02.png)

![译芽界面截图 3](docs/images/screenshots/yiya-03.png)


## 下载后怎么用

1. 在 [v0.2.1 Release](https://github.com/onecoffeecup/yiya-translator/releases/tag/v0.2.1) 下载 `yiya-0.2.1.zip`。
2. 解压后先读「先读我.txt」，把「译芽.app」拖到应用程序文件夹。
3. 按 [首次打开说明](docs/首次打开说明.md) 打开应用并授权屏幕录制。当前包使用 ad-hoc 签名，尚未经过 Apple 公证。
4. 按 [API Key 配置教程](docs/API-Key配置教程.md) 配置服务，点「测试翻译」。
5. 在「运行设置」选择目标窗口和文字区域，再点「开始翻译」。

下载版已内置词典；不需要额外下载资料包或安装开发工具。现有 0.2.0 用户先手动安装一次包含 Sparkle 的版本，之后可使用应用内更新。已发布 0.2.1 build 17 从不同版本升级时仍需重填一次 Key；后续包含跨版本保留改动的包可直接沿用旧 Key。

## 隐私与资料

画面识别在本机完成；翻译与 AI 学习会把相关文字、问题和上下文发送到你填写的接口地址。API Key 会随认证请求发送给该服务。远程服务地址须使用 HTTPS；明文 HTTP 仅允许本机回环地址。API Key 保存在当前用户的本机应用数据文件 `~/Library/Application Support/com.nanami.fuyi/credentials/api-key.json`，文件权限为 0600；当前开发源码在重启、重建、重装、build 递增和跨应用版本更新后均自动读取。此文件不在源码或应用包中，不会随安装包分发。升级前生成的设置备份可能仍含旧 Key，若曾分享备份请到服务商撤销并重建。 详细规则见 [API Key 本机保存约定](docs/api-key-storage.md)。

设置和学习记录留在本机。学习数据库位于 `~/Library/Application Support/com.nanami.fuyi/learning.sqlite3`，最近台词最多保留 5 条，收藏及其语境另行持久保存。当前开发源码只把已有非空译文的记录计入最近台词，等待或失败的翻译不占这 5 条；实现与验证见 [最近台词收录规则](docs/dialogue-history-translated-only.md)，公开附件尚未更新。公开资料包不包含用户的台词、收藏或凭据。

离线资料由 JMdict、Tatoeba 和 OpenJLPT 整理而来，词典释义为英文，中文语境解释可能由 AI 或用户提供。JLPT 等级属于社区参考，资料和 AI 解析都未经过完整人工审校。来源及许可见 [第三方资料说明](THIRD_PARTY_NOTICES.md)。

另已准备独立的 N1/N2 中文词汇文字资料包，含 7,260 个词条和中日例句，来源为 egg rolls 的 Anki 牌组，采用 CC BY-NC 4.0，仅限非商业用途。当前已本地打包，尚未发布或接入正式 App；内容、来源和校验值见 [文字资料包说明](docs/data/jlpt-n1-n2-text.md)。

## 从源码构建

Debug 与回归入口见 [DEBUG_WORKFLOW.md](DEBUG_WORKFLOW.md)，架构与实施依据见 [审查记录](docs/debug-architecture-audit.md)。在源码根运行 `python3 scripts/debug.py check` 可无设备、无窗口、无真实 API 执行生产链路 Replay 与核心检查；报告明确单列已知产品缺口。每次修复 Bug 前需先按 [AGENTS.md](AGENTS.md) 复现并验证根因，修复后运行相关回归。真实采集和用户体验仍需单独验收。

本仓库为唯一维护源码；维护者本机的旧根目录副本已于 2026-10-08 归档，不再同步或用于构建。目录与文档归属见 [维护与归档约定](docs/project-maintenance.md)。

需要 macOS、Xcode Command Line Tools（`clang` 等）和 Python 3.9+。工程使用 Objective-C / AppKit，构建时下载锁定的 Sparkle；框架随应用内置，玩家无需另装运行时。

源码中保留词典的来源和校验清单，约 154 MiB 的数据库由 Release 附件分发。先从同一 Release 下载 `fuyi-reference-20261004.zip`，然后在源码目录运行：

```bash
python3 scripts/reference-data.py install "$HOME/Downloads/fuyi-reference-20261004.zip"
scripts/build-app.sh
scripts/run-checks.sh
scripts/install-app.sh
open "$HOME/Applications/译芽.app"
```

`install-app.sh` 会退出正在运行的译芽、备份原 App，再安装到 `~/Applications`；你的学习记录位于独立的数据目录。仅构建或检查时不必运行安装脚本。

`run-checks.sh` 默认执行无界面基线；独立入口为 `bash scripts/run-headless-checks.sh`，GitHub Actions 使用同一入口。桌面测试需先安排空闲时段再设 `FY_TEST_ALLOW_UI=1`；默认检查不会占用桌面或读真实 Key。源码清单统一在 `scripts/lib-sources.sh`；发布构建使用 `-O2 -g`，dSYM 与二进制 UUID 核对后保存在本机 `dist/symbols/`，不放进玩家安装包。

详细步骤见 [源码构建](docs/源码构建.md)。维护者打包和发布见 [发布流程](docs/发布流程.md)，当前验证范围见 [发布检查结果](docs/发布检查结果.md)。

## 视觉规范

项目已接入用户确认的「奶油棕花境」：暖奶油底、深棕圆体、浅草绿按钮、圆角阅读卡片，以及左下角樱花树与猫咪。中文采用华文圆体，日文采用 Hiragino Maru Gothic；字体不可用时回退至系统无衬线字体，不随包分发系统字体。

当前界面采用「奶油棕花境」样式；设计过程、内部交接和验收截图仅在维护者本机保留，不随公开源码分发。公开仓库包含运行所需的原创 UI 资产，验证范围见 [发布检查结果](docs/发布检查结果.md)。

主窗口、AI 对话、字幕浮窗、快捷查句及原句悬停共用新样式。字幕主题「译芽花境」沿用索引 3；原黑/白/粉主题、字号、透明度、位置与设置保持兼容。安装名为 `译芽.app`，继续使用 `com.nanami.fuyi` 和原学习数据库。实际预览始终展示真实采集画面并保持图像比例，演示场景仅用于隔离测试。

## 已知限制与反馈

- 手动框选优先适配主屏幕上的 QuickTime；多屏幕、全屏快捷键及不同 macOS 版本仍需更多实际验证。
- 尚无正式 Developer ID 签名和公证，首次安装需要按系统提示处理；不同机器及升级后的权限行为尚待验证。
- OCR 可能漏字或读错，翻译和语法解析也可能有误；不适合需要保证准确性的专业场景。
- 支持 OpenAI 兼容的 Chat Completions 接口，不保证所有第三方服务和模型都兼容。模型可用性及收费以服务商为准。
- 暂无真题库、附件导入和术语表。0.2.1 已提供应用内更新；长时间运行、中文输入法及真实窗口边缘拖拽仍需专项验收。
- 采集卡模式已支持界面贴译，须先定位或校准 QuickTime／OBS 中的视频区域；无法定位时会提示，不按整个窗口尺寸强行落位。与 QuickTime 不承诺逐帧同步，首次使用需要相机权限。
- 一次现场试用中，QuickTime 已显示游戏画面，但译芽的采集卡输入停在「采集中」且没有收到新帧；原因尚未确认。遇到同样情况可改选「窗口截图」继续使用，并附诊断信息反馈。

试用反馈请附系统版本、芯片型号、使用场景和报错信息，隐藏 API Key 与个人内容。可按 [首次安装验收](docs/首次安装验收.md) 逐项检查，并在本仓库 Issues 中反馈。

「运行设置 → 诊断与反馈」可运行检测并导出最近的权限、窗口和错误状态，通过聊天交给开发者；也可点击「通过邮件反馈…」，保存诊断包后打开附带文件的邮件草稿，收件人为 `yiyatranslator@163.com`，由用户确认发送。诊断包不含密钥、截图或台词。详见 [诊断包说明](docs/translation-text-trace.md)。

## 许可

项目源码、脚本和原创文档采用 [MIT](LICENSE)。第三方词典、例句和等级数据使用各自的原有许可，参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；MIT 不替代这些资料的许可。
