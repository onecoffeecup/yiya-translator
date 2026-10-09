# 译芽 iPadOS Lite 阶段验证记录

日期：2026-10-08。工程审查完成；独立视频 PoC 源码与检查入口已准备；iPadOS 设备构建、安装与硬件采集均未完成，第三至五阶段未开始。

## 本轮改动

新增 `ipados/CapturePoC` 独立 iPadOS 17+ Xcode 工程，使用 SwiftUI、AVFoundation 和 CVPixelBuffer。代码准备了外接视频发现、启动时权限请求、串行会话配置/启停、等比非镜像预览、像素格式/帧率协商、最新单帧槽、状态/帧统计、插拔与中断处理、前后台停止/恢复和有界错误重试。当前只保留内存元数据，无 API、OCR、音频或素材落盘。

新增生产帧槽/统计/格式选择的辅助执行测试及 `scripts/check-ipados-poc.py`，报告区分语法、结构、主机执行、iPad 编译和硬件验收。更新 README 增加评估入口。Mac 的 `objc/`、既有 tests 与构建脚本没有修改，也没有运行安装/发布命令。

## Mac 本轮真实回归

命令：`python3 scripts/debug.py check`，退出码 **0**。

实际报告：`.build/debug/20261008T053202Z-c6bbcc/summary.json` 与 `summary.txt`。总计 54 条检查记录，50 条 `passed`，4 条 `known_gap_reproduced`（两个登记缺口，各运行两遍）；总结果为 **baseline_passed_with_known_gaps**。报告记录 `source_unchanged=true`。隔离、诊断、模块、翻译 trace、对白、Replay 构建、失败报告、21 个普通 Replay 场景各两遍执行通过，包括合成 Vision 图像/视频、缓存、输入中断、模式/窗口过期和乱序。

仍存在的产品缺口：

- `known-gap-english-period`：含句点的英文对白被过滤，预期 1 个请求，实际 0。此次没有修复。
- `known-gap-latest-frame-while-busy`：画面已到新对白时，旧请求仍可能交付。失败步骤实际收到“测试译文甲”，预期不显示旧字幕。`inFlight` 阻止新 OCR 是已登记根因证据；此结果与 Lite 的快切目标不符，不能把普通乱序回归通过当成快切验收通过。

这是 headless 生产链路检查，真实 API 调用 0；未执行 Mac 实际设备或桌面 UI 验收。生产代码未改，自动回归结果维持既有基线，不代表两个已知产品缺口已解决。

## PoC 本轮真实检查

最终命令：`python3 scripts/check-ipados-poc.py --build`。实际报告：`.build/ipados-poc/20261008T054828Z-lttzokuh/summary.json`。退出码 **1**，失败保留，不以被阻断或跳过项计为通过。

| 检查 | 本轮结果 | 含义与失败原因 |
| --- | --- | --- |
| Xcode project/Info.plist/scheme 结构 | PASS | plutil 解析，源文件编译成员、iPad 家族 2、部署目标 17.0、视频权限和无后台/麦克风权限检查通过；不等于 Xcode 可构建 |
| Swift 源文件语法 | PASS | `swiftc -frontend -parse -Xcc -fno-implicit-module-maps`；只解析语法，不解析 Apple API 或证明类型正确 |
| 主机生产帧槽测试编译 | FAILED | 本机 SwiftBridging 重复模块定义，Foundation 导入失败 |
| 主机帧槽测试执行 | NOT RUN | 上一步编译失败；有界释放、epoch、并发、帧率和离散格式测试尚未执行通过 |
| 采集服务在 macOS SDK 下类型检查 | FAILED | 同一模块冲突，另输出 SDK/编译器不匹配诊断；不能认定类型正确 |
| xcodebuild 预检 | FAILED | 当前 developer directory 为 CommandLineTools，未安装完整 Xcode |
| iPadOS SDK 预检 | FAILED | `iphoneos` SDK 不存在 |
| generic iOS device 编译 | NOT RUN | 完整 Xcode/SDK 前置失败，无二进制产物 |
| 真机签名/安装 | NOT RUN | 无构建、开发签名和真机安装证据 |
| UVC 枚举/Switch 预览/缓冲/插拔/中断/长时内存 | NOT VERIFIED | 无实际目标硬件执行记录，不能据源码或 API 文档判 PASS |

`git diff --check`、检查入口 Python 语法检查和单独的 Swift 语法解析执行成功。文档相对链接与工程资源路径另外核对；没有进行无法执行的 UI 截图验收。

环境补查：`xcode-select -p` 返回 `/Library/Developer/CommandLineTools`，Swift 6.0.3。`xcodebuild -version`、`xcrun --sdk iphoneos --show-sdk-path` 失败，`devicectl` 不可用；`/Applications` 没有 Xcode bundle。主机 SDK 有 13.3、14.4、14.5、15.2，默认 15.2；显式指定现有 14.5 SDK 也未消除 SwiftBridging 重复定义。尝试的私有编译器 VFS 映射未解决类型检查，已从正式入口移除，原始日志保留在忽略的 `.build/`。系统模块、xcode-select 和 Codex 配置均未修改。

## 最短继续步骤与剩余风险

1. 准备完整 Xcode 与目标 iPadOS SDK，在有效环境重新运行 `python3 scripts/check-ipados-poc.py --build`，解决真实的类型/设备构建错误；辅助测试必须执行成功，不能只保留语法 PASS。
2. 打开 `ipados/CapturePoC/YiyaCapturePoC.xcodeproj`，选择开发 Team、实际 USB-C iPad，签名并安装。
3. 按 [硬件验收表](../ipados/CapturePoC/HARDWARE_VALIDATION.md)连接 Switch HDMI → UVC → iPad；确认实际内容与像素缓冲，完成权限、拔插、前后台、中断和至少 30 分钟连续运行。
4. 填写每个型号/系统/采集卡组合的真实结果、失败原因与未覆盖项。第二阶段通过后才按 [共享核心方案](ipados-lite-feasibility.md)接 OCR/翻译，并针对同会话快切新建失败回归后修复。

剩余风险包括：SwiftUI/UIKit/AVFoundation 的 iPad 类型检查和运行行为、采集卡与 USB 供电/带宽兼容、真实 HDMI 内容与方向、系统权限和中断恢复、帧槽实际内存释放、30 分钟断流/发热、游戏声音与可接受操作延迟。OCR、翻译、分段耗时和最终快切验收尚未实现，不能填通过。

当前阶段门为 **hardware_gate=not_verified，third_stage_allowed=false**。没有用 Mac 回归、语法检查、工程结构或 Apple 平台说明替代真机验收。

## 2026-10-09 分支提交前复查

运行 `python3 scripts/check-ipados-poc.py`，退出码 **1**。工程与权限结构、Swift 语法检查通过；主机帧槽测试编译和采集服务类型检查仍因 `SwiftBridging` 重复模块定义失败，帧槽执行测试未运行。报告保存在本机忽略目录 `.build/ipados-poc/20261009T145859Z-62p193b3/summary.json`。本次没有要求 iPadOS 设备构建，也未进行签名安装或真机验收；源码以尚未验收的 PoC 提交，硬件阶段门继续关闭。
