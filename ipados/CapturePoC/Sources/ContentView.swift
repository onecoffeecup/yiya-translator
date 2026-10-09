import SwiftUI
import UIKit

// Palette follows the approved cream/brown theme. Native Dynamic Type and SF symbols.
private enum YiyaTheme {
    static let paper = Color(red: 0.976, green: 0.957, blue: 0.922)
    static let panel = Color(red: 0.988, green: 0.976, blue: 0.953)
    static let ink = Color(red: 0.349, green: 0.243, blue: 0.169)
    static let secondary = Color(red: 0.459, green: 0.376, blue: 0.306)
    static let leaf = Color(red: 0.792, green: 0.855, blue: 0.651)
    static let line = Color(red: 0.729, green: 0.631, blue: 0.506)
}

@MainActor
struct ContentView: View {
    @StateObject private var model = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("译芽 · 视频采集验证").font(.largeTitle.bold())
                    Text("连接 Switch 和 UVC 采集卡，验证 iPad 能否接收游戏画面。")
                        .foregroundStyle(YiyaTheme.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label(model.status.phase, systemImage: model.status.hasLiveFrames ? "video.fill" : "video.slash")
                        .font(.headline).accessibilityAddTraits(.updatesFrequently)
                    Text(model.status.detail).textSelection(.enabled)
                    Picker("视频设备", selection: Binding(get: { model.status.selectedID }, set: model.select)) {
                        Text("请选择外接视频设备").tag("")
                        if !model.status.selectedID.isEmpty &&
                            !model.status.devices.contains(where: { $0.id == model.status.selectedID }) {
                            Text("所选设备已断开").tag(model.status.selectedID)
                        }
                        ForEach(model.status.devices) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("只列出外接视频设备")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { actions }
                        VStack(alignment: .leading, spacing: 12) { actions }
                    }
                    if model.status.permissionDenied {
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(.bordered).frame(minHeight: 44)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading).card()

                ZStack {
                    Color.black
                    CapturePreview(session: model.previewSession)
                        .opacity(model.status.hasLiveFrames ? 1 : 0)
                        .accessibilityLabel("外接采集卡实时画面")
                    if !model.status.hasLiveFrames {
                        VStack(spacing: 12) {
                            Image(systemName: "cable.connector").font(.largeTitle)
                            Text(model.status.phase).font(.headline)
                            Text("收到有效新帧后显示实际画面").font(.body)
                        }.foregroundStyle(.white).padding()
                    }
                }
                .aspectRatio(previewAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("视频输入统计").font(.title2.bold())
                    LabeledContent("像素尺寸", value: model.status.width > 0 ? "\(model.status.width) × \(model.status.height)" : "等待缓冲")
                    LabeledContent("接收帧率", value: String(format: "%.1f fps", model.status.hasLiveFrames ? model.status.metrics.deliveredFPS(at: ProcessInfo.processInfo.systemUptime) : 0))
                    LabeledContent("协商目标帧率", value: String(format: "%.1f fps", model.status.negotiatedFPS))
                    LabeledContent("像素格式代码", value: model.status.pixelFormat == 0 ? "—" : String(model.status.pixelFormat))
                    LabeledContent("收到 / 系统丢帧 / 无效", value: "\(model.status.metrics.received) / \(model.status.metrics.dropped) / \(model.status.metrics.invalid)")
                    LabeledContent("最近帧距现在", value: model.status.frameAge.map { String(format: "%.1f 秒", $0) } ?? "等待帧")
                    LabeledContent("会话启动耗时", value: String(format: "%.1f ms", model.status.sessionStartMS))
                    LabeledContent("回调处理平均 / 最大", value: String(format: "%.2f / %.2f ms", model.status.metrics.callbackMeanMS, model.status.metrics.callbackMaxMS))
                    Button("检查最新像素缓冲", action: model.probeBuffer)
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .disabled(!model.status.hasLiveFrames)
                    Text(model.bufferProbe).textSelection(.enabled)
                    Text("帧率来自实际回调计数；回调耗时不等于 HDMI 到显示的延迟。")
                        .foregroundStyle(YiyaTheme.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).card()

                Text("当前为视频采集 PoC，不采音频。OCR 与翻译等待真机采集验收通过后接入。")
                    .foregroundStyle(YiyaTheme.secondary).textSelection(.enabled)
            }
            .padding(24).frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(YiyaTheme.ink)
        .background(YiyaTheme.paper)
        .tint(YiyaTheme.ink)
        .controlSize(.large)
        .preferredColorScheme(.light)
        .onAppear { model.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setForeground(phase == .active) }
        .onDisappear { model.setForeground(false) }
    }

    private var previewAspect: CGFloat {
        model.status.width > 0 && model.status.height > 0
            ? CGFloat(model.status.width) / CGFloat(model.status.height) : 16 / 9
    }
    @ViewBuilder private var actions: some View {
        Button("启动采集", systemImage: "play.fill", action: model.start)
            .buttonStyle(.borderedProminent).tint(YiyaTheme.leaf).foregroundStyle(YiyaTheme.ink)
            .frame(minHeight: 44).disabled(model.status.hasLiveFrames)
        Button("暂停采集", systemImage: "pause.fill", action: model.pause)
            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!model.status.wantsCapture)
        Button("刷新设备", systemImage: "arrow.clockwise", action: model.refresh)
            .buttonStyle(.bordered).frame(minHeight: 44)
    }
}

private extension View {
    func card() -> some View {
        background(YiyaTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(YiyaTheme.line, lineWidth: 1))
    }
}
