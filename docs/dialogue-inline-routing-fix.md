# 混合对白路由与文字保留修复

2026-10-11，Mac 分支 `dev0.2.1_261009`，修复基线为 `03a1c66ae96b973c1a05b4766488989761dddd28`；代码、合成回归及规则文档随本轮 Mac 修复提交保存。规则全文及源码散列见 [对白和贴译规则](dialogue-inline-mode-rules.md)。

用户确认同一画面中的对白进入字幕窗，选项原位贴译，纯菜单、资料页与公告页仍使用界面贴译。本轮处理审查中已确认的 R1、R2、R8、R9、R14；不把所有待验证边界当成已解决问题。没有更改视觉、窗口、学习数据保留、采集或网络服务配置。

## 根因与生产证据

以下均为合成 OCR；`boundingBox` 是左下原点归一化坐标，Replay JSON 中字段名为 `box`。运行完整生产后处理、模式确认、文本稳定、请求构造、解码和交付；HTTP 及窗口终点由隔离记录器替换。没有真实对白、截图、凭据或设备采集。

R1 的公共输入：

| text | boundingBox |
| --- | --- |
| 今日は図書館で待っています。 | [0.20, 0.12, 0.38, 0.045] |
| 青木 | [0.20, 0.21, 0.06, 0.04] |
| 先に行く | [0.20, 0.75, 0.14, 0.03] |
| ここで待つ | [0.20, 0.61, 0.14, 0.03] |
| 話を聞く | [0.20, 0.47, 0.14, 0.03] |
| 後で話す | [0.20, 0.33, 0.14, 0.03] |

在 0、500、1000、1500 ms 注入相同帧，打开自动模式及生产稳定门，初始模式分别为对白和 UI。合成白底没有姓名栏像素角色，因此这里的青木是文字姓名候选；正向姓名栏统一排除另有既有回归。

| 条目 | 修复前实际结果与预期 | 阶段与当前源码定位 | 最小回归 |
| --- | --- | --- | --- |
| R1 | 1、2 选项通过；3 选项加姓名共 5 块、small=3，或 4 选项 small=4，第二次观察提交 UI。预期同时交付字幕和全部选项。 | 整帧分类与模式确认；`FYContentRouter.m:346` modeDecision、`:1011` looksLikeUIFrame。 | `routing-r1-{1,2,3,4}-small-options-from-{dialogue,ui}`，以及三选项无姓名对照。 |
| R1 分流追加 | 仅修好分类后，第四项与姓名中心距约 0.115，姓名与正文约 0.088，旧 0.12 行距簇把第四项串进正文；实际只贴前三项。预期第四项仍贴译。 | 对白/选项分流；`FYContentRouter.m:461` splitDialogueAndOptions。 | 同一四选项 Replay 的完整 sources/inline/captions；原生测试另覆盖 OCR 数组倒序。 |
| R2 控制词 | 公共正文加 戻る [0.82,0.94,0.10,0.03] 与 メニュー [0.82,0.86,0.12,0.03]，tokens=2 接管 UI。预期正文保留字幕。 | 整帧分类；同上 UI 入口。 | [双菜单词场景](../tests/fixtures/replay/routing-r2-dialogue-two-menu-buttons.json)。 |
| R2 宽行 | 四选项改 w=0.25、h=0.04，增加 明日もここで会いましょう。 [0.20,0.06,0.35,0.045]，六条 substantial 接管 UI。预期两条正文加四项贴译。 | 整帧分类；同上 UI 入口。 | [宽选项场景](../tests/fixtures/replay/routing-r2-four-wide-options-two-dialogue-lines.json)。 |
| R8 | I know. [0.20,0.15,0.25,0.045]；Books are here. [0.20,0.15,0.38,0.045]。分类为对白却被 no/ok 子串删空，零请求。预期完整正文请求和字幕。 | 正文过滤；`FYContentRouter.m:226` filterReasonForText。 | [know](../tests/fixtures/replay/routing-r8-english-know.json)、[Books](../tests/fixtures/replay/routing-r8-english-books.json)。 |
| R8 日文 | 戻らないで。 [0.20,0.15,0.14,0.045] 加 メニュー [0.82,0.80,0.12,0.03]，戻 前缀加菜单词提交 UI。预期保留对白。 | 分类词匹配；`FYContentRouter.m:854` textHitsUIToken。 | [普通戻正文](../tests/fixtures/replay/routing-r8-japanese-modoru-speech.json)。 |
| R9 短英语 | Hello. [0.20,0.15,0.10,0.045]，不进入短句锚点，转 UI 后又删空。预期与同框 Hello! 一样交付对白。 | 分类及 UI 过滤；`FYContentRouter.m:629` isSingleLineDialogue、`:226` 过滤。 | [句号](../tests/fixtures/replay/routing-r9-english-short-period.json)、[感叹号对照](../tests/fixtures/replay/routing-r9-english-short-exclamation.json)。 |
| R9 菜单 | 英语 Back/Next、No/Yes，或日语半角 ｽﾀｰﾄ/ｵﾌﾟｼｮﾝ：位置为 [0.10,0.75,0.12,0.04]、[0.10,0.55,0.12,0.04]。短非日文过滤删英语；No 还被编号装饰门删除；半角假名不在旧有效字符集。预期独立贴译。 | UI 文字过滤；`LiveCaptionTranslator.m:5983` 显式传识别语言，路由过滤同上。 | [英语菜单](../tests/fixtures/replay/routing-r9-short-english-menu.json)、[No/Yes](../tests/fixtures/replay/routing-r9-english-no-yes-menu.json)、[半角菜单](../tests/fixtures/replay/routing-r9-halfwidth-menu.json)。 |
| R14 | うん、約束 [0.20,0.15,0.26,0.045] 实际请求变成 うん、。预期整句保留。 | 正文尾串截断；`FYContentRouter.m:1085` dialogueTextWithoutTrailingButton。 | [正常汉字尾串](../tests/fixtures/replay/routing-r14-natural-trailing-kanji.json)。 |

