# 像素冒险手账 UI 资产

最新造型校准为 本机内部 V2 校准板（不随公开源码分发），对应 `icons-v2/` 的 14 个新 SVG。下文 `icons/` 的 24 个单色线图属于第一版历史资产，不能再作为饱满彩色导航图标的默认造型。

第一版原创 UI 图标共 24 个，清单见 [icons/manifest.json](icons/manifest.json)，历史设计稿和 Figma 交付说明仅在维护者本机保留。这些是界面操作图标；已确认的「译芽 / Yiya！」macOS 应用图标仍使用 `resources/AppIcon.png` 与 ICNS。

图标在 16 × 16 像素格内绘制，再居中放入 24 × 24 的透明 SVG 画布；viewBox 为 `0 0 24 24`，单个像素单元为 1，外围留白 4。路径采用 currentColor 和 crispEdges，填充轮廓代替有抗锯齿漂移的圆滑描边。`manifest.json` 的 sourceGrid=24 表示导出画布尺寸，内部造型格为 16。

正常控件使用 24pt，说明性展示可用 48pt；按整数倍缩放并对齐像素。实际按钮的点击区域至少 32pt，图形留白不算作缩小点击区域的理由。深底用 paper 或 turquoise，浅底用 ink / actionTeal；状态同时提供文字或可访问名称。单色路径可以在 AppKit 中转为模板图像或矢量绘制，导出 PNG 时需要同时准备 @1x / @2x 并保持整数边缘。

| 类别 | 图标名称 |
| --- | --- |
| 导航 | translate、history、book、settings、subtitle、service |
| 操作 | play、pause、pin、bookmark、star、refresh、edit、copy、send、close |
| 方向 | chevron-left、chevron-right、chevron-down、chevron-up |
| 辅助 | ai、eye、check、link |

`scene-demo.svg` 是原创像素场景，仅用于静态演示。不能为了配合主题改变用户的真实采集画面。

重新生成图标：在项目根目录运行 `python3 docs/design/figma/build-icons.py`。修改造型时同步生成器、本地 SVG/清单和 Figma 对应 Icon 组件；保持组件里的 Pixel paths 容器及内部 Vector 双轴 Scale 约束。本轮资产尚未接入应用。

## 当前 V3 原生接入

AppKit 使用 `art-v3/art-atlas.png` 的独立插画区域，由 `FYAdventureTheme.h` / `FYLearningViews.m` 绘制。图集包含导航、AI 标识、标题风景和植物；旧 SVG 保留作历史参考。实际游戏预览不读取图集中的演示场景。
