# 唯一维护源码与历史归档

2026-10-16 源码提交分支为 `dev_mac_261016`，收录现有 Mac 模块拆分及后续学习存储、分析、工作流和运行编排拆分。提交前核对 831 文件冻结快照及最近统一回归的 780 项源码散列全部一致；随后仅更新本页和分支规则文档。最近统一检查为 `.build/debug/20261015T034401Z-afcae1/summary.json`：209 passed、2 known_gap_reproduced（同一旧缺口的两遍回放），独立验收结论为 `accepted_with_preexisting_gap`。这些是隔离自动回归结果；真实桌面、设备、服务、安装及公开发布分别验收，本次提交不更新已安装应用、版本或 Release。

2026-10-14 前一阶段交付范围与待验收项见 [阶段交付](mac-decoupling-stage-delivery.md)：保留1–38批，收尾词典39批。[学习存储拆分](learning-storage.md) 已完成，用户随后授权继续 [学习 AI 分析拆分](learning-analyzer.md)，保留前阶段全部改动与证据；设置、诊断的新拆分仍暂缓。以下历史“继续全目标”计划不再是当前阶段必做。

更新日期：2026-10-13。

## 2026-10-13 深度拆分（源码继续，未安装/发布）

前六批未提交修改已整体保存。新开工基线为 168 passed + 2 known_gap_reproduced，报告 `.build/debug/20261013T040210Z-7c6425/summary.json`；381 个源码/脚本/测试/规则/文档快照与完整 tracked/untracked 登记在 `.build/mac-decoupling/`，不含凭据或真实日志。

当前子批拆出独立预览调度与尺寸处理，七项预览状态统一到 scheduler；最小依赖和生产归属/Trace 专项在 O0/O2 均通过，两种隔离边界破坏均正确失败，恢复通过。相关 UI 只编译；完整收尾报告及后续未完成范围见 [Mac 深度拆分](mac-decoupling.md) 和本机 `PROGRESS.md`。本轮不使用旧桌面授权，不把源码测试视作实机验收。

子批 2 继续收敛内容 revision/操作计数/源文与观察/几何身份，并分开实时与暂停单次界面的交付校验。Foundation-only 52 项、宿主归属 62 项及 Trace 在 O0/O2 均通过；四种隔离变异均正确失败，恢复原实现通过。三处旧交付函数正文原样迁移，独立消费者也链接相同生产实现。拆前报告 `.build/debug/20261013T043110Z-fca63f/summary.json`；完整收尾见本机 `.build/mac-decoupling/batch2-evidence.json`，其它领域仍未完成。

子批 3 将请求准备/任务登记/回包与缓存/长短批次规划分别收敛到独立协调器。新增 Foundation-only 45 项、宿主归属 73 项及 Trace 在 O0/O2 均通过；三种边界变异失败并恢复通过，原 cache/batch 函数与 task owner 正文一致。拆前 `.build/debug/20261013T052116Z-381abe/summary.json` 为 170 passed + 2 known_gap_reproduced，完整收尾记录在 `.build/mac-decoupling/batch3-evidence.json`；后续 OCR 调度等范围仍未完成。

子批 4 独立 OCR 调度与周期身份：Foundation-only 90 项、宿主归属 87 项和生产 Trace 在 O0/O2 通过，四种隔离边界破坏均被检测。六项运行状态和帧消费只保留唯一 owner；实时/手动 busy 释放、原生 timer 和迟到回调寿命保持，OCR 算法正文一致。四项相关 UI 只编译；拆前报告 `.build/debug/20261013T062054Z-c46443/summary.json`，完整收尾见 `.build/mac-decoupling/batch4-evidence.json`。识别工作阶段、目标/映射及其它领域仍未完成。首轮完整 Debug 的离线启动超时及采样保留；harness 增加字节完全相同的私有输入快照后 10 项真实 OCR/启动/正反检查通过，再跑完整收尾，不改生产 OCR 或系统权限。

子批 5 独立 OCR 观察/文字与读序、纯精读资格/选择/合并去重和上下文唯一 owner。Foundation/CoreGraphics 最小依赖 61 项、真实宿主 91 项与 Trace 在 O0/O2 通过；原 Module 在 O2 通过，三种隔离边界破坏被检测并恢复通过，16 处算法正文一致（仅兼容接收者调整）。四项 UI 只编译；拆前 `.build/debug/20261013T071501Z-57defa/summary.json` 为 172 passed + 2 known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch5-evidence.json`。识别 worker 与引擎/裁剪适配及后续完整范围仍未完成。

子批 6 提取后台识别 worker、不可变 OCR 参数/结果、拥有型图像 lease、原生动作 lease，以及真实 Vision 引擎和 scope/裁剪/放大/回映。worker/几何 55 项、独立真实 Vision 11 项、真实宿主 95 项和生产 Trace 在 O0/O2 通过，原 Module 在 O2 通过；三种受控变异失败、恢复通过，原 copy/remap 与抽出诊断后的 Vision 正文一致。四项 UI 只编译；拆前 `.build/debug/20261013T075917Z-cf44e6/summary.json` 为 173 passed + 2 known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch6-evidence.json`。剩余稳定/路由、目标/映射及后续完整范围仍未完成。

子批 7 独立对白/字段稳定和模式状态/不可变决定。34 项新最小检查加原 39 项字段检查在 O0/O2 通过，真实宿主 97 项与 Trace 在 O0/O2 通过，Module O2 通过；18 处算法正文一致。原字段观察复制函数和姓名栏共用单一模型实现。反向验证补充空帧断言后 3 种变异均失败并恢复通过；共享依赖编译失败与首次空帧变异未捕获的结果保留，没有弱化断言或改产品算法。四项 UI 仅编译；拆前 `.build/debug/20261013T084851Z-89276c/summary.json` 为 174 passed + 2 known_gap_reproduced，完整收尾在 `.build/mac-decoupling/batch7-evidence.json`。分类/路由、像素、目标/映射及后续范围仍未完成。

子批 8 独立无状态过滤/分类/对白策略、模态/姓名栏像素与文本后处理；router 继承兼容并保留单一模式 owner，manager 保留原公有适配。23 项最小检查、98 项真实宿主和 Trace 在 O0/O2 通过，Module O2 通过；54 处算法正文保持，3 处仅接收者迁移，像素阈值相同。4 种隔离变异被检测并恢复通过，4 项 UI 只编译。拆前 `.build/debug/20261013T094050Z-913b57/summary.json` 为 175 passed + 2 known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch8-evidence.json`；目标/映射和其余范围继续，未安装或发布。

子批 9 独立目标/几何七项状态与纯目标解析，映射计算、原 cache/schedule 状态和坐标转换分别编译；native 显示器/候选动作与窗口 UI 保留原适配。新 44 项与原几何 96 项在 Foundation/CG 的 O0/O2 通过，真实宿主 107 项与 Trace 的 O0/O2、原 Module O2 通过。40 处算法及6处状态段比对保持，原几何断言完整保留；4 种边界破坏被抓住并恢复通过。4 UI 只编译；拆前 `.build/debug/20261013T101341Z-fd6596/summary.json` 为 176 passed + 2 known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch9-evidence.json`。采集/映射运行适配和后续全部范围继续，未安装或发布。

