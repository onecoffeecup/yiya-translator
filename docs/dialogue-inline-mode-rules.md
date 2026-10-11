# 对白和贴译判定规则与审查清单

整理日期：2026-10-11。依据 Mac 分支 dev0.2.1_261009 的内容路由模块、对白修复及已提交的 N2 长批次保留规则。本文随本轮对白修复提交；已同步引用词保护、同行短片段路由及 build 51 的本机用户确认；源码快照以第 12 节散列为准，后续独立改动可能另行改变工作区。

本文记录实现现状，不代表所有规则合理，也不代表所有场景已经通过验收。示例和审查场景均为合成输入，不包含私有诊断中的真实对白。2026-10-11 模块提取后已更新本文：规则实现集中到 FYContentRouter，阈值、优先级和主链路闸门保持原行为。模块边界见 [内容路由模块](content-router-module.md)。随后另行修复独立姓名栏错读：新增像素角色标记及未知姓名栏的对白排除，详见第 6、8 节；这项行为变化不属于此前保持行为的模块提取。

本文主体描述“开始翻译”的实时自动链路。“翻译当前界面”是另一个单次动作：弹窗筛选后直接进行界面分组、过滤和贴译，不经过本文的自动模式两次确认或实时字段跨帧稳定。它不应与自动模式误判混为同一入口。

## 给 Claude 的审查任务

请对照当前源码审查下面的规则，重点检查对白、界面贴译、对白与选项同时出现时的边界和优先级。

用户确认的产品要求：同一画面可以同时存在对白和需要贴译的选项；这时对白进入字幕窗，选项在原位贴译。真正的纯菜单、资料页和公告页仍应使用界面贴译。

请先审查和复现，不直接修改代码。每个发现请给出：

1. 触发条件、实际结果、预期结果，以及对应源码函数和行号。
2. 最小合成 OCR 输入：每块的 text、boundingBox，必要时提供连续帧、初始模式和在途请求。
3. 失败发生在整帧分类、模式确认、对白与选项分流、文字过滤、文本稳定还是交付阶段。
4. 证据级别：可由代码直接确定、已用生产路径复现，或仍待验证。不要把可能性当成已发生的 Bug。
5. 是否有现有回归覆盖，以及应补哪条最小失败回归。测试应复用生产处理，不能另写一套判定器验证自己。
6. 修复方向及对纯菜单、短对白、背景招牌、英语和混合显示的潜在影响。

如需运行回归，请先读仓库 AGENTS.md、DEBUG_WORKFLOW.md 和 docs/inline-ocr-stability.md。不要启用真实设备、读取真实凭据或保存新的原文、画面、译文。

优先审查第 10 节。只收到本文而无法读取源码时，请明确把结论限定为规则审查。

## 1 概念和输入

### 整帧模式与呈现方式

| 概念 | 当前实现 |
| --- | --- |
| 对白模式 | ContentModeDialogue = 0 |
| 界面模式 | ContentModeUI = 1 |
| 混合模式 | 没有第三个枚举；在对白模式内分成对白字幕和选项贴译两条路径 |
| 自动或手动 | 当前正式应用固定自动判别，autoContentModeEnabled 返回 YES |
| 看到贴译面板 | 可能是整帧界面模式，也可能只是对白模式里的选项，不能只凭外观判断整帧模式 |

“整帧 UI 判定”和“贴译块的 Short 或 Long 分组”是不同概念。后者服务于字段分组、请求和排版，不决定整帧应该进入对白模式还是界面模式。

### 坐标与字符数量

- boundingBox 为归一化的 [x, y, width, height]，左下角为原点，y 越大越靠上。
- 本文用 w、h、midY、minX、maxX、minY、maxY 表示对应矩形值。模式判定前，裁剪或精读坐标已映回完整输入图像。
- w 相对图像宽，h 和 y 相对图像高；它们不是屏幕像素，也不是同一轴上的长度。
- 通常的 L 为 FYNormalizeOCRTextForComparison(text).length：删除空白和换行，保留标点，再取 NSString 的 UTF-16 长度。省略号数量会影响 L。
- 姓名和姓名注音函数另用去掉首尾空白后的字符串，内部空白没有按上述 L 统一删除。
- 模式判定没有按置信度加权，也没有使用模型理解句意。部分路径检查假名，部分只检查几何、长度和标点。

### 判定前的 OCR 处理

Vision 适配器先删除首尾空白后长度不足 2、宽小于 0.010 或高小于 0.006 的观察。这些宽高门针对该次实际 OCR 输入图像，精读裁剪时不能直接当成完整图像的阈值。

正式实时路径使用 Accurate OCR；识别语言随设置选择日语或英语。minimumTextHeight 为 clamp(48 / 当前 OCR 图像高度, 0.005, 0.10)。Fast 路径使用 32 像素目标，但不是当前正式实时策略。

双遍合并还保护首遍的完整引用：同位置明确一对一日文单行，首遍有唯一完整、非空引用词，其外围句子与精读一致；精读删除该词、留下空引号或短的不闭合引用时保留首遍观察。双方水平交集至少为较宽框的 65%，不处理多行、多个/嵌套引用或其它位置；完整引用纠错和只丢引号但保留词仍使用精读。条件及正常纠错回归见 [引用词修复](ocr-refinement-quotation.md)。该保护先于下方的字幕带与模式判定。

窗口截图和采集卡视频是干净源图；源观察只按文字与位置去重，不按译文缓存删除同文原文。可选区域精读和跨帧精读结果选择在模式判定之前执行。日语链路在合并及坐标回映后，用完整源图做独立姓名栏角色标记；Vision 局部裁剪输入不自行标记。该过程复用已有图像，不新增 OCR 请求或保存画面。

关键输入分歧：

