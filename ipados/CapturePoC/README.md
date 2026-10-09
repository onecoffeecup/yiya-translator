# 译芽 iPad 视频采集 PoC

独立 iPadOS 17+ SwiftUI 工程，只验证 USB-C UVC 视频链路。Mac 源码、构建与安装入口不变。当前工程没有通过 iPadOS 设备构建或真机验证，不能认定采集功能可用；实际结果见 [验证记录](../../docs/ipados-lite-validation.md)。

## 范围

- 仅发现 `.external` 视频设备，不回退内置相机；用户点击启动才申请相机权限。
- AVFoundation 会话、设备通知、配置、启停和回调使用同一串行队列；预览使用 AVCaptureVideoPreviewLayer，等比完整显示 HDMI 图像，关闭镜像与设备方向自动旋转。
- AVCaptureVideoDataOutput 丢弃迟到帧，直接保留最新 CVPixelBuffer 一项；不做 UIImage/CGImage 全帧转换。`LatestFrameMailbox.snapshot()` 返回具有 epoch、index、PTS 和接收单调时间的缓冲，供后续 OCR 适配器使用。
- 显示实际缓冲尺寸、协商目标帧率、实际收到帧率、系统丢帧/无效帧数、最近帧年龄、会话启动耗时和回调耗时；按钮检查实际像素缓冲访问。
- 断开、暂停、后台、运行失败与中断清旧帧并作废 epoch。同一设备身份重连使用新设备实例；身份改变需重新选择。媒体服务重置自动重试最多一次；其他错误由用户重试。会话运行但 3 秒无新帧时隐藏旧预览并提示。
- 没有 OCR、翻译 API、音频、API Key、学习、持久诊断或画面记录。没有合成视频回退或模拟采集“成功”。

格式优先选择设备实际支持的 720p/30，再按范围选择 <=1080p 接近 720p 的模式；如果仅有其他格式则使用设备可用模式。帧率区间分别判断，不在离散范围之间发明 30fps。输出优先 NV12，备选 BGRA；协商失败给出错误，而不静默假定成功。缓冲尺寸才是实际输出分辨率。

## 构建和运行

需要完整 Xcode 15+（或支持目标 iPadOS 的更高版本）、iPadOS SDK、USB-C iPad、开发签名账号及设备开发者模式。iPadOS 17 作为部署下限；操作系统和设备兼容性必须分别记录。不要把 iPhone、Mac Designed for iPad、Mac Catalyst 或模拟器作为硬件验收目标。

1. 使用 Xcode 打开 `YiyaCapturePoC.xcodeproj`，选择 `YiyaCapturePoC` scheme。
2. 在 Signing & Capabilities 选择自己的开发 Team，必要时为 PoC 设置自己的 Bundle Identifier。
3. 连接并选择实际 iPad，在设备上运行。
4. 连接 Switch Dock HDMI → UVC 采集卡 → iPad USB-C 数据口；确保 Switch 已输出 HDMI，采集卡及集线器供电正常。
5. 在 App 中选择外接设备，启动、授权，目视确认真实 Switch 画面，并检查像素缓冲。
6. 按 [硬件验收表](HARDWARE_VALIDATION.md)完成权限、方向、拔插、中断和持续运行记录；未通过前不接 OCR/HTTP。

在源码仓库根运行无硬件检查：

```bash
python3 scripts/check-ipados-poc.py
# 再要求 iPadOS generic device 编译，无签名，不安装
python3 scripts/check-ipados-poc.py --build
# 仅当本机默认 macOS SDK 冲突时，显式指定已有 SDK；不改变系统设置
python3 scripts/check-ipados-poc.py --host-sdk /path/to/MacOSX.sdk --build
python3 scripts/debug.py check
```

检查报告位于忽略的 `.build/ipados-poc/`，包含命令、退出码与源文件 SHA-256。默认检查结构、语法、生产帧槽/统计/格式选择的执行测试及采集服务在 macOS SDK 下的类型检查；编译失败的测试会标为 `not_run`。`--build` 缺完整 Xcode/SDK 会失败，不冒充构建成功。所有情况都保持 `hardware_gate=not_verified` 和 `third_stage_allowed=false`，自动脚本不负责替代人工硬件验收。

回调平均/最大耗时只测当前回调处理；会话启动耗时只测 startRunning。PTS 属于采集流时钟，不可直接与系统 uptime 相减宣称端到端延迟。Switch 到显示延迟需要外部对照/高速摄影；后续 OCR 与 HTTP 必须另外计时。

## 后续接入边界

当前没有共享业务核心，避免硬件门通过前修改 Mac。真机通过后按 [实施方案](../../docs/ipados-lite-feasibility.md)接入现有 Objective-C OCR、身份、缓存与翻译模块。Swift 只负责输入/展示适配。现有“忙时不观察新对白”失败回归必须保留，并在共享调度器中验证快切、取消后迟到回复、输入重连与配置改变。

截图、视频、原始 OCR 和译文不得默认记录；需要文字或画面诊断时遵循 `DEBUG_WORKFLOW.md` 显式启用与私有保存规则。硬件记录表只填型号、系统版本和聚合统计，不附设备 uniqueID、序列号、Key、对白或游戏截图。PoC 使用独立 Bundle ID，不访问 Mac 凭据与学习数据库。
