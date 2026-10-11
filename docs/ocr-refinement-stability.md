# 双遍 OCR 的结果选择

2026-10-11。现场同场景的 35 帧文字诊断中，首遍读到的正文持续一致，第二遍放大识别却交替返回几个不同句尾。生产链路回放确认：最终 OCR 文字不断变化，使新对白无法连续通过稳定门，字幕保留上一句；换用首遍稳定输入后可以正常提交。这发生在请求之前，N1 的在途取消修复不能解决该边界。

## 局部修复

实时 OCR 使用 `FYApplyOCRRefinementWithStabilizer`，沿用已有精读触发、识别与合并路径。新 `FYOCRRefinementStabilizer` 按同一位置的一对一行替换比较首遍、精读的连续帧：首遍连续两帧一致且精读发生变化时，保留当前帧首遍观察；精读连续三帧一致后恢复替换。精读尚未抖动时，持续一致的修正立即按原规则交给下游。

只使用当前图像中的原观察，不拼接或重放旧画面的文字。不修改原观察的文本、框和元数据，不按角色、句尾符号或具体对白建白名单。精读在其它位置新找回的行继续保留；无法明确一对一匹配的拆行、多行合并和局部裁图继续走原合并合同。

选择结果仍须通过原有对白/界面稳定、身份、缓存和交付检查。恢复精读不会绕过这些门；曾抖动的精读修正会增加确认等待。持续稳定不等于识别正确，这条规则只处理两遍结果的稳定性冲突。

状态按采集代次、窗口、输入类型与 epoch、语言、OCR 范围、图像尺寸隔离。主线程创建上下文后由单次 OCR 工作序列使用；旧任务持有旧对象，停止重启后的任务使用新对象。空观察、失败或没有精读时打断连续证据，避免间断命中积累。

显式单次界面识别及离线单图工具保持原无跨帧路径。新增诊断 `ocr/refinement_selection` 只记录 `stable_pass1` 原因及回退块数，遵循现有文字诊断开关，不新增自动保存画面或文字。

## 回归与证据

公开夹具均为合成对白。`refinement-dialogue-oscillation.json` 的初始最小版本修复前第 4 步失败：总请求预期 2、实际 1，新增对白未提交；报告 `.build/debug/20261011T030431Z-455e05`。修复后连续两遍通过，随后扩展覆盖持续交替、静止去重、切窗与重启。`refinement-correction-and-missing-line.json` 检查精读纠正首遍错字、补回首遍漏行，并核对实际提交的完整原文。

模块检查另覆盖精读三帧恢复、两帧短暂重复、当前原文元数据保留、真实文字变化、不同位置同文、空帧/错误复位、不稳定首遍、拆行和多行合并。Replay 新字段 `refined_blocks` 只替换第二遍识别边界，区域门、生产合并与选择、下游稳定、请求和字幕交付仍执行生产实现；不另写选择模拟算法。

| 实际命令 | 结果 |
| --- | --- |
| `python3 scripts/debug.py replay tests/fixtures/replay/refinement-dialogue-oscillation.json --repeat 2` | 退出 0，两遍通过；扩展后报告 `.build/debug/20261011T030709Z-30ca60`。最终夹具也在下面的核心检查中两遍通过。 |
| `python3 scripts/debug.py replay tests/fixtures/replay/refinement-correction-and-missing-line.json --repeat 2` | 初版退出 0，两遍通过；随后增加精确请求原文断言，最终夹具在核心检查中两遍通过。 |
| `python3 scripts/debug.py replay .build/private-diagnostics/dialogue-20261011/paired-refinement.json --repeat 2` | 退出 0，35 帧历史观察的双遍输入两遍通过；请求原文保留首遍正文，字幕交付更新且不重复请求。报告 `.build/debug/20261011T031126Z-70d84a`。真实文字夹具仅存本机私有目录，不提交或打包。 |
| `python3 tests/DebugInfrastructureTests.py` | 11 项通过；精读观察执行同样的输入坐标与字段验证。最终版本在核心检查重跑通过。 |
| `bash scripts/run-module-tests.sh` | 局部检查退出 0；最终版本在核心检查重跑，OCR 后处理 207 项、字段稳定 39 项等全部通过。 |
| `python3 scripts/debug.py check --timeout 300` | 退出 0，11 项核心套件及 Replay 构建/失败报告检查通过；Replay 66 passed、2 known_gap_reproduced，`source_unchanged=true`。报告 `.build/debug/20261011T031157Z-3d0c75/summary.json`。 |
| `ARCHS='arm64 x86_64' bash scripts/build-app.sh` | 退出 0，双架构编译与 dSYM UUID 核对通过；只有既有 unused-function 警告。 |
| `git diff --check` | 通过。 |