证据级别：上述指定输入均已由生产路径复现，并由修复后 Replay 检查实际请求源文、模式和交付内容。它们不能证明其它游戏样式或真实浮窗已通过验收。

## 最终修改及影响

`separatedDialogueItemsInItems:` 在旧 UI 计数门之前尝试取独立下方正文。强对白锚点须有假名句读或拉丁句末标点；附近正文按水平重叠、字高和局部行距收拢。其它非控制块必须有上方间隔及宽/高差异。原短行换行对白也可与独立完整控制标签共存。分流复用这份区域边界，避免不同阶段各自认可不同的正文。

无独立区域时沿用原 small/tokens/substantial 菜单门。原生反例覆盖等大小六行完整句列表及宽标题公告；既有四项下方纯选择、带姓名标题的选择列表、短对白、注音、日期、远处背景与同行碎片回归仍保留。此规则依然依赖几何，无法仅由 OCR 判断两组完全相同结构的文字究竟属于剧情还是资料。

正文控制词改为完整标签匹配，并要求外围或小字几何；不再删除 know、Books 等普通词的整行。日文 UI 词要求整条或标点分隔的前缀，英文 UI 匹配保留内部空格。`詳細を見る` 等复合按钮可能少一份词证据，仍按其它 UI 规则分类，需要继续观察实际样式。

短 UI 非日文噪声门仅作用于日语设置，增加半角假名；英语 No/Yes 等有效字段保留。中央、正常字高且以 ASCII 句号结尾的短拉丁句新增对白证据，日期和角落按钮不靠这个分支成为对白。无标点短英语没有因此全量放宽。

取消无角色证据的末尾汉字截断，优先保留完整原文。OCR 已将正文和“使用”等按钮粘在同一个观察中时，现在也保留该尾串；独立控制块仍可按几何过滤，粘连块需要额外结构证据。

## 验证记录