- 整帧模式判定、对白字幕带和混合分流使用合并后的 ocrBlocks。
- 界面模式后续分组、过滤使用弹窗筛选后的 modalScopedBlocks。
- 模式判定发生在贴译分组、shouldIgnoreInlineText 过滤和 FYInlineOCRFrameStabilizer 之前。
- 因而后续会被删除的日期、符号、按钮等，仍可能先参与模式判定的块数、宽度和词命中统计。OCR 把一行拆成多块，也可能改变分类结果。

## 2 整条处理顺序

当前主链路的顺序如下：

1. 采集、OCR、区域精读合并、源观察去重，日语完整源图姓名栏标记，另外计算弹窗筛选结果。
2. 检查启动代次、运行状态、目标窗口、采集会话代次和 OCR 错误。
3. 全帧 normalized.length 小于 2 时提前返回。
4. 用全部 ocrBlocks 做整帧分类，再经过模式两次确认。
5. 如果确认切换模式，取消旧内容请求、清理旧贴译和去重状态，重置对白文本稳定计数。
6. 当前为对白模式时，待比较文本排除像素标记的未知姓名栏；当前为界面模式时，先分组、过滤，再做界面字段跨帧稳定；用稳定结果生成待比较文本。
7. 比较已显示文本、在途文本、几何和分组变化，执行去重与同文重试节流。
8. 当前为对白模式时，再做全帧文本稳定确认。
9. beginContentTranslation 创建新的内容修订，取消被替代的在途任务；实时界面仅短字段变化而长正文未变时，beginInlineContentTranslation 保留长 HTTP 批次并更换界面计划，只取消过期短批。
10. 根据已确认模式分流：界面贴译，或对白字幕加选项贴译。
11. 翻译回调再次检查内容修订、运行代次、窗口、采集会话和模式后交付。

模式判定先于“文本没变”和“正在等待译文”闸门。因此静止画面也有机会完成模式切换。与此同时，混合分流位于整帧 UI 判定之后。

## 3 单次整帧分类规则

入口：FYContentRouter contentModeForItems:fallback:，原 FYOCRManager 接口转发到该模块。

按下列顺序执行，前面的返回优先：

~~~text
如果 blocks 为空：
    返回当前模式 fallback

如果 looksLikeUIFrame(blocks)：
    返回界面模式 1

如果 subtitleBandItems(blocks) 非空：
    返回对白模式 0

如果块数 <= 2 且 UI 词命中块数 == 0：
    只要任意块满足中央假名片段条件，
    或者所有块都在右下角提示区域：
        返回当前模式 fallback

其余情况：
    返回界面模式 1
~~~

中央假名片段条件为：包含假名，midY 在 [0.10, 0.38]，minX >= 0.18，maxX <= 0.78，h >= 0.035。

右下角提示区域条件为：所有块 minX >= 0.80 且 midY <= 0.12。此处不要求文字一定是“操作説明”。

fallback 表示保留已有模式，不能理解成“判为对白”。例如在界面模式下，只看到一个中央短片段仍可继续保持界面模式。

## 4 什么会被优先判为界面

入口：FYContentRouter looksLikeUIFrame:。计数时先跳过 L = 0 的块。

| 计数 | 条件 |
| --- | --- |
| tokens | 命中 UI 词的块数；同一块命中多个词仍只计 1 |
| small | L <= 8，h < 0.036，w < 0.20，并且不是几何注音 |
| edge | minY < 0.10 或 maxY > 0.90，同时 L <= 12 |
| wide | w >= 0.32 |
| substantial | w >= 0.15；或 L >= 8、w >= 0.13、h >= 0.030 |

以下按代码顺序执行，任一返回 YES 即接管整帧：

1. tokens >= 2。
2. tokens >= 1，且 small >= 2 或 edge >= 3。
3. small >= 4，或总块数 >= 5 且 small >= 3；此分支有下面的短对白豁免。豁免后仍满足相同菜单块门槛则返回 YES。
4. edge >= 4，wide = 0，tokens >= 1。
5. substantial >= 6。
6. 以上均未返回则不是 UI。

“总块数”使用 blocks.count，不是非空文字块数。substantial 的 w >= 0.15 分支没有额外的长度和高度要求，只要求 L 非零。

第 4 条目前被第 2 条涵盖，因为 tokens >= 1 且 edge >= 4 必然先满足 tokens >= 1 且 edge >= 3；它不是一个额外可达的分类分支。

### UI 词的实际匹配方式

日文列表：

~~~text
戻る、戻、閉じる、詳細、次へ、決定、設定、メニュー、スキップ
~~~

整条相等或以该词开头即命中。“戻”因此是一个比较宽的前缀条件，不要求整块只是按钮。

英文列表：

~~~text
back, close, menu, next, ok, cancel, skip, setting, settings, web
~~~

先去空白并转小写，再查找出现位置；左右须为字符串边界或非 NSCharacterSet.letterCharacterSet 字符。不是语义判断，也不是保留空格后的分词。“wait back”先变为“waitback”，会影响英文词边界结果。

### 短行换行对白的豁免

只在第 3 条的小块菜单规则里执行；不能否决 tokens 或 substantial 的整帧 UI 判定。

取 subtitleBandItems(blocks)，须全部满足：

- band 至少 3 块，第一块为 isSpeakerLabelItem。
- 每块 midY <= 0.45，h >= 0.026，w <= 0.30。
- 相邻块左边缘差 <= max(0.025, 两块的最大 h)。
- 相邻块 midY 差 <= 两块最大 h 的 2.5 倍。
- 至少两块 L >= 3 且包含假名。
- 至少一块上述假名行以“。！!？?…・、”之一结尾。
- 至少一块上述假名行不像姓名，并且不以“。．.！!？?…‥”之一结尾，作为未完句证据。

符合时，从 small 中减去 band 里的 small 块，再检查菜单门槛。总块数仍是全部 blocks.count。