子批 10 独立原 native 会话 controller、Foundation/CG 单帧槽与模型，input 继承原 API，具体 self/锁/delegate/弱观察/强队列捕获及原状态唯一归属保持。20 纯帧/模型+47实际会话算法检查在 O0/O2 通过，真实宿主109与Trace的O0/O2、Module O2 通过；63处正文保持，仅4个native构造入口迁移。4种隔离边界破坏被抓住，4UI只编译。拆前 `.build/debug/20261013T104051Z-cac02a/summary.json` 为177passed+2known_gap_reproduced，完整收尾在 `.build/mac-decoupling/batch10-evidence.json`。独立的原启动顺序探针在拆前/后O0/O2均退出2：队列被阻塞且设备立即返回时，旧teardown清掉pending，连接停在Starting；原行为未改，不能算通过，真实设备是否触发待验收。映射运行及后续全部范围继续，未安装或发布。

子批 11 独立 Foundation/CG 映射自动定位/存储/复核协调器，唯一拥有原三个 lazy cache/date owner；runtime 属性仅兼容，单次 native lease 保留具体宿主覆写和强在途寿命，typed 诊断保持原阶段/格式。44 最小依赖、122 宿主与 Trace 在 O0/O2 通过，Module O2 通过；7 处编排正文按明确接口迁移，129 个其它方法和 6 个诊断格式相同。4 种隔离变异失败/恢复通过，4 UI 仅编译；草稿 input-size fixture 与误用 Trace 入口的原失败保留，未改产品算法。拆前 `.build/debug/20261013T112000Z-6c662b/summary.json` 为178passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch11-evidence.json`。排版、页面、存储、设置/诊断继续，原会话启动条件失败证据保持，未安装或发布。

子批 12 独立 Foundation/CG 布局模型/结果索引、分组、跨帧身份与文字/几何辅助，保留原mutable模型/外层copy/索引重建/variant字段与三位小数合同，legacy头兼容导出；原引擎/绘制不变。43最小依赖、125宿主与Trace的O0/O2、Module O2通过；32原函数/方法及44native引擎方法正文相同，绘制整文件相同。4变异失败并恢复，4UI仅编译；首次fixture返回租约未排空的原失败留档，只修正测试pool寿命。拆前 `.build/debug/20261013T114644Z-bfccd0/summary.json` 为179passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch12-evidence.json`。真实测量/计算/绘制与后续全部范围继续，未安装或发布。

子批13独立真实原生文字测量与fontProvider/本轮heightCache唯一owner，保留原native getter次数、cache key/别名/异常与重入恢复。25实际AppKit测量+13共同lifecycle直接编译拆前/后O0/O2通过，130宿主与Trace的O0/O2、Module O2通过；3原测量方法、4engine primitive方法迁移，37其它方法一致，布局/渲染共用6bounds/7metrics。4变异失败并恢复25+13，4UI只编译；草稿fixture泛型编译失败与纠正保留。拆前 `.build/debug/20261013T121005Z-7377ef/summary.json` 为180passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch13-evidence.json`。计算/绘制及后续全部范围继续，未安装或发布。

子批14把候选/过滤/碰撞避让/评分/变体及轮次独立到Foundation/CG计算器，原config/revision/诊断单owner，native Engine继承并仅保存measurer。原具体self/子类helper、指定class工厂/标题和唯一默认设置保持；31纯几何、6原生receiver与13lifecycle共同fixture直接编译拆前/后O0/O2通过，真实native测量没有替换为假字宽。拆前 `.build/debug/20261013T124645Z-8581b7/summary.json` 为181passed+2known_gap_reproduced；134宿主与Trace在O0/O2、Module O2通过，4变异正确失败并恢复31+6；27原计算正文及8native正文一致，13处明确native表达式迁移，默认设置唯一，4UI仅编译。完整收尾及白名单散列见 `.build/mac-decoupling/batch14-evidence.json`。后续绘制/浮层、页面、存储、设置诊断继续，未安装/发布。

子批15把原渲染尺寸与按压决策独立为Foundation/CG组件，native Renderer独立小头不依赖Engine/grouping/model/root。原5尺寸、5实际绘制函数、13其它native方法相同；四项按压状态唯一owner，原native事件/getter/actions顺序与callback寿命保持。12纯尺寸同fixture拆前/后O0/O2、25实际按压与8不创建UI的native依赖/归属检查通过；10项实际UI事件新fixture拆前/后仅编译，未执行。拆前 `.build/debug/20261013T152326Z-8fe423/summary.json` 为182passed+2known_gap_reproduced；136宿主/Trace在O0/O2、Module O2通过，4受控变异被检测并恢复；原4UI套件和新UI事件夹具仅编译。完整收尾见 `.build/mac-decoupling/batch15-evidence.json`，面板/页面/存储/设置诊断继续，未安装/发布。

子批16（2026-10-14）抽出Foundation/CG显示协调器，原16项panel/cache/result/身份字段唯一，native继承保留具体self/weak host与原窗口动作；完整缓存/布局/复用/commit算法、3文本函数/原panel struct独立，122其它native方法和实际calculator/measurer/renderer未改。33纯算法+37真实native计算，以及同fixture13原/新真实hostO0/O2通过，合成panel边界且不创建UI对象；typed frame保留原locals强别名/原copy语义。拆前 `.build/debug/20261013T154647Z-1ad499/summary.json` 为183passed+2known_gap_reproduced；140宿主/Trace O0/O2、Module O2通过，4变异被抓住/恢复33；首几何key变异未抓住的fixture尺寸混杂已留档并独立重跑，生产未改，6UI只编译。完整收尾与失败/最终fixture散列见 `.build/mac-decoupling/batch16-evidence.json`，拖选/展开及全部页面/存储/设置诊断继续，未安装/发布。

子批17（2026-10-14）将原manual两字典/key/3x3邻桶/clamp/age独立为Foundation/CG组件，将weak拖动panel/strong timer/Option bool与wire/apply/start/stop独立为NativeDrag适配；native兼容无重复状态，原weak回调/原0.1s host factory/getter/alias/早期reset顺序保持。26 pure manual+21 native事实与18原/新真实host fixture O0/O2通过，无UI对象，127其它native方法及layout/measurement/renderer未改；显示测试只用实际manual新动作保持旧断言。拆前 `.build/debug/20261013T163743Z-0c968d/summary.json` 为184passed+2known_gap_reproduced；接入后原显示与145宿主/Trace在O0/O2、Module O2通过；4变异检测并恢复26+21，6UI只编译。完整收尾见 `.build/mac-decoupling/batch17-evidence.json`，后续选择/展开与所有页面/存储/设置诊断继续，未安装/发布。

子批18（2026-10-14）独立pure快照模型/identity/snapshot/selection与NativeCard绑定，无第二current owner；Study仍current/return唯一，copy与后续sentence/version写入、weak source/card与strong原payload/snapshot保持。24pure+19NativeBinder事实、19原/新真实host同fixtureO0/O2通过，无UI对象，148其它native方法与Study/layout/measurer/renderer未改。fixture不可变输入异常及lease声明实际strong的AST根因/止损审计与尝试留档，未改生产ARC。拆前 `.build/debug/20261013T170855Z-527502/summary.json` 为185passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch18-evidence.json`，后续展开/页面/存储/设置诊断继续，未安装/发布。