修改前，18 个路由场景中 12 个按产品预期失败、6 个对照通过，报告 `.build/routing-fix-before-5ff9ea/summary.json`。R2 在模式提交检查点断言，避免错误路由异步请求造成无报告退出。随后新增的日文前缀和英语 No 场景也分别失败，报告 `.build/routing-modoru-before.json`、`.build/routing-no-menu-before.json`。修补期间另发现四选项分流失败，记录 `.build/routing-fix-after-dff734/summary.json`。R14 的模拟对白响应去除了只适用于编号批次的 `1.`，源文完整性断言保持不变。

实际执行：

```bash
bash scripts/run-module-tests.sh
bash scripts/run-replay-tests.sh --build-only
python3 scripts/debug.py check --timeout 300
CODESIGN_IDENTITY=- FY_BUILD_NUMBER=67 ARCHS='arm64 x86_64' bash scripts/install-app.sh
git diff --check
```

最终核心报告为 `.build/debug/20261011T131338Z-ee1996/summary.json`：161 项记录通过，20 个新增 Replay 各两遍通过，373 个源码/夹具/媒体散列在检查期间不变。模块中 OCR 后处理 274 条断言、内容路由 200 条断言通过；采集离线工具、生产请求及过期交付、学习、字段稳定、N1/N2 原有回归均通过。检查没有运行真实桌面或设备，注册的 known gap 数为 0 也不表示本文未注册边界已解决。

本机已安装 `~/Applications/译芽.app`，版本 0.2.1、build 67。初次脚本默认按 Git 提交数生成 build 62，发现低于已有本机 build 66 后，使用 `FY_BUILD_NUMBER=67` 重新构建安装；最终身份以下列 UUID 为准，临时 62 不作为交付版本。

- arm64：`93612743-E33F-3FC4-8B31-E42EC5A768A4`
- x86_64：`EFCCD4CE-1148-3736-AB20-82A0341C88A2`

安装、打包、release 和 dSYM 的两架构 UUID 一致，严格签名校验退出 0。安装后 373 个测试快照散列仍一致；凭据目录及文件的权限、大小、inode、修改时间未变，仅核对元数据，没有读取内容。记录为 `.build/dialogue-routing-install/verification.json`；构建日志 `install-build67.log` 有主文件已有的 7 条未使用辅助函数警告，没有新增路由编译警告。未自动启动真实采集，实际桌面显示未由此验收。

## 保留的边界与最短人工确认

R3/R4/R6/R7/R13 仍需专项结构或 Vision 输入证据。R5 对齐远处招牌、R15 拆行选项的处理现象已用合成 OCR 观察到，但缺少区分真实容器的证据，本轮不靠任意距离或合并阈值修补。R10 空正文保留旧字幕、R11 空帧不清模式候选及交互面板暂停模式观察保持原策略。

R12 混合两路仍共享内容修订及全帧稳定门。只有选项变化时，稳定提交可取消并重发未变对白；独立交付合同和独立任务代次尚未实施。N2 的整帧 UI 长批保留不能代表此行为已解决。

本轮没有要求重做整个 App 验收。安装后只需抽查：

1. 有三四个选项的对白页：对白出现在字幕窗，所有选项在原位贴译，已确认姓名栏不出现在对白原文。
2. 纯菜单或资料页：仍在原位贴译；返回对白页后路由恢复。

自动检查验证合成输入及交付数据，实际游戏样式、浮窗位置与长期运行仍待这一范围内的用户确认。

## 提交与推送

2026-10-11 用户授权「commit 然后提交吧」后，功能、合成回归和规则文档提交为 `a6ad14b0740b1fa0a8a60183de6199bd8635b530`，已推送到 `origin/dev0.2.1_261009`，本地提交与远端跟踪分支一致。提交前复核 373 个源码 / 夹具散列仍匹配上述 161 项通过的核心报告；没有因提交另行重建或安装。本次授权是提交及推送指令，不将其记录为新增真实设备或两页场景的现场验收。