这里“、”和“・”可作为未完句，“…”则属于完句标记。左右对齐判断把归一化 h 数值用于 x 差阈值；这种跨轴比较是否适用于不同宽高比，需单独验证。

### 几何注音的排除

isFurigana:nearLargerLineInItems: 要求小块 L >= 2、w <= 0.14、h <= 0.035，假名占至少 75%。

还须找到另一个块：宽至少为小块 1.6 倍，高至少为小块 1.5 倍；小块中心高于大块中心，小块 midY 与大块 maxY 的差 <= 0.05，水平重叠至少覆盖小块宽度的 65%。

它用于 small 统计和对白正文过滤，区别于第 6 节的姓名注音判断。

## 5 如何找对白字幕带

入口：FYContentRouter subtitleBandItems:。这里没有识别真实气泡或对白框边界，只用 OCR 文字块。

### 强锚点

isFormedTextLine 条件为：

~~~text
(L >= 8 且 w >= 0.20) 或 (L >= 6 且 w >= 0.12)
~~~

isDialogueAnchor 还要求 h >= 0.026、midY <= 0.32，以及：

~~~text
w >= 0.22 或 (L >= 10 且 w >= 0.15)
~~~

当前源码在所有合格强锚点中选最宽的一条，不是选最低的一条。部分旧注释仍写“最低”，应以实现为准。

0.15 宽度条件是本轮窄对白省略号误判的局部修正：省略号不能只凭字符数把窄句送进强锚点，再被后面的实质行门否决。更窄的句子交给既有短句兜底。

### 单行短句兜底

没有强锚点时，按输入数组顺序选第一条 isSingleLineDialogue，不比较谁最宽或最低：

- L >= 4，w >= 0.05，h >= 0.026，midY <= 0.45。
- 最后一个字符为“。！!？?…・、”之一；或者满足下面的无标点短句规则。

无标点短句要求全部满足：

- 4 <= L <= 14，包含假名。
- h >= 0.043，0.08 <= w <= 0.30。
- minX >= 0.18，maxX <= 0.78，0.10 <= midY <= 0.38。

该短句标点集合没有 ASCII 句号“.”、全角句点“．”或“‥”。有标点的分支不额外要求假名。

### 相邻堆叠短句兜底

仍无锚点时，候选需 L >= 4、w >= 0.06、h >= 0.026、midY <= 0.45。

还须有另一块：L >= 2，中心 y 差 < 0.10，水平方向有正重叠。合格候选中选最宽者。

isShortDialogueAnchor 的注释说纯数字或日期不当对白，但当前函数没有实现该检查，也不检查假名或标点。日期过滤发生在后面的文字过滤层。

### 实质行否决与旧弱锚点分支

已找到锚点后，全部 blocks 中只要存在 w >= 0.20，或 L >= 8 且 w >= 0.15，即满足 hasSubstantialLine。否则非短句兜底路径返回空带；短句兜底跳过该否决。

代码还保留“已选锚点 w < 0.16 且 L < 10”的弱锚点检查。按当前强锚点门，这种已选强锚点不可达：它必须 w >= 0.22，或 L >= 10。记录这一点用于审查旧分支，不据此推断用户可见故障。

### 从锚点扩张

其余候选只需 L >= 2 且 w >= 0.04。

1. 先向下，再向上；每个方向从锚点中心开始。
2. 候选与当前前沿的 y 中心差必须方向正确且绝对值 < 0.20。
3. 候选与原始锚点水平重叠至少为较窄块宽的 50%，且重叠为正。
4. 每次取最近的合格块，移动前沿，重复扩张。
5. 垂直扩张完成后追加下面的同行短片段，再统一排序。

扩张使用相邻前沿的 y 距离，但水平对齐始终参照原锚点；没有整条字幕带的总高度上限，也不检查所有候选是否位于下半屏。

### 横向拆开的同行短片段

原垂直带非空后，检查带外块与已收录块；符合以下条件的相邻片段加入带，重复检查直到不再增加，以免观察输入顺序影响收录：

- 双方未标记 speakerLabel，lineCount <= 1，文字没有换行；宽、高均为正。
- 较小 h 至少为较大 h 的 70%，midY 差不超过较小 h 的 25%。
- 去空白后两边均非空，较短 L <= 6、较长 L >= 4，较长一边含日文假名；等长时检查函数第一个实参。
- gap = max(两块 minX) - min(两块 maxX)。gap 至少为较小 w 的 -15%，防止竞争重叠观察被当成另一词。
- gap 不超过 min(0.02, 两块中较小的 w/L × 75%)，只接收紧邻片段。

同基线、字高相近且未标记姓名栏的单行按 minX 从小到大排序；其余继续按 midY 从大到小，中心差 < 0.01 时沿用原排序位置。这条追加不要求窄片段满足 w >= 0.04 或与原锚点水平重叠，不改变界面字段分组，也不猜测已被 Vision 删除的字。完整路由必须调用 `dialogueRouteForItems`，只测试 `dialogueTextFromItems` 会漏掉带选择时丢词的边界。

## 6 姓名与姓名注音

| 判断 | 实际条件 |
| --- | --- |
| looksLikeSpeakerName | 去首尾空白后长 1 到 10；末字不是“。．.！!？?”；不含平假名 U+3040 到 U+309F；至少含一个汉字 U+4E00 到 U+9FFF 或片假名 U+30A0 到 U+30FF |
| looksLikeSpeakerFurigana | 去首尾空白后长 2 到 12；末字不是同一组句末标点；不计空格和 tab 后，假名占至少 60% |
| isSpeakerLabelItem | 已有正向像素姓名栏标记；或姓名且 w <= 0.35；或为姓名注音，位于另一姓名块上方，midY 减对方 maxY <= 0.05，重叠至少覆盖注音宽的 50% |
| looksLikeSpeakerLabelCluster | 1 到 3 块，每块均为姓名或姓名注音，至少一块为姓名，簇内最宽块 <= 0.35 |
| dialogueFrameIsSpeakerLabelOnly | 过滤后的全部行均为姓名或姓名注音，并且至少一行为姓名 |