子批19（2026-10-14）独立展开阅读六个native算法和原四项唯一状态，保留真实度量、12/8pt几何、滚动恢复、missing>=2、weak collapse/Esc、原monitor/close顺序。66最小native事实+15原/新实际host同fixtureO0/O2通过，无UI对象；152其它native方法与其它业务组件未改。首Footer事实漏isHidden的错误与纠正留档，生产未因此修改。拆前 `.build/debug/20261013T174002Z-37f7dd/summary.json` 为186passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch19-evidence.json`，后续overflow/页面/存储/设置诊断继续，未安装/发布。

子批20（2026-10-14）独立overflow Foundation/CG原policy6与Native资源3及原chooser/entry/geometry；保留冻结/两帧count/1.5s expiry、strong别名/close期间entry租约、Host targets/weak callbacks和原样式。原FlippedDocumentView独立而class/正文保持。34pure+25Native事实与20原/新真实host同fixtureO0/O2通过，161其它native方法/其余业务未改。首peer漏captionPanel的相同原/新异常留档，仅补测试事实。拆前 `.build/debug/20261013T180124Z-1a7d6d/summary.json` 为187passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch20-evidence.json`；真实UI仅编译，后续全部页面/存储/设置诊断继续，未安装/发布。

子批21（2026-10-14）独立20原native render/body/placement/appearance算法为无state CardRenderer，保持原实际measure/primitives/Source/Host/scroll/颜色，185其它native方法与其它组件正文不变。16最小Native与20原/新同fixtureO0/O2通过，无UI对象。nil-height误硬编码22及诊断越界/修改入口错误/止损审计留档，原实际native30与拆前一致，生产未改。拆前 `.build/debug/20261013T183432Z-caa1a9/summary.json` 为188passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch21-evidence.json`；实际UI仅编译，后续主窗口/实时/选词与其它页面/存储/设置诊断继续，未安装/发布。

子批22（2026-10-14）独立可见句Display4与Word3及12Foundation学习操作，Main动态兼容/原native输入输出；保持token/bookmark强source和AI/follow弱source、真实gate/同词不同range/busy与Host顺序。37纯业务与22原/新实际Main同fixtureO0/O2通过，86其它Main方法/bridge/coordinator/tokenizer/store未改。首最小链接/Area getter/RW extension错误与纠正留档，不改算法或产品断言。拆前 `.build/debug/20261013T190004Z-eb5a9f/summary.json` 为189passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch22-evidence.json`；真实UI只编译，后续实时页/native构造/导航/其它页面/数据库/设置诊断继续，未安装/发布。

子批23（2026-10-14）拆出无状态实时阅读刷新/等级协调与原生文字样式、实际栏宽测高、对白/固定状态渲染，保留原Display4/Word3/服务与native资源owner。18纯编排、18真实native与17实际Main原/新同fixtureO0/O2通过；124其它Main方法/桥接/学习/贴译未改。拆前 `.build/debug/20261013T192509Z-ae2826/summary.json` 为190passed+2known_gap_reproduced；完整收尾见 `.build/mac-decoupling/batch23-evidence.json`，真实UI仅编译，未安装/发布。后续native实时页/列表/导航布局与其它页面/存储/设置诊断继续。

子批24（2026-10-14）独立实时页列表signature/snapshots两copy与筛选/刷新/选择、stateless native card/row构造，原Main资源与学习/阅读owner不复制。26pure+24native+25实际Main原/新同fixtureO0/O2通过，145其它Main方法/bridge/learning/inline未改。首canonical链接遗漏和新文字动作/native setter碰撞已纠正并留档，不弱化断言。拆前 `.build/debug/20261013T200253Z-08b0a7/summary.json` 为191passed+2known_gap_reproduced；完整收尾见 `.build/mac-decoupling/batch24-evidence.json`，真正UI仅编译，后续native实时页/布局与其它页面/存储/设置诊断继续，未安装/发布。

子批25（2026-10-14）将完整原生实时页与weak选词callback/通知接线收敛到独立零state builder，原Main视图/Word3/Display4/List2/阅读与服务owner保持。20最小native与19实际Main/原body摘录同fixtureO0/O2通过，159其它Main/native primitives/Theme/其它业务未改。完整native图只编译原/新专用UI及原六UI；不能把摘录接线当完整页面验收。拆前 `.build/debug/20261013T203004Z-8bb4d5/summary.json` 为192passed+2known_gap_reproduced；完整收尾见 `.build/mac-decoupling/batch25-evidence.json`，后续Main布局和所有其它页面/存储/设置诊断继续，未安装/发布。

子批26（2026-10-14）隔离Main公有头的整套支持依赖，并独立同名FrameDriven native class/原3strong资源/原三几何表达式；163个Main方法、其它support/业务保持。10原/新native几何与18实际Main同fixtureO0/O2通过，header clang依赖证明确认隔离；完整窗口/UI只编译。首getter误预期和fact priority float ABI诊断/修正留档，只纠正fixture不改算法。拆前 `.build/debug/20261013T210043Z-ac4119/summary.json` 为193passed+2known_gap_reproduced，完整收尾见 `.build/mac-decoupling/batch26-evidence.json`；Main已收敛nav/layout/compatibility，后续其余页面/存储/设置诊断，未安装/发布。

子批27（2026-10-14）独立Foundation语法七方法/七state与只读配置container，原strong task-source/captured item/state/existing、main/quick独立analyzer/cache/cancel和全部回包门保持；nativeconfig getter/文字/颜色/scroll/render仍原动作。51pure+44原/新同fixtureO0/O2通过，118其它native与canonical业务不变；首harness路径错和首成功fixture升级证据留档。拆前 `.build/debug/20261013T212100Z-5d7559/summary.json` 为194passed+2known_gap_reproduced，收尾见 `.build/mac-decoupling/batch27-evidence.json`；UI/实际服务只另列验收，未安装/发布，后续native语法及其它所有域。

子批28（2026-10-14）独立原生scroll四算法为无状态renderer，原视图/Core七字段/两ActionState拥有者不变；143其它native方法精确。38最小与37实际原/新controller同fixtureO0/O2、Runtime182/Trace O0/O2、Module O2通过；clang依赖清单证明语法公有头不带大Support等域。五变异失败、恢复通过，四UI仅编译。首fixture/protocol与negative PCH路径错误及修正留档，不改原算法/断言。拆前复用紧邻子批27完整Debug195+2（595散列相同），完整收尾见`.build/mac-decoupling/batch28-evidence.json`；未安装/发布，其余Grammar和所有其它域继续。