核心检查包含真实 Vision 的合成图片 OCR、离线工具 Accurate/Fast 与并行正反断言、测试隔离、诊断、模块、外观、数据库韧性、布局、翻译生产链路、语法及全部 Replay；没有连接真实设备或请求真实 API。原 N1、新 N1、快切及迟到 OCR 归属回归均两遍通过。上一轮 N1 记录中的离线工具失败仍保留为历史证据；本轮该套件 6 项通过，未修改离线工具，也不据此倒推之前失败的根因。

`baseline_passed_with_known_gaps` 表示普通基线通过、登记缺口仍可复现。N2“长批在途时无关时钟变化取消重发”的两个失败记录仍保留，调度未改，不属于本次精读修复。

构建 UUID：arm64 `5BBBC482-B2D8-3EEB-872E-3CDDD4BC9C3C`，x86_64 `44CBBBB8-1EE1-3546-BA49-6D6835106B43`，对应 dSYM 一致。最终源码散列及证据索引保存在忽略的 `.build/ocr-refinement-review-20261011/verification.json`。

上述自动验证阶段没有安装、启动应用、发布或推送。历史观察回放使用合成 HTTP 回复，证明观察选择到请求/字幕交付的链路，不证明新版本面板实际可见或本次重新识别游戏画面的准确率。现场只需让原失败对白停留数秒，确认字幕更新并静止保持；再切到下一句确认能正常切换。小字菜单的真实识别质量及长时间运行另行验收，不由这些合成/历史回放推定。

## 同日本机安装

用户随后授权“安装一下我测试”。执行 `CODESIGN_IDENTITY=- ARCHS='arm64 x86_64' bash scripts/install-app.sh`，退出 0；脚本备份旧包、重建/组装并签名安装到 `~/Applications/译芽.app`。随后用 `open ~/Applications/译芽.app` 打开，进程路径核对为该安装包。当前为 **0.2.1 build 44**，应用版本未改变。

安装脚本重建得到新的 UUID：arm64 `2830E4D9-5EA0-3D52-89C0-C05357AE816E`，x86_64 `4530A138-E1C1-3551-9644-DA0D5DA23FEF`。本次构建、安装包与 dSYM 三者一致；安装后的 `codesign --verify --deep --strict` 通过。重新核对完整核心检查的 274 个源码/夹具文件散列，全部未变，安装使用已通过回归的同一份源码；上文初次构建 UUID 保留为历史证据，不能当作当前运行包的 UUID。

凭据只核对元数据：安装及重新打开后，Key 文件大小、mtime、inode、0600 权限及目录 0700 权限均未变，没有读取或输出 Key 内容。安装索引见本机私有的 `.build/ocr-refinement-review-20261011/installation.json`；用户现场字幕时机与显示验收仍待反馈，未发布或推送。

## 当前对白重复行：同日追加

用户随后反馈另一句延迟，并提供主窗口当前对白中同一行出现两份的截图。经明确授权的 20 秒文字诊断共 39 个完整 OCR 帧：首遍文字一致，双遍合并有 7 帧重复中间行、32 帧正常。用户确认采样时悬浮字幕已经更新；该样本未覆盖最初等待及请求，不能认定重复行解释了现场全部延迟。采样中的 OCR 工作平均约 0.200 秒、最长 0.297 秒，也不能拿它解释最初长等待。

重复行的边界已确认：首遍框高约 0.079854、精读框高约 0.045454，比例约 0.569，低于原跨遍替换的 0.6 门限；通用重叠去重又要求覆盖外框 85%，较小精读框达不到。因此同图同位置同文的两份观察进入稳定、学习和请求路径。此前的文字抖动选择器只处理一对一替换，两遍文字相同但框高跨门限不属于其回退条件。

`FYOCRManager mergeCoarseItems:refinedItems:` 追加同文单行几何判定：双方均不是多行，去空白后文字完全相同；水平交集至少为较宽框的 85%、交集覆盖较小框至少 85%，垂直中心偏差不超过较高框的 25%。满足时保留当前精读对象及原文/框/元数据，不重放旧帧，不修改学习身份、缓存或稳定门。原不同文字的替换阈值、原始观察通用去重及拆行/多行规则保持原合同；实际不同位置的同文行仍保留。