这不是人名词典。某些纯汉字标题或片假名普通词也能通过姓名条件。

“整帧只含姓名”主要控制学习记录：对白身份为 nil，不记成对白句子；主链路没有因此统一禁止翻译，过滤后的字符串达到长度门仍可能请求翻译。

### 独立填色姓名栏的像素角色

`FYOCRManager itemsByMarkingSpeakerLabels:inImage:` 先取现有字幕带；字幕带不足两项且整帧恰有两项时，改按原阅读顺序测试这两项，避免旧锚点长度门排除很短的正文。不会用此退回改变整帧模式规则。首行作姓名栏候选，第二行作正文参照，须同时满足：

- 有源图且字幕带至少两块，候选为单行；midY 分别不超过 0.45、0.38。
- 令 H 为两行最大高度，W 为首行之后字幕带的最大宽度。候选宽度不超过 max(W × 0.6, H × 2.5)，高度为正文高度的 0.35 到 1.8 倍。
- 候选 minY 减正文 maxY 为 −0.25H 到 1.2H；候选 minX 不超过正文 minX + 0.5H。
- 在复用的至多 480 像素宽缓冲上，各矩形采样 9 × 7 个点。同色定义为 RGB 各通道差不超过 22；最大同色群占至少 55%。正文矩形另向左右扩正文高度的 15%，上下扩 10%。两行代表底色至少一个通道相差 45。
- 候选上边外一倍自身高度处与右边外 3H 处各采 5 点。全部点须在图内，至少 8 点与候选底色不同，避免把宽阔背景色直接当姓名栏。

符合后仅复制首项并附加 `speakerLabel = YES`，保留文字、坐标、置信度和来源标签。该标记不改变整帧 UI 优先级或界面贴译过滤。

`isUncertainSpeakerLabelItem` 定义为已有像素角色且不满足现有 `looksLikeSpeakerName`。这类行在对白提取和更早的对白比较中同时排除，使姓名栏错读变化不再创建正文请求或学习身份。符合现有姓名规则的行继续参与完整原文及身份；不同明确姓名的同文对白仍不同。

没有源图、底色相同、无界色块、几何不符或没有下方正文时保留原行。不会仅凭假名、英文、重复字符或短宽度排除；未知姓名栏下的真实短句也保留。该结构启发式不是人名识别模型：透明、纹理或不同排布的姓名栏可能不命中，纯汉字/片假名错读仍可能满足旧姓名规则；这些情况尚未据此宣称解决。现有历史数据不自动改写或删除。

## 7 对白与选项同时出现时怎样分流

主链路只有在已确认模式为 0 时执行以下混合分流：

1. 以全部 ocrBlocks 查找 bandItems。
2. 窗口输入可分流；采集卡输入须有可用的 inlinePlacementRect 坐标映射。
3. 调用 splitDialogueAndOptions，将对白送字幕路线，选项送原位贴译路线。

### 选择对白簇

- band 按上到下排列，相邻两块中心 y 差 <= 0.12 为同簇，> 0.12 则分簇。
- 在 midY <= 0.42 的成形行中选最宽者，它所在的簇为对白簇。
- 没有合格行时，退回 band 内含最宽文字块的簇，位置不限。
- 向前检查上方相邻数组簇，只要是姓名标签簇就并回对白；此处没有再检查实际几何间距。
- 剩余簇全部进入选项，包括对白簇下方的簇。注释说“上方其余簇”，实际循环没有限定上方。

### 从整个 OCR 输入补选项

对白簇中最宽的块作补漏锚点。对 allBlocks 中尚未归入选项、也不属于选定对白簇的块，要求：

- L >= 2，w >= 0.10。
- 不是 isSpeakerLabelItem。
- midY 高于补漏锚点。
- 与补漏锚点水平正重叠，且重叠至少为较窄块宽的 55%。

这条补漏没有最大竖直距离，不要求文字是真正选项，也不要求存在选择按钮。它依靠上述几何和姓名排除。

### 两条路径的约束

- 对白和选项可同时提交；共享本轮 contentTranslationRevision。选项操作另增加在途计数。
- 混合选项直接使用 splitDialogueAndOptions 的结果进入 translateInlineTextItems，没有先经过整帧界面分支的 FYInlineGrouper、strict = NO 过滤或 FYInlineOCRFrameStabilizer；它依赖前面的全帧对白稳定以及分流条件。这与整帧界面贴译的输入确认不同。
- 选项回调要求当前仍为对白模式，并验证修订、运行代次、窗口、采集会话和运行状态。
- 选项请求安排在“对白文字是否为空”的判断之前，因此对白为空时仍可能交付选项。
- 没有选项时会清除旧贴译面板。
- 采集卡坐标映射不可用时，band 全部进入对白候选，不单独贴选项；为空时仍会触发下面的全帧退回。
- dialogueItems 为空时，dialogueTextFromItems 使用整个 dialogueSource，也就是全部 ocrBlocks，而不是直接认定没有对白。

整帧已经被 UI 优先规则接管时，上述分流不会执行。这正是“选项加对白”需要重点审查的前提。

## 8 分类后的文字过滤

分类正确不等于所有原文都会被翻译。过滤发生在分类之后，而且两个路径规则不同。

### 共用删除规则

shouldIgnoreInlineText 会删除：