子批29（2026-10-14）独立原生detail/三highlight/局部selection/main-quick actioncontrols六算法，保留原views/Core7/两ActionState/index唯一owner，141其它native正文精确。39独立与37原/新controller同fixtureO0/O2、Runtime182/Trace O2与Module O2通过，O0由本批最终完整Debug核验；真实富文本/UTF16/属性/字体/颜色和原动态覆写保持。8变异失败，恢复通过；四UI只编译。拆前复用子批28完整Debug196+2（601散列精确），收尾见`.build/mac-decoupling/batch29-evidence.json`；未安装/发布，其余Grammar与所有其它域继续。

子批30（2026-10-14）独立busy/results/clear/tab/followup五原Native算法，142其它native正文保持；96独立与93实际原/新同fixtureO0/O2通过。Core7/两ActionState/views/index/tab仍原owner，主clear取消/两次nil/代次与Tab重入、局部result/工厂输入和scroll顺序保持。八变异失败、恢复通过，四UI只编译；首95/92夹具未检出读取时点变异，保留证据后新增输入身份断言，不改原算法或旧断言。拆前子批29完整Debug197+2与607散列一致，收尾见`.build/mac-decoupling/batch30-evidence.json`；未安装/发布，其余Grammar和所有其它域继续。

子批31（2026-10-14）独立完整Grammar card/info/structure三Native构造算法，144其它原方法精确；Builder无字段、原43视图角色/数组copy/scroll/tab/weak Host target仍原owner。65独立冷/guard、旧64/新65实际controller O0/O2通过（新增API单次target读取为新版本额外检查）。六变异失败且恢复65通过；完整图旧/新两opt及canonical五UI只编译，不据入口验证宣称整图运行。新UI登记统一清单。首uiAccent声明缺失与UI隔离header双路径编译错误留档，仅修新接口/私有helper。拆前完整Debug198+2/613散列一致，收尾见`.build/mac-decoupling/batch31-evidence.json`；未安装/发布，其余语法bookmark与所有其它域继续。

子批32（2026-10-14）两类grammar bookmark异步业务进Foundation Core类方法，Core原七字段/原实现与146其它Native方法保持；index同步原位置、BOOL/text适配、原强source/item/existing租约与stale行为保持。60独立+61实际原/新O0/O2通过，七变异失败且恢复60通过，业务头实际依赖无AppKit/Root/private。五UI仅编译。拆前子批31完整Debug199+2/620散列一致，完整收尾见`.build/mac-decoupling/batch32-evidence.json`；未安装/发布，后续其它页面/存储/设置诊断全目标继续。

## 唯一维护入口

本仓库是译芽唯一维护源码。维护者本机工作区中的路径为 `.build/yiya-translator-publish-ocj99vs_/fuyi-0.1.0`；目录名保留历史名称，实际版本读取 `VERSION`，归档时为 0.2.0。其他机器直接使用其正常克隆的本仓库路径，不需要建立上述本机目录。

开发、自动检查、构建、安装、提交、推送和发布准备均在本仓库进行。源码和运行文档不再向旧副本同步；构建流程见 [源码构建](源码构建.md)。推送源码与创建 Release 是独立步骤，按 [发布流程](发布流程.md) 执行。

维护者工作区根目录已改为导航和内部资料入口，原根目录的 Git 仓库及可构建源码已经移走。需要执行 Git 命令时，先进入本仓库，核对 `git rev-parse --show-toplevel` 指向这里。

## 当前交付与验收状态（2026-10-11，0.2.2 已发布）