新增合成 Replay `refinement-overlapping-same-line.json` 的最小版本在修复前第二帧失败：期望当前字幕已交付，实际字幕列表为空，报告 `.build/debug/20261011T033844Z-c1698e`。只改变精读框高度即可使重复行出现/消失，阻断原两帧稳定门。这证明该机制可延迟请求，但不替代现场最初停滞的缺失证据。

修复后扩展为连续框高交替、完整请求原文与静止去重，并用第二段包含两个不同位置的真实同文行，断言请求保留两行。`python3 scripts/debug.py replay tests/fixtures/replay/refinement-overlapping-same-line.json --repeat 2` 退出 0，两遍通过，报告 `.build/debug/20261011T034111Z-42e7ee`。无 AppDelegate/窗口/Vision 请求的后处理检查修复前同位置重行断言失败，修复后 215 项通过；补充覆盖框高变化、空白等价、不同文字、部分水平覆盖、邻行、多行及元数据保留。

真实文字与配对观察只保留在本机 `.build/private-diagnostics/dialogue-stall-20261011/`，公开夹具不包含游戏对白。本追加的完整核心检查、历史配对回放、构建安装与用户体验证据在执行后另行记录；上述局部通过尚不能冒充已安装版本的现场验收，也不会自动清除已经存入最近台词的旧记录。

本次 39 帧配对历史观察已经生产精读合并、稳定、身份、请求及交付回放，连续两遍通过，合并重复帧由样本的 7 帧降为 0，实际提交原文为 4 个不同的行。命令 `python3 scripts/debug.py replay .build/private-diagnostics/dialogue-stall-20261011/paired-refinement.json --repeat 2`，报告 `.build/debug/20261011T034334Z-42a0f4`。初次回放的合成旧句控制帧漏填全图坐标的第二遍输入，导致自动模式切换，失败记录 `.build/debug/20261011T034226Z-5e00ed` 保留；补齐控制输入后通过，没有为此修改生产代码。当前合并后观察恢复精读输出时，只去掉样本中原样保留的首遍框，不能恢复未记录的其它候选或全部 OCR 元数据。

上一处句尾抖动的 35 帧配对历史观察亦连续两遍通过，命令 `python3 scripts/debug.py replay .build/private-diagnostics/dialogue-20261011/paired-refinement.json --repeat 2`，报告 `.build/debug/20261011T034436Z-f547c6`。两轮历史回放均使用 mock HTTP，不接设备，不重新识别游戏画面，不证明真实翻译服务的响应速度或实际面板显示。

本追加的 `python3 scripts/debug.py check --timeout 300` 退出 0，报告 `.build/debug/20261011T034514Z-2425e2/summary.json`：11 项核心套件及 Replay 构建/失败报告检查通过，普通 Replay 68 个通过记录、N2 已登记缺口 2 个 `known_gap_reproduced`，总结果为 `baseline_passed_with_known_gaps`；`source_unchanged=true`。模块后处理 215 项、采集卡离线合成 OCR、布局、生产翻译链路及真实 Vision 合成媒体均通过。N1、此前精读抖动和真实重复行保护包含在本轮核心检查中，没有屏蔽已知缺口。

沿用用户此前本机安装授权，执行 `CODESIGN_IDENTITY=- ARCHS='arm64 x86_64' bash scripts/install-app.sh` 退出 0，双架构构建只有既有 unused-function 警告；退出旧译芽、备份并重装后打开新包。当前仍为 **0.2.1 build 44**，但二进制已更换：arm64 `7D7DD4BE-01BA-3052-9FD3-BF7445ADA558`，x86_64 `F4E1B9AB-142A-396A-8C64-DA2CE2A3F475`。构建、安装和 dSYM 三者 UUID 一致，深层严格签名检查通过；核对 276 项源码/夹具散列均与本轮核心检查一致。

安装及打开后，凭据文件大小、mtime、inode 和 0600/目录 0700 权限均未变，只检查元数据，不输出 Key。证据索引在本机 `.build/ocr-duplicate-review-20261011/verification.json` 与 `installation.json`；无提交、推送或公开发布。打开状态为暂停，未代用户启动真实翻译或重新录制诊断。最短验收：点「开始翻译」，让当前对白保持不动，确认当前对白中的中间行只显示一次；再切一句确认正常跟随。已存入最近台词的旧记录不自动改写；首次长等待的完整原因仍待覆盖开始阶段的现场证据。