- 空 normalized。
- 没有有效日文字符且整行全为标点、符号或空白的文字。有效日文范围包括平假名、片假名、汉字和半角片假名；含英文普通文字的句子不因这个条件整行删除。
- 所有字符都属于“0123456789/.-〜~年月日(月)(火)(水)(木)(金)(土)(日) ”的字符串。这里是字符集合判断，不是日期语义识别。
- 同时贴上下边与左右边的窄短块：minY < 0.08 或 maxY > 0.94；minX < 0.12 或 maxX > 0.88；L <= 8；w < 0.10。

### 对白正文过滤

dialogueTextFromItems 先排除有正向像素角色、但不满足现有姓名规则的未知姓名栏，再排除右下“操作説明”和几何注音，最后用 strict = YES 过滤。未知姓名栏同样在更早的对白稳定、在途匹配及已显示去重比较中排除；明确姓名仍保留，普通短句无标记时不会因本规则被删除。

strict 词表：

~~~text
today, web, back, 戻る, 戻, 詳細, 閉じる, ルームへ,
更新, news, no., no, ok, yes, skip, auto, menu
~~~

转小写后整条相等或任意位置包含即命中；若同时 L <= 8、w < 0.16、h < 0.06 中任意一项成立，就删除该块。

此处与整帧 UI 词检测不同：没有英文词边界，也不限日文前缀。普通正文中包含这些子串可能被过滤，是待审查边界。

过滤后，若相邻两个保留观察满足第 5 节的同行片段条件，直接按当前字符串接为一行；其它观察继续以换行拼接。不会补写未识别的引号或修改原观察对象。随后执行 dialogueTextWithoutTrailingButton：如果整串有函数列举的日文假名，末尾为 2 到 4 个连续汉字，且汉字前为“。．.!！?？、，,…」』）)”之一，就删末尾汉字。它不检查这些汉字是否真的属于按钮词。

### 界面贴译过滤

modalScopedBlocks 先经 FYInlineGrouper 分组，再用 filteredInlineTextItems strict = NO：

- normalized 长度不足 2 删除。
- 同文且位置 overlapRatio >= 0.5 去重；不同位置的同文保留。
- h < 0.015 且 L < 5 删除。
- L <= 6 且完全没有 U+3040 到 U+30FF 假名或 U+4E00 到 U+9FFF 汉字时删除；此条件不按当前识别语言区分。
- 单独的 no. 或 no 删除，再应用共用删除规则。
- 按阅读顺序排列，按钮类移到队尾；没有按总块数截断。

这意味着界面路径的短英文、数字、日期、半角片假名要结合实际分组结果审查，不能仅凭“按钮和日期都保留”的注释判断。

## 9 模式和文本怎样经过稳定确认

### 模式确认

FYContentModeStability 维护 detectedMode、candidateMode、candidateHits：

- 本次分类与已确认模式相同：候选改为当前模式，计数清零。
- 分类不同且与上一次候选相同：计数加一；否则换候选，计数为 1。
- 候选达到 2 次：提交新模式，计数清零。

主链路中存在 inlineOverflowChoicePanel 或 inlineExpandedReadingPanel 对象时，跳过模式观察并维持已有模式。它保护的是译芽的选择列表和展开阅读卡，不是检测到游戏有选项就锁定模式；当前条件也没有额外检查面板 visible。

这里的“两次”是两次进入模式观察的结果。OCR 错误或全帧 normalized.length < 2 会提前返回，空帧只重置对白文本稳定，没有在这一分支重置模式候选；不能直接等同于相邻两个物理视频帧。

确认切换后会取消旧内容任务、清贴译、清已显示与已提交的去重文本、重置对白稳定，并清空当前原文标签。两条模式的轮询间隔分别为对白 0.5 秒、界面 1.2 秒；忙碌、采集和 OCR 时长会影响实际观察间隔。

### 对白文本稳定

模式为 0 时，在混合分流和正文过滤之前，对全帧比较文本进行稳定确认，通常要 2 次等价观察。日语先保留各行边界，调用共享比较键完成逐行归一后才连接；不能先用通用空白清理删除换行，否则后续行的行首省略号会变成句中标点。未知姓名栏仍在比较前按已有结构标记排除。

日语对白还满足“与已显示文本相似度 >= 0.85，但不属于同一句”时，需要候选达到 3 次。这用于确认真实细微修正。

日语同句判断采用 FYDialogueComparisonKey，不用高相似度直接吞掉字词变化：