| 事实面 | 状态与依据 |
| --- | --- |
| 代码与远端 | `verified-current`：Mac dev 截至 `66b19fb` 已合入 main；发布标签 v0.2.2 与源码附件对应 `aca2d91`，版本 0.2.2 / build 74。原未提交的 31 项已进入 `95269c1`，后续五个 UI 测试合同对齐与发布记录已提交；发布提交的 main / 标签两次 CI 均成功。Mac dev 随后快进同步发布与交付记录。 |
| 发布产物 | `verified-current`：0.2.2 build 74 双架构安装包、更新包、418 文件源码包、资料附件及 17 → 74 差分共 10 个附件已公开。严格签名、资源、dSYM UUID、独立源码构建、差分还原及远端散列核对通过；详见[发布检查记录](发布检查结果.md)。 |
| 本机正式 App | 最近只读核对为 0.2.1 build 67，本轮未替换；其安装记录继续保留原范围，不能用于验收新发布包。 |
| 公开交付 | `verified-current`：[v0.2.2](https://github.com/onecoffeecup/yiya-translator/releases/tag/v0.2.2) 为正式 Release / Latest；安装、源码、资料从公开链接重新下载散列一致。线上 Sparkle 签名清单实际验证为 build `[74, 17]`，Pages 已部署，既有版本保留。 |
| 自动与桌面检查 | `verified-current`：最终优化核心 166 条通过、一个粘连按钮缺口复现两遍；52 个桌面套件全部尝试，49 个通过、3 个失败。失败为粘连按钮、两条长卡旧预期及已选中徽标；不记为全部产品或桌面验收通过。 |
| 文档、规则与工作区 | 当前 README、版本、使用说明和更新／发布说明已同步 0.2.2；侧栏、原生缩放、中文优先和跨版本 Key 约定保持。旧副本、历史分支、私有日志、签名符号与备份保留；Agent 记忆不在本轮范围。 |
| 真实体验 | `pending`：游戏设备、真实服务、Intel 实机、另一台 Mac 和长时间运行未由自动回归代替。此前用户确认的行为及 build 67 待抽查范围作为历史记录保留。 |

## 2026-10-12：第六批内部结构整理（未提交工作树）

用户授权继续拆分；沿用此前五批的未提交改动，仍只修改 Mac `dev0.2.1_261009` 的现役源码，没有安装、提交、推送或更新公开附件。

- `objc/app/FYAppRuntimeBridge.m`、`FYAppOverlayBridge.m`、`FYAppPresentationBridge.m`、`FYAppSettingsBridge.m` 四个明确类别按职责接入 1,120 个既有兼容访问方法；状态仍由前几批组件唯一拥有。主类用 `@dynamic` 声明 356 个委托属性，避免跨编译单元后编译器自动合成重复 ivar／访问器；12 个拥有者工厂和配置构造仍留在主类。私有声明头把存储声明与跨文件动作声明分开。
- `objc/app/FYAppSupport.m` 集中原有共享辅助、诊断白名单／私有写入、框选与校准视图、块快照及预览缩放实现；既有声明头不变，仅补齐两处原静态辅助的内部连接声明。主宿主从 3,880 行降至 1,620 行，保留生命周期、设置适配、公共工厂和跨域可见性编排。
- `objc/inline/FYInlineGrouping.m` 拥有分组及稳定块匹配；`FYInlineOverlayViews.m` 拥有短贴片／长阅读视图和原安装函数；`FYInlineLayoutUtilities.m` 实现共用数值与规范化辅助，私有声明在 `FYInlineLayoutInternal.h`。原 `FYInlineLayout.m` 从 2,262 行降至 1,435 行，继续拥有数据模型和候选／排版引擎。公共 `FYInlineLayout.h`、字号、避让、身份、交互和已知失败预期保持。
- 生产及隔离测试统一源码清单；新增 `FY_LAYOUT_CORE_SOURCES` 给文字策略、字体及字号稳定等独立排版消费者使用，完整清单另加可选布局诊断实现。没有复制一套工具函数或算法供测试使用。

1,307 个宿主／兼容／排版方法正文与拆前逐项一致；辅助段只改变导入与私有函数连接。`RuntimeOwnershipTests` 已执行 36 项检查通过，追加一项读取运行时属性元数据、核对全部动态兼容属性没有重复宿主存储；此前冷／弱归属、独立忙碌槽、内容租约、停止和回调生命周期断言保持。

基线复用第五批同源码的 14 组 UI 与核心报告（全部 412 个散列和本批前快照一致），另执行页面归属、字幕选择／显隐、贴译折叠／布局／长正文／学习、批量样式、布局诊断与框选 10 组 UI；小画面两条旧预期按 `-O0`／`-O2` 另记。拆后对照同组执行，编译检查与运行结果分别保留。核心命令为 `python3 scripts/debug.py check --timeout 300`；专项包含 `bash scripts/run-module-tests.sh`、`bash scripts/run-runtime-ownership-tests.sh`、已授权的 `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh <suite>`、双架构 `bash scripts/build-app.sh`、二进制检查与 `git diff --check`。完整命令、源码快照、方法／Replay 对照及实际结果见忽略的 `.build/refactor-batch6/evidence.json`。

保持原粘连按钮缺口与小画面旧预期，不记为全部产品要求通过。测试使用合成输入和隔离临时数据，没有真实 Key／学习库、API 或采集设备。本轮没有替换正式应用；真实游戏、设备、服务、Intel 实机与长期运行仍需独立验收。后续安装后的最短抽查：窗口缩放及侧栏／切页、字幕选择和收起、长卡滚动／折叠／学习返回、区域框选，以及两种输入停止重启后的预览和译文交付。

## 2026-10-12：第五批采集与翻译运行态拆分（未提交工作树）

用户授权继续拆分；保留此前第一、二、四、三批的未提交改动。本轮仍在 Mac `dev0.2.1_261009` 的现役源码推进，没有安装、提交、推送或更新公开附件。

| 运行组件 | 职责与状态 |
| --- | --- |
| `objc/runtime/FYTranslationRuntimeController` | 开始／停止、实时 OCR 轮询与手动界面快照、分组／稳定、内容代次、对白缓存与长短翻译批次、请求及交付；76 个方法、30 个存储字段、10 个既有派生访问入口。 |
| `objc/runtime/FYCaptureRuntimeController` | 输入设备与会话、截图／OCR 服务边界、串行采集／预览队列、独立预览、窗口选择／恢复、目标几何、采集映射、区域框选和校准；104 个方法、44 个存储字段、3 个既有派生访问入口。 |

合计迁移 180 个方法、74 个实际存储字段及 13 个派生入口。主宿主文件从 6,394 行降至 3,880 行；原 `FYImmersiveUI.inc` 的最后一个采集方法迁入采集组件后移除。主窗口在区域框选前的显隐快照继续由原主窗口组件拥有，避免重复状态；服务测试任务仍由设置组件独立拥有。

每个迁移方法以原始宿主作为明确协议上下文：所有原有动作／测试覆写继续通过宿主，异步块原来强持有或弱观察宿主的生命周期保持，后台工作不因拆分改成只持有子组件。控制器拥有存储字段，宿主用门面访问唯一状态；控制器不导入 AppDelegate 私有状态，不用动态全量转发。源码清单统一链接同一生产实现；纯辅助函数／映射版本常量保留唯一实现。180 个迁移方法的正文对照只包含接收者／协议类型的机械转换和两处字典参数泛型补齐，未调整判别门、节流、取消、字段排列或交付算法。

拆分前同组 14 个 UI 套件全部通过：输入设备／映射、目标跟随／窗口选择、界面翻译、对白稳定／完整／省略号、历史去重／保留、设置／服务测试、浮层归属及主窗口缩放。新增无界面的 `RuntimeOwnershipTests` 已执行 35 项检查通过，并纳入 `debug.py check`：冷初始化不创建窗口／设备／任务、弱组件宿主、唯一存储、分离的采集／预览队列、网络取消不释放 OCR／预览槽、旧完成不释放新内容、跨组件预览作废、服务测试独立、停止清理，以及待答块强持有与设备观察弱持有宿主。

本轮验证命令：`bash scripts/run-runtime-ownership-tests.sh`；`bash scripts/run-translation-trace-tests.sh`；`python3 scripts/debug.py check --timeout 300`；已授权桌面时段的 `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh <suite>`；宿主接入方 `clang -fsyntax-only`；`bash scripts/build-app.sh` 和 `python3 tests/ReleaseBinaryTests.py`；`git diff --check`。完整命令、退出码、前后源码快照、方法／Replay 检查点对照、实际 UI 和双架构构建结果集中于忽略的 `.build/refactor-batch5/evidence.json`，编译与执行分别记录。

原粘连按钮缺口保持，不改变现有小画面长卡滚动显示或其旧预期。测试只有合成输入、临时数据和 mock HTTP／采集，没有读取真实 Key／学习库、调用真实服务或连接设备。本轮没有替换正式应用；真实设备、实际服务、Intel 实机及长期运行仍需单独验收。后续安装后的最短复查：两种输入开始／暂停／重启、在途快切 A→B→A、设备重连、目标窗口重建／投影／移动、静止字段及长短批次更新时的字幕与预览。

## 2026-10-12：第三批字幕与贴译展示拆分（未提交工作树）

用户授权继续拆分；在第一、二、四批未提交改动上推进第三批。此次仍只修改 Mac 分支 `dev0.2.1_261009` 的现役源码，没有安装、提交、推送或更新公开附件。

- `objc/presentation/FYSubtitlePresenter` 拥有字幕窗、快捷小条、样式预览、显隐意愿和原生文字显示状态：20 个方法、13 个字段。
- `objc/presentation/FYInlineOverlayController` 拥有贴译面板复用、排版缓存、块身份映射、手动拖动偏移、折叠入口／冻结选择列表和展开阅读生命周期：81 个方法、36 个字段。原排版引擎算法、字号稳定及卡内滚动规则保持。
- 宿主保留原动作入口，属性访问器连接唯一状态持有者。两个组件通过明确宿主协议读取设置、几何和学习快照，不导入应用私有状态，不做动态全量转发。原生按钮／定时器及已有测试覆写继续经过宿主；诊断仍使用同一隐私开关、限额和私有日志。
- `FYImmersiveUI.inc` 只保留引用当前画面的采集识别方法；字幕停靠入口迁入字幕组件。宿主从第四批的 7,828 行降至 6,394 行，兼容访问器仍保留后续迁移用途。当时采集、OCR 稳定、网络请求与跨帧主循环留待第五批。

拆分前快照和源码散列、前后同组 UI 结果、方法正文及生产 Replay 对照集中于本机忽略目录 `.build/refactor-batch3/`，完整结果由 `evidence.json` 关联。新增并执行 `OverlayOwnershipTests` 23 项检查通过：冷访问无浮窗／监听、弱宿主、宿主无重复状态 ivar、协议连接、原生字幕／选择按钮经过宿主覆写、学习快照共享、稳定块展开及清场资源释放。迁移的 101 个方法正文只改变明确动作目标与宿主覆写连接；8 个核心编排方法与第四批后基线正文相同。

贴译学习验收首次在「返回同块后待答消息」断言失败：仅等固定 50 ms 时看到 `sending=1`、消息 1 条。聊天控制器、会话及回复处理源码与基线一致；在拆前／拆后实现上注入同一 120 ms 合成回复，旧断言均失败，继续等待均收到 2 条消息，确认等待条件不足。`InlineLearningAcceptanceTests` 改用已有 5 秒超时的 `Pump` 等待发送结束，保留原消息断言并保留延迟回复夹具；不修改生产会话行为。原失败、两份延迟对照和修正后的执行结果均保留于本批证据目录。

验证命令与范围：`FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh <suite>` 对照字幕外观／选择／显隐、批量样式、字号、贴译布局／折叠／长正文／学习、模态面板、目标跟随、字段保留、布局诊断、主窗口缩放及既有页面归属；新增浮层归属测试加入桌面清单。`InlineTranslationTests` 的粘连按钮失败与 `InlineAdaptiveAcceptanceTests` 的两条小画面旧预期失败按拆前基线单列，后者同时检查 `-O0`／`-O2`，不为使其通过而改变现有显示。核心执行 `python3 scripts/debug.py check --timeout 300`；依赖宿主的测试／工具使用 `clang -fsyntax-only`；`bash scripts/build-app.sh` 验证双架构构建和 dSYM UUID，`python3 tests/ReleaseBinaryTests.py` 验证二进制检查器；编译与实际 UI 执行分别记录。

测试隔离使用合成输入和临时数据，没有读取真实 Key／学习库、调用真实 API、连接采集设备或发送邮件。本轮没有安装，真实游戏、服务、Intel 实机和长期运行仍需独立验收。后续安装后的最短复查：静止界面核对面板不重建、短贴片 Option 拖动、长正文卡内滚动、折叠入口及选择列表中选择对应条目、查句／AI 后回到同一块、切页清场和目标窗口移动后的落位。

## 2026-10-12：第四批页面与学习交互拆分（未提交工作树）

用户授权继续第四批；保留前两批的未提交工作。此次只修改 Mac 分支 `dev0.2.1_261009` 的现役源码，没有安装、提交、推送或更新公开附件。

新增 `objc/presentation/` 五个独立编译的控制器：

| 控制器 | 拥有的职责与状态 |
| --- | --- |
| `FYMainWindowController` | 主窗口、页面导航、侧栏布局、实时阅读、选词表单和实时页译文列表；62 个字段。 |
| `FYCollectionController` | 最近台词、词语／语法／句子收藏、词卡、例句和遮义复习；36 个字段。 |
| `FYGrammarPresentationController` | 主语法卡、分析与选择、高亮、结构图、按需解释和两个阅读表面的语法动作缓存；53 个字段。 |
| `FYStudyPresentationController` | 共享聊天会话、查句／AI 浮窗、独立分析、原句快照、返回关系和滚动位置；43 个字段。 |
| `FYReferencePresentationController` | 本机词典展示、结果代次、主阅读／查句悬停和词义缓存；16 个字段。 |

共迁移 159 个方法及 210 个控件／临时状态字段。宿主用兼容访问器读取唯一持有者，保留原生按钮、委托和测试覆写入口；控制器只依赖共享声明和各自的明确宿主协议，不导入 AppDelegate 私有状态，不用动态全量转发。基本视图工厂及跨页面连接仍由宿主提供；当时采集、OCR、翻译主循环和贴译面板尚未拆分。

原 `FYReferenceUI.inc`、`FYSourceHoverUI.inc`、`FYGrammarActionsUI.inc` 已迁入编译模块并移除；`FYWorkspaceUI.inc` 保留通用视图工厂，`FYImmersiveUI.inc` 当时保留当前画面识别和字幕停靠入口。共用视图／模型／测试辅助声明位于 `app/FYAppSupport.h`。主宿主文件从前两批的 8,769 行降至 7,828 行；保留的兼容动作与属性访问器有后续迁移用途，不能把文件行数当作职责已经全部拆完。

本轮验证及范围：

- 基线源文件与前两批已通过核心检查的全部 393 个散列一致。拆分前后分别执行同一 16 组原生 UI：收藏布局、页面导航、学习交互、窗口缩放、阅读布局、沉浸学习、查句分析、语法动作、聊天展示、最新原句、两组悬停、工作区压力／追问、词典及贴译学习入口，全部退出 0。
- 新增 `PresentationOwnershipTests`，在已授权桌面时段执行 21 项检查并通过：冷访问不创建窗口、宿主弱引用、宿主没有重复 UI 状态 ivar、协议连接、原生按钮仍经过宿主覆写点、共用学习身份、切页和侧栏开关保留同一会话／聊天视图／草稿。此套件登记在 `run-checks.sh` 的桌面清单中；默认核心不冒充执行了 UI。
- `python3 scripts/debug.py check --timeout 300` 最终退出 0，报告 `.build/debug/20261012T073639Z-43a4e5/summary.json`：169 条执行记录，167 通过、2 条同一粘连按钮缺口复现，`source_unchanged=true`，全部 402 个源码／脚本／规则／夹具散列与最终文件一致。
- 77 个生产 Replay 场景双遍共 154 次，所有检查点与第四批前完全一致。159 个迁移方法的正文只调整原生动作目标及明确的宿主覆写连接，没有其它正文变化；开始、停止、timer、贴译批次和主要贴译布局方法保持原样。
- 59 个依赖宿主声明的测试和工具通过 `clang -fsyntax-only`，这部分只编译。`bash scripts/build-app.sh` 完成 arm64／x86_64 的 `-O2 -g` 构建及双架构 dSYM UUID 核对；随后 `python3 tests/ReleaseBinaryTests.py` 三项执行通过；`git diff --check` 通过。

完整命令、退出码、前后快照、控件归属分区、正文／Replay 对照及构建 UUID 位于本机忽略目录 `.build/refactor-batch4/`，由 `evidence.json` 关联。整体仍为 `baseline_passed_with_known_gaps`；本轮没有修复粘连按钮缺口，不记为全部产品要求通过。没有读取真实 Key／学习库、发送真实邮件、请求真实 API 或连接设备。

新构建尚未安装；真实游戏、服务、Intel 实机与长期运行仍需独立验收。未来安装后的定向复查：切页及手动开关 AI 侧栏保留尺寸与草稿；收藏页切换词／语法／句子及遮义复习；查句进入 AI 后返回同一句，选择和滚动位置保持；关闭后旧解析不能覆盖新句；原生原文选择／复制和悬停保持。

## 2026-10-12：第一、二批模块拆分（未提交工作树）

用户授权先做入口／测试接入和设置／诊断两批，再检查功能影响。本轮只修改 Mac 分支 `dev0.2.1_261009` 的现役工作树；没有提交、推送、安装或更新 Release／Sparkle，已安装与公开版本仍按上表记录。

- `objc/LiveCaptionTranslator.m` 保留 13 行启动入口；宿主移至 `objc/app/FYAppDelegate.m`。公开生命周期声明和私有状态／测试覆写声明分开；测试和离线工具不再导入 `.m` 或重命名应用 main，而是链接同一份生产实现。
- `FYAppDiagnostics` 和 `FYGrammarActionState` 的类实现改为独立 `.m`；隔离 Key 状态移为测试共享变量，避免分开编译后出现重复类或各文件拥有不同的合成凭据。
- `objc/settings/FYSettingsStore` 拥有普通设置不可变快照、凭据保存状态和 0.45 秒延迟保存；`FYServiceTestController` 拥有服务测试任务、代次和取消状态；`objc/diagnostics/FYDiagnosticsController` 拥有元数据报告、保存对话框和邮件草稿状态。宿主保留控件适配及原有测试入口；Key 继续使用既有私有文件读写、设置键与跨版本规则。
- 当前宿主仍有 8,769 行，尚未实施后续页面、贴译展示、输入与主循环拆分。生产 timer、开始／停止、贴译翻译批次、主要贴译排版方法，以及其余六个 UI 片段与拆分前正文相同。

实际验证：

| 检查 | 结果与范围 |
| --- | --- |
| 拆分前 `python3 scripts/debug.py check --timeout 300` | 168 条：166 通过、2 条已知缺口复现；报告 `.build/debug/20261012T053226Z-aa51df/summary.json`。 |
| 最终同一核心命令 | 169 条：167 通过、2 条同一已知缺口复现；`source_unchanged=true`，全部 393 个源码／脚本／规则／夹具散列与最终文件一致；报告 `.build/debug/20261012T055120Z-e06d1f/summary.json`。 |
| 前后 Replay 对照 | 77 个场景、双遍共 154 次回放，全部检查点与拆分前一致，包括原有粘连按钮缺口；没有新增失败。 |
| `HostExtractionTests` | 28 项通过：嵌套快照独立、合成 Key 共享／写失败／清空、延迟保存合并和释放、服务测试取消／迟到结果、诊断隐私；纳入统一核心入口。 |
| 已安排桌面时段的隔离 UI | `FY_TEST_ALLOW_UI=1 bash scripts/run-learning-app-tests.sh <suite>`：`SettingsInteractionTests`、`LocalCredentialSettingsTests`、`TranslationServiceViewTests`、`DiagnosticsInteractionTests`、`MainWindowResizeTests` 均执行退出 0。诊断检查使用假邮件服务，并经实际 sharing delegate 回调验证取消和重试。 |
| 接入方编译检查 | 58 个依赖宿主的测试和工具通过 `clang -fsyntax-only`；这部分仅编译，不记为其余桌面套件执行通过。 |
| `bash scripts/build-app.sh` | arm64／x86_64 的 `-O2 -g` 构建通过，二进制与 dSYM 双架构 UUID 一致。后续 `python3 tests/ReleaseBinaryTests.py` 三项通过；`git diff --check` 通过。 |

证据集中于本机忽略目录 `.build/refactor-batches12/`，`evidence.json` 记录完整命令、退出码、报告、源码核对、Replay 对照及构建 UUID。核心整体仍为 `baseline_passed_with_known_gaps`：同一个 `known-gaps/fused-trailing-button.json` 两遍复现，不写成全部产品要求通过。测试没有读取真实 Key／学习库、请求真实服务、连接设备或发送真实邮件。

尚未验证新构建的真实设备、服务调用、Intel 实机和长期运行；本轮没有安装，不能把源码测试当作正式应用已更新。未来安装后的最短复查：改模型名按 Enter 并重开确认保存；检查服务测试、字幕与实时翻译互不覆盖；运行诊断并核对报告不含内容和凭据；缩放／切页保持窗口尺寸与侧栏手动状态。

子批33（2026-10-14）独立聊天上下文/发送四算法与两标量唯一owner，既有Session/视图/返回/网络取消scope不重建，111其它Native方法原文不变。73最小与74实际原/新同fixture O0/O2通过、八变异失败并恢复，原配置读写交错/最新身份/迟到隔离/两草稿和strong上下文/weak网络寿命保持；RuntimeOwnership追加唯一state检查。首合成fixture误预期与纠正保留。拆前紧邻子批32完整Debug200+2、624散列精确匹配，完整收尾见`.build/mac-decoupling/batch33-evidence.json`及[聊天上下文](study-chat-context.md)。UI仅编译，源码未安装/发布；后续全目标继续。

子批34（2026-10-14）独立快捷查句分析/取消与句子、语法收藏查询/操作六方法、九项原临时状态；121其它Native方法原文保持，原聊天/导航/存储/取消scope不改。81最小与82实际原/新同fixture O0/O2通过、九变异失败/恢复，RuntimeOwnership增加唯一owner检查；首最小链接canonical依赖遗漏与修正留档。拆前子批33最终Debug201+2、631散列精确一致，完整收尾见`.build/mac-decoupling/batch34-evidence.json`及[查句业务](quick-sentence-workflow.md)。UI仅编译，未安装/发布；后续全目标继续。

子批35（2026-10-14）独立七学习/查句/贴译进入与返回算法、12项导航状态，current/return snapshot现物理归属NavigationCore，Study/Root/Inline仍兼容同一对象；142其它Native方法原文保持，原Quick/Context/Session不改。59最小与60实际原/新同fixtureO0O2、11变异失败/恢复通过，Runtime加强唯一归属/跨Inline身份；首protocol重复声明和getter临时autorelease检查修正留档。拆前子批34完整Debug202+2、638散列一致，完整收尾见`.build/mac-decoupling/batch35-evidence.json`与[学习导航](study-navigation.md)。UI仅编译，未安装/发布，其余全目标继续。

子批36（2026-10-14）将学习原生14方法分为Chat/Quick/Scroll三个无state组件，视图/offset/业务Core/Session仍原owner；隔离Study public header整套支持依赖，167其它Native方法保持。69独立与68实际原/新同fixtureO0O2、10变异失败/恢复，真实weak/font/text/scroll检查通过；完整Quick/UI仅编译原/新专用fixture两opt与9套canonical，未运行桌面。首fixture block声明错误/详情升级留档。拆前子批35完整Debug203+2、645散列一致，收尾见`.build/mac-decoupling/batch36-evidence.json`与[原生渲染](study-native-rendering.md)。未安装/发布，其余全目标继续。

## 发布前开发记录（历史）

查句悬停在用户确认预览后共用实时页的生产组件。新增 `QuickSentenceHoverTests` 与五组相关原生 UI 回归通过，覆盖词义／语法优先级、选择复制、自然高度、外层滚动、关闭及迟到回调隔离；安装前后 65 个生产源码散列一致，正式应用打开后为暂停空状态。命令、build 61 安装 UUID、Key 元数据及最短手动验收见[阅读布局](live-reading-layout.md)。真实游戏、设备与物理鼠标体验仍待确认。

### 本次服务修复与后续审查的证据范围

服务提交 `8dbf649` 的独立检查为 `.build/debug/20261011T141237Z-98526c/summary.json`：166 条全通过、378 个散列核对一致；三组设置 UI、14 项翻译解码与学习拒答回归通过，前后日志及提交文件散列在 `.build/refusal-enter-fix/evidence.json`。这些数字描述当时服务修复工作树，不能替代后续代码验证。

后续本机审查提交截至 `54cfec0` 的 `.build/debug/20261011T141946Z-f2f2a5/summary.json` 包含 168 条记录，检查期间源码未变，380 个散列在本轮文档修改前与工作树一致。`known-gaps/fused-trailing-button.json` 的两遍回放仍分别得到对白与按钮粘连的源文，登记为一个已知缺口，详见[OCR 稳定合同](inline-ocr-stability.md)。本次只做文档和安装身份核对；文档变动不作为一次新的核心、桌面或设备验收。

六条审查的独立判断、根因、五个提交、失败与通过命令、工作树范围及未验证边界已汇总到[审查记录](review-speaker-routing-20261011.md)。本机仍为 build 67，当前无需重复验收尚未安装的审查修补；后续安装新版本时定向检查贴底／贴左姓名栏和正文首行自报姓名，并核对实时原文、译文与最近台词。该组源码回归不替代 build 67 混合画面／纯菜单的原待验收项。

### build 59 文档收尾的历史范围

本次文档收尾只检查内容、链接、源码证据与安装身份，不重跑桌面 / 核心套件，也不递增 build 或重新安装。111 项核心检查与相关 UI 的通过记录对应功能提交 `4956d21` 的代码；文档变动及随后出现的未提交源码不能被写成一次新的运行验收。阅读文档中的 23 pt 中文字号描述的是已提交 / 已安装 build 59；未提交的 19 pt 调整须在其验证与交付完成后另行同步。

## 旧副本已归档

2026-10-08，原工作区根目录旧副本归档至工作区内 `.archive/legacy-root-20261008/repository/`。

归档保留：

- 旧 `.git` 历史及当时的工作树；归档基线提交为 `fb6834a40c2927372095f5120a4c88f821337415`。
- 50 个已跟踪文件的未提交修改，以及 86 个未跟踪条目（包括文件夹，不能视作 86 项功能）。
- 旧源码、资源、脚本、测试、工具、版本文件和构建产物。
- 当时的 README、AGENTS 和完整 `docs/` 快照，以及旧仓库涉及的本机素材。

未提交内容主要包含 OCR/贴译稳定修复、窗口/OCR/坐标/翻译/诊断/排版模块拆分、界面和学习交互、API Key 文件存储、构建测试与文档。新增生产模块在现役仓库中都有对应文件，其中部分已演进；归档只保证旧文件被保存，不宣称所有差异均已逐项功能验收。

归档外层 `README.md` 记录用途，`legacy-files.json` 记录归档前文件 SHA-256、大小和权限，`verification.json` 记录归档核对结果。旧仓库的未提交状态保持原样，没有为了归档创建提交或推送旧代码。

归档停止维护，不作为安装、发布或“稳定分支”的来源。原旧副本与现役仓库是两个历史仓库副本；归档并不创建 Git 开发分支。后续实验和功能开发应在现役仓库的分支中进行。

## 文档与本机资料归属

| 内容 | 维护位置 |
| --- | --- |
| 源码、运行资源、脚本、测试和版本 | 本仓库 |
| 使用、构建、OCR/API Key 合同及发布说明 | 本仓库 `README.md` 和 `docs/` |
| 本机 Agent 规则、内部视觉规范、设计与交接资料 | 工作区根目录 `AGENTS.md`、`docs/design/`、`design/`、`handoff/` 等原位置 |
| 旧副本历史状态 | `.archive/legacy-root-20261008/`；保留快照，不继续同步 |

根目录与本仓库重复的运行文档只保留跳转，现役说明以本仓库为准。历史报告中的“根目录测试”“旧副本同步”等计数保留其当时含义，不构成继续维护旧副本的要求。内部规范提及的代码与运行资源路径相对于本仓库；历史原型路径由其说明明确标注。

本机归档不进入 GitHub 或发布附件。真实 API Key 和学习记录位于独立的用户应用数据目录，本次没有读取、复制或修改它们。内部资料的保留不表示已获公开分发授权。

根目录 `.build/` 除构建证据外还包含本仓库，不能整目录清空。本次保留了历史构建证据、已安装应用和用户资料；没有发布新 Release。

## 查找与恢复

在维护者工作区根目录可只读检查旧状态：

```bash
git -C .archive/legacy-root-20261008/repository status --short
git -C .archive/legacy-root-20261008/repository log --oneline -5
```

需要恢复某项改动时，在现役仓库创建功能分支，先比较归档文件与当前实现，再按具体改动集成并运行相应检查。不要整文件覆盖现役代码，也不要让旧源码恢复为第二份日常维护入口。

需要完整复原旧现场时，保留归档原件，复制其 `repository/` 到另一个临时目录检查；归档中的未提交文件已直接保存在工作树，不需要依靠旧提交才能取回。

子批37（2026-10-14）拆出收藏复习七个业务方法与三字段唯一状态，保留原生 Collection 兼容入口、Store连接、strong数组别名及原强弱回调。专项独立60/原新控制器61项 O0/O2、八项变异/恢复已验证；统一完整结果见 `.build/mac-decoupling/batch37-evidence.json`，相关 UI 仅编译，真实复习操作另验。拆前657散列与子批36完整Debug204+2一致，已保存私有快照；详见[收藏复习](collection-review.md)。未安装/提交/推送/发布，全目标继续。

子批38（2026-10-14）收拢收藏查询、词卡操作与原生展示，Query4/Card3字段唯一，Review3沿用；21原完整方法与Native行/原位片段、词卡例句回调按职责维护，62其它Native正文保持，public header不再导入大Support。94业务/64原生原新同fixtureO0O2与11变异/恢复通过，首fixture问题及定位留档；完整结果见 `.build/mac-decoupling/batch38-evidence.json` 与[收藏工作流](collection-workflow.md)。拆前664hash与37完整205+2一致，相关UI只编译；未安装/提交/推送/发布，Reference/数据库/设置诊断全目标继续。