- 逐行先删除空白，包括省略号字符之间的空白，再判断行首。
- 删除行首连续的装饰字符“・･…⋯‥•。．._＿”。开引号/括号“「『（(【［[〈《“‘\"”保留在键中；其后的装饰点号仅在后接日文字符时忽略，不把括号中的 .5 或非日文记号改成另一数值。支持多个开括号以及点号与开括号交错的前缀。
- 行首连续的字符“-－‐‑‒–—ー”与空白，仅在后接 U+3041 到 U+30FA 或 U+3400 到 U+9FFF 时去掉。
- 日文字符之后的连续省略号及点号串归一为“…”：包含显式“…”、“⋯”（U+22EF）、“‥”，或至少两个“・･•.．。”时成立；行尾的单个“・”、“･”、“•”保持原有归一行为。句中停顿及其它已展平的比较调用仍兼容这一规则；行首身份必须在展平前处理。
- 单独的日文句末“.”、“．”、“。”可忽略。各行直接连接成比较键，不保留换行边界；内部小数、单个姓名分隔中点、横线和非日文数学记号保持区别。比较键不改写 OCR 原文或已保存快照。
- 非空的单字日文比较键可复用同句；空键不能确认对白，也不能把纯标点当作已显示的台词。此前行首省略号被去掉后若只剩一字，原两字长度门会阻断同句匹配。

行首边界的失败回归、修正和验证见 [行首省略号记录](dialogue-leading-ellipsis.md)。

非上述日语对白路径：最大长度 <= 6 时要求等长且相似度 >= 0.84；更长时相似度 >= 0.90。

全帧观察稳定之后，学习协调器仍可用完整已确认源文替代退化 OCR 文本；该身份复用逻辑不是整帧模式判定。其完整实现应另查学习协调器。

### 界面字段稳定

FYInlineOCRFrameStabilizer 在分组与过滤之后工作：

| 情况 | 规则 |
| --- | --- |
| 首次显示 | 与前一候选文字及几何匹配数 >= 两帧最大块数的 65%，才接受 |
| 整页大改 | 新旧均至少 3 块且匹配数 < 较少块数的 40%；新页候选间匹配 >= 最大块数的 60%，候选命中 2 次后接受 |
| 同位置文字或类型修正 | 相同新文本与类型连续 3 次 |
| 新增块 | 相同文本且几何可匹配，连续 2 次 |
| 单块漏读 | 保留前 2 次漏读，第 3 次移除 |
| 空观察 | 连续 3 次清空已确认状态；未确认候选也会被空观察打断 |
| 几何变化 | delta >= 0.010 时需 2 次接近观察，候选 delta < 0.005；较小变化沿用已确认位置 |

还会恢复被临时合并观察吞掉的已确认字段边界。界面模式经过该稳定器后不再等待额外的全页文本两帧确认；不能把代码注释“界面不等稳定”理解成完全没有稳定门。

### 去重 在途匹配和同文重试

对白模式的这些全帧闸门位于对白与选项分流前。界面模式使用已确认字段拼接文本。

- 已显示同文且几何、分组未变化：跳过请求，并重置对白候选。
- 与在途内容相同：跳过请求，并重置对白候选。
- 界面在途匹配还要求整页文字完全相等，以及逐项缓存身份序列相等。
- 同一已提交文本的重试节流：对白 4.0 秒、界面 1.2 秒。条件是文本等价、几何未变化且距上次尝试不足间隔；这不是每个新句都强制等 4 秒。
- A 已显示、B 在途、又看到 A 时，当前代码只把 sameTextAsRendered 改为 NO，交给稳定门；不会在这里立刻取消 B。A 被稳定接受并进入 beginContentTranslation 后才取消 B。这是 N1 的当前行为。
- 界面稳定确认的小块变化会更换界面计划；所有长正文键及重复次数不变时，保留在途长批并按当前字段位置接回，只更新短字段。正文变化仍取消旧批次。这是 N2 的后续局部修正，详见 [在途长正文规则](inline-ocr-stability.md#在途长正文与独立短字段)；混合对白/选项仍使用原内容修订。

## 10 需要重点验证的边界

下面区分已核对的代码事实和待复现的用户影响。这些条目不是新的已确认 Bug 清单。

| 编号 | 已核对的规则事实 | Claude 应验证什么 |
| --- | --- | --- |
| R1 | UI 优先早于混合分流；4 个 small，或总块数 >= 5 且 3 个 small，可接管整帧 | 有长对白时出现 3 到 4 个真实选项，能否保持对白字幕并独立贴选项；不要只测试纯选项菜单 |
| R2 | tokens 和 substantial 是全帧统计，短对白豁免只影响 small | 对白伴随两个常驻菜单按钮，或对白加选项达到 6 条较宽行时，是否整帧转 UI |
| R3 | 模式用全部 ocrBlocks，界面分组用 modalScopedBlocks | 背景按钮或公告能否把弹窗对白判成 UI；弹窗筛选是否应影响同一次分类 |
| R4 | band 可沿邻接链扩张，没有总高度上限；非对白簇全部进入选项 | 多段对齐背景文字、下方短行是否被误收为选项，或选项连入对白 |
| R5 | band 外选项补漏只要求上方、宽度和 55% 水平重叠，无最大纵距 | 对齐的背景招牌是否被当选项；偏左或偏右真实选项是否漏掉 |
| R6 | 短行菜单豁免依赖姓名首行、假名、未完句和跨轴对齐阈值 | 无姓名、多行完整短句对白、片假名正文、注音先行、宽高比变化是否误判 |
| R7 | 字幕强锚点挑最宽，单行短句挑第一个；空对白数组会退回全帧 | 多个下方区域、OCR 顺序变化、模式确认过渡帧是否把环境文字送入字幕 |
| R8 | 分类和过滤使用不同 UI 词表及匹配方式 | 日文“戻”开头的正文、英文含 no 或 ok 的词，是否改变模式或丢整行；英文去空格后按钮是否反而漏识别 |
| R9 | 短句标点不含 ASCII 句号；界面短文本过滤未按英语设置区分 | 短英语对白、纯英语菜单，以及半角片假名能否保留正确路由和内容 |
| R10 | isShortDialogueAnchor 未实现注释所称数字日期排除，纯数字日期稍后过滤 | 是否先被判为对白，随后正文为空而保留旧字幕；需将分类和过滤放在同一复现里 |
| R11 | OCR 空帧或错误不在主链路此处重置模式候选，译芽交互面板存在时暂停观察 | 两次不同模式读数中间有空帧时是否仍切换；阅读卡长期打开期间页面真实变化如何处理 |
| R12 | 对白稳定与在途匹配用全帧文字，混合两路共享内容修订 | 无关背景或选项变化能否延迟对白、取消另一条在途结果，或产生不必要的重复请求 |
| R13 | 单字观察在 Vision 适配器已被删除；正文层又声称不因字少删除有效日文 | 单独一字台词和拆成单字的 OCR 是否根本无法到达后处理，不能只测过滤函数 |
| R14 | 句末标点后的 2 到 4 个汉字会被当尾随按钮；姓名判断无语义词典 | 正常正文末尾汉字或普通片假名是否被删除、排除成姓名；单纯姓名帧是否产生多余翻译 |
| R15 | 混合选项不经过整帧界面的字段分组、文字过滤和字段稳定器 | 多行选项被拆块、局部错读、同位置抖动时，是否产生碎片贴译或请求；不能把界面稳定器的测试算作混合选项覆盖 |

建议合成场景至少包含：

1. 同一条长对白，分别配 1、2、3、4 个短选项；再配 4 个宽选项。初始模式分别为 0 和 1，完整运行模式确认与交付。
2. 相同短对白：有姓名、无姓名、姓名注音单独成块，正文为未完句或每行完整句，省略号字符数变化。
3. 对白加常驻菜单词；背景相同词只放远处或被弹窗筛掉，观察结果差异。
4. 下方日期、下方纯汉字招牌、上方公告分别与对白对齐及不对齐。
5. “新模式候选、空帧、同候选”的序列，以及阅读卡开闭期间切页。
6. 对白请求在途时只改选项，选项请求在途时只改对白，分别检查两路取消和旧结果交付。
7. 宽高比、窗口尺寸、OCR 拆行和合行变化；保留相同文本语义，不依赖角色名白名单。
8. 日语与英语设置各自运行短对白和短菜单，检查分类后实际送翻译的文本。

上述场景目前是审查输入建议，并非本轮新增且已运行的回归。

## 11 已知修正和现有验证范围

### 已有局部修正

- 独立姓名栏错读不再进入对白正文及身份比较；普通短对白与不同明确说话人的同文保留。像素条件与局限见第 6 节。

- 强对白锚点加入 w >= 0.15 的长句宽度条件，防止窄省略号句被先选强锚点再整体否决。根因及独立验证见 [窄对白模式误判记录](short-dialogue-mode.md)。
- A 显示、B 在途、单帧 A 的 N1 已改为稳定确认后取消，相关回归见下面列表。
- 精读抖动与同位置重行属于模式判定前的 OCR 输入问题，见 [精读结果选择](ocr-refinement-stability.md)；不能把它们与模式误判或网络延迟混为一项。
- 完整引用被精读覆盖、引用词被横向拆开后落在字幕带外已有独立修补；本机 build 51 的该句获用户确认，范围见 [引用词修复与验收记录](ocr-refinement-quotation.md)。其它画面与设备不由这次确认推定。

### 可对照的测试

| 文件 | 相关覆盖 |
| --- | --- |
| [SpeakerPlateTests.m](../tests/SpeakerPlateTests.m) | 独立姓名栏正向像素证据、普通背景/无界色块反例、元数据不可变、普通短句与姓名栏下短句保留；33 条断言 |
| [speaker-plate-ocr-noise.json](../tests/fixtures/replay/speaker-plate-ocr-noise.json) | 生产主循环：在途时未知姓名栏变化只请求一次且不取消，回包后正常交付，学习原文不污染，不同明确姓名同文仍请求并创建各自身份 |
| [ContentRouterTests.m](../tests/ContentRouterTests.m) | 独立规则接口、混合输出、模式锁定、过滤原因、映射限制、同句与稳定、同行短片段及反例；当前 181 条断言 |
| [mixed-dialogue-options-auto-mode.json](../tests/fixtures/replay/mixed-dialogue-options-auto-mode.json) | 两个选项加对白、两路同时在途、对白先交付、选项后交付、静止去重 |
| [OCRPostprocessingTests.m](../tests/OCRPostprocessingTests.m) | UI 词、注音、短对白豁免、纯选项、强短锚点、字幕带扩张、姓名、对白与远处选项拆分 |
| [short-dialogue-ellipsis-auto-mode.json](../tests/fixtures/replay/short-dialogue-ellipsis-auto-mode.json) | 窄省略号对白、静止去重、纯四项菜单、返回对白的 10 步链路 |
| [short-stacked-dialogue.json](../tests/fixtures/replay/short-stacked-dialogue.json) | 堆叠短对白自动模式 |
| [lower-choice-menu-auto-mode.json](../tests/fixtures/replay/lower-choice-menu-auto-mode.json) | 下半屏纯选择菜单保持 UI |
| [stale-mode.json](../tests/fixtures/replay/stale-mode.json) | 模式变化后的过期交付保护 |
| [pending-dialogue-single-frame-recurrence.json](../tests/fixtures/replay/pending-dialogue-single-frame-recurrence.json) | N1 单帧旧对白回现，不提前取消在途新对白 |
| [cancelled-dialogue-recurrence.json](../tests/fixtures/replay/cancelled-dialogue-recurrence.json) | 已取消对白再次出现 |
| [ellipsis-jitter.json](../tests/fixtures/replay/ellipsis-jitter.json) | 省略号身份抖动 |
| [middle-line-ellipsis-history.json](../tests/fixtures/replay/middle-line-ellipsis-history.json) | 中间正文行的 U+2026 / U+22EF 与点号数量变化；在途保留、静止身份去重、真实标点变化及 A→B→A；详见 [追加记录](dialogue-history-ellipsis.md) |
| [leading-ellipsis-history.json](../tests/fixtures/replay/leading-ellipsis-history.json) | 多行行首、引号后、夹空白、漏识别及单独省略号行；在途保留、原文快照、静止去重、问号变化和 A→B→A |
| [leading-ellipsis-short-reply.json](../tests/fixtures/replay/leading-ellipsis-short-reply.json) | 去掉行首省略号后仅剩一字的回复仍正常确认、翻译及去重 |
| [english-period.json](../tests/fixtures/replay/english-period.json) 与 [english-inline-period.json](../tests/fixtures/replay/english-inline-period.json) | 英文句号保留，不等于完整英文自动模式覆盖 |
| [refinement-dialogue-oscillation.json](../tests/fixtures/replay/refinement-dialogue-oscillation.json) | 首遍稳定而精读抖动 |
| [refinement-correction-and-missing-line.json](../tests/fixtures/replay/refinement-correction-and-missing-line.json) | 精读修正及缺行 |
| [refinement-overlapping-same-line.json](../tests/fixtures/replay/refinement-overlapping-same-line.json) | 双遍同位置重行 |
| [quoted-word-refinement-loss.json](../tests/fixtures/replay/quoted-word-refinement-loss.json) | 精读删除、空引号与短的不闭合引用不得覆盖首遍完整引用词 |
| [quoted-word-refinement-correction.json](../tests/fixtures/replay/quoted-word-refinement-correction.json) | 精读中完整引用的正常纠错仍进入请求与字幕 |
| [dialogue-horizontal-quoted-fragment.json](../tests/fixtures/replay/dialogue-horizontal-quoted-fragment.json) | 精读横向拆开的窄引用词进入完整路由、请求和学习原文；静止只请求一次 |
| [inline-long-batch-unrelated-change.json](../tests/fixtures/replay/inline-long-batch-unrelated-change.json) | N2 已转普通回归：独立时钟多次变化不得取消或重发原长正文；按当前长短结果交付 |
| inline-long-batch-retained-error-retry / retention-cancellation / retention-field-removal / retention-duplicate-fields / retention-restart | 在途长批失败重试、真正正文变化、过期短结果、字段移除后的输出位置与停止重启 |

提取前，混合分流只有已找到的单元覆盖，Replay 扫描未发现同一步明确断言非空 captions 和非空 inline。本轮新增 mixed-dialogue-options-auto-mode.json，经生产自动判定和主循环运行两遍通过；同时检查两组交付、待回包索引和取消次数。这补齐了两个选项加长对白的链路证据，不代表第 10 节中多个短选项、常驻按钮、背景噪声或切换时序等边界都已验证。

此前窄对白修复已运行 OCR 后处理 228 条断言及统一核心检查：83 项记录通过，2 项为 N2 已知缺口重复复现，整体状态 baseline_passed_with_known_gaps。具体命令、报告和本机安装记录见 short-dialogue-mode.md。本轮模块提取已运行专项回归，最终统一检查结果见 [模块验证记录](content-router-module.md)。

历史回放、自动回归、本机安装、真实设备表现和用户体验验收分别记录。前一次延迟采样发生在字幕恢复之后，不能据此确定长延迟的全部根因；本文也不宣称现有局部修正解决全部卡顿。

## 12 源码入口和快照

以下用文件及函数名定位当前实现，避免后续改动使旧行号误导审查。原 FYOCRManager 及主文件 C 入口仍保留转发；审查规则实现优先读 FYContentRouter。

| 位置 | 函数或主链路 |
| --- | --- |
| [FYContentRouter.h](../objc/FYContentRouter.h) | 公开输入输出、原因枚举和模式状态 |
| [FYContentRouter.m](../objc/FYContentRouter.m) | FYContentModeStability observeMode、observeModeForItems:locked: |
| 同文件 | dialogueRouteForItems:optionsCanPasteInline:filterObserver:、dialogueTextFromItems:speakerLabelOnly:filterObserver: |
| 同文件 | FYDialogueSameBaseline、FYDialogueAdjacentRowFragments、subtitleBandItems: |
| 同文件 | isSameSubtitleText、isStableText、filterReasonForText |
| 同文件 | modeDecisionForItems:fallback:、looksLikeUIFrame:、textHitsUIToken: |
| 同文件 | 姓名/姓名注音、splitDialogueAndOptions、dialogueTextWithoutTrailingButton: |
| [FYOCRManager.m](../objc/FYOCRManager.m) | 通用文本计数、界面字段稳定、完整源图姓名栏标记、Vision 适配器 |
| 同文件 | FYOCRRefinementLosesQuotation、mergeCoarseItems:refinedItems:、FYOCRRefinementStabilizer |
| [LiveCaptionTranslator.m](../objc/LiveCaptionTranslator.m) | timerFired: 的模式、界面稳定、去重、节流、对白稳定、完整路由及两路请求 |
| 同文件 | 在途匹配、beginContentTranslation、beginInlineContentTranslation、在途长批映射 |
| 同文件 | 整帧界面分组、过滤、采集会话和实际窗口显示 |
| [FYLearningModels.m](../objc/learning/FYLearningModels.m) | FYDialogueComparisonKey，共享身份归一化 |
| [FYTranslationManager.m](../objc/FYTranslationManager.m) | 同文重试节流状态 |

整理时 SHA-256：

~~~text
objc/FYContentRouter.h
7970dd3669e76f195d49d6f92a07335cf61c3706f2a179128cea257ebcbf10c5

objc/FYContentRouter.m
af81bafdbd86f204532d623fbd6a146d72f36ff3b8f5457996943d84884caa0d

objc/FYOCRManager.m
782b5883698011909549e0b47f2de4d7da84de1e0789f4ce7348ce4596d1a368

objc/LiveCaptionTranslator.m
bd2b06303ed1bc1f8c244f3aab09eeb593f1cd2eb5e5cd3ef4ae50a178633758

objc/learning/FYLearningModels.m
a1d6b480e0e20eb7b0f40e3f2b78753044b7afd405799b74ee808ecf18630edf

objc/FYTranslationManager.m
dfc61544f46a1f0a513a550831cf70521f9698f3e5e70dbf877b9f09bafd6775

tests/ContentRouterTests.m
d7ece902d6147d4de46bcffe3626c3ed486de05e951187dfa1263c2ffdaac35c

tests/OCRPostprocessingTests.m
045fc1182b91213d1602e7c4e448989434fb895efb528b288a536efe0e2ffa5d
~~~

推荐交给 Claude 的材料为本文、FYContentRouter.h/m、FYOCRManager.h/m、LiveCaptionTranslator.m、FYLearningModels.m 和相关测试。验证请求与交付应在完整唯一维护仓库执行，避免从归档旧副本得出结论。
