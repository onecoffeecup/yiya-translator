import AVFoundation
import Combine
import CoreVideo
import Foundation

struct VideoDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

struct CaptureStatus {
    var devices: [VideoDevice] = []
    var selectedID = ""
    var phase = "等待外接设备"
    var detail = "连接 USB-C UVC 采集卡后，点击启动采集。"
    var wantsCapture = false
    var hasLiveFrames = false
    var permissionDenied = false
    var width = 0
    var height = 0
    var pixelFormat: OSType = 0
    var negotiatedFPS: Double = 0
    var sessionStartMS: Double = 0
    var frameAge: Double?
    var epoch: UInt64 = 0
    var metrics = CaptureMetrics()
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published private(set) var status = CaptureStatus()
    @Published private(set) var previewSession: AVCaptureSession?
    @Published private(set) var bufferProbe = "尚未检查像素缓冲"
    private let service = CaptureService()

    init() {
        service.onUpdate = { [weak self] status, session in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = status
                self.previewSession = session
                if !status.hasLiveFrames { self.bufferProbe = "当前没有有效的新帧" }
            }
        }
        service.refresh()
    }

    func start() { service.start() }
    func pause() { service.pause() }
    func select(_ id: String) { service.select(id) }
    func setForeground(_ active: Bool) { service.setForeground(active) }
    func refresh() { service.refresh() }
    func probeBuffer() {
        guard let frame = service.frames.snapshot(), frame.epoch == status.epoch,
              ProcessInfo.processInfo.systemUptime - frame.receivedSeconds < 3 else {
            bufferProbe = "当前没有有效的新帧"
            return
        }
        bufferProbe = "CVPixelBuffer 可读取：\(CVPixelBufferGetWidth(frame.value)) × \(CVPixelBufferGetHeight(frame.value)) · 帧 \(frame.index) · 会话 \(frame.epoch)"
    }
}

// Session, configuration, device notifications and delegates share ONE queue.
// No OCR/HTTP/UIImage conversion takes place in the callback or on the main thread.
private final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let frames = LatestFrameMailbox<CVPixelBuffer>()
    var onUpdate: ((CaptureStatus, AVCaptureSession?) -> Void)?
    private let queue = DispatchQueue(label: "com.nanami.yiya.ipad.capture", qos: .userInitiated)
    private let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external], mediaType: .video, position: .unspecified)
    private var status = CaptureStatus()
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var tokens: [NSObjectProtocol] = []
    private var sessionTokens: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var foreground = true
    private var permissionPending = false
    private var startedAt: Double?
    private var resetAttempts = 0

    override init() {
        super.init()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) {
                [weak self] _ in self?.queue.async { [weak self] in self?.devicesChanged() }
            })
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.heartbeat() }
        watchdog = timer
        timer.resume()
    }

    deinit {
        watchdog?.cancel()
        (tokens + sessionTokens).forEach(NotificationCenter.default.removeObserver)
        // App-scoped owner; regular lifecycle teardown always goes through queue.
    }

    func refresh() { queue.async { [weak self] in self?.devicesChanged() } }
    func select(_ id: String) {
        queue.async { [weak self] in
            guard let self, self.status.selectedID != id else { return }
            self.tearDown()
            self.status.selectedID = id
            self.resetAttempts = 0
            self.resumeIfPossible()
        }
    }
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.status.wantsCapture = true
            self.resetAttempts = 0
            self.resumeIfPossible()
        }
    }
    func pause() {
        queue.async { [weak self] in
            guard let self else { return }
            self.status.wantsCapture = false
            self.tearDown()
            self.setPhase("已暂停", "已释放采集会话，点击启动可重新连接。")
        }
    }
    func setForeground(_ active: Bool) {
        queue.async { [weak self] in
            guard let self, self.foreground != active else { return }
            self.foreground = active
            if active { self.devicesChanged() }
            else {
                self.tearDown()
                self.setPhase("采集已挂起", "进入后台或失去活动状态，返回前台后按启动意图恢复。")
            }
        }
    }

    private func devicesChanged() {
        status.devices = discovery.devices.filter { $0.isConnected }.map {
            VideoDevice(id: $0.uniqueID, name: $0.localizedName)
        }
        if status.selectedID.isEmpty { status.selectedID = status.devices.first?.id ?? "" }
        if !status.wantsCapture && status.phase != "已暂停" {
            if status.devices.isEmpty {
                status.phase = "等待外接设备"
                status.detail = "未发现 UVC 视频设备，请检查 USB 数据线、采集卡和供电。"
            } else {
                status.phase = "设备已发现，尚未采集"
                status.detail = "请选择设备并启动采集；收到缓冲后再确认 Switch 画面。"
            }
        }
        if session != nil && !status.devices.contains(where: { $0.id == status.selectedID }) {
            tearDown()
            setPhase("设备已断开", "旧帧已清除；同一设备重连后恢复。若设备身份改变，请重新选择。")
        }
        resumeIfPossible()
    }

    private func resumeIfPossible() {
        guard foreground else { publish(); return }
        guard status.wantsCapture else { publish(); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard !permissionPending else { return }
            permissionPending = true
            setPhase("等待相机授权", "系统相机权限也用于外接视频采集；只申请视频权限。")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.permissionPending = false
                    self.resumeIfPossible() // Recheck latest pause/foreground/device intent.
                }
            }
            return
        case .denied, .restricted:
            tearDown()
            status.permissionDenied = true
            setPhase("相机权限不可用", "请在系统设置中允许译芽使用相机；受管理的 iPad 可能限制此权限。")
            return
        case .authorized: status.permissionDenied = false
        @unknown default:
            setPhase("未知权限状态", "无法开始采集，请检查系统权限。")
            return
        }
        guard session == nil else { publish(); return }
        // Always fetch a fresh AVCaptureDevice after a reconnect; never use built-in fallback.
        guard let device = discovery.devices.first(where: {
            $0.uniqueID == status.selectedID && $0.isConnected && $0.deviceType == .external
        }) else {
            setPhase("等待外接设备", "未找到所选 UVC 设备。检查 USB 数据线与供电，或重新选择设备。")
            return
        }
        configure(device)
    }

    private func configure(_ device: AVCaptureDevice) {
        tearDown()
        status.metrics = CaptureMetrics()
        status.negotiatedFPS = 0
        status.sessionStartMS = 0
        setPhase("正在建立会话", "设备已发现；还不能确认视频帧或 HDMI 信号。")
        let candidate = AVCaptureSession()
        let dataOutput = AVCaptureVideoDataOutput()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            candidate.beginConfiguration()
            guard candidate.canAddInput(input) else {
                candidate.commitConfiguration()
                setPhase("无法添加视频输入", "设备可能不兼容或被系统占用，请重连后重试。")
                return
            }
            candidate.addInput(input)
            guard candidate.canAddOutput(dataOutput) else {
                candidate.commitConfiguration()
                setPhase("无法添加像素输出", "该设备无法建立 VideoDataOutput，请记录设备与系统版本。")
                return
            }
            candidate.addOutput(dataOutput)
            if candidate.canSetSessionPreset(.inputPriority) { candidate.sessionPreset = .inputPriority }
            var options: [CaptureFormatOption] = []
            for (index, format) in device.formats.enumerated() {
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                for range in format.videoSupportedFrameRateRanges {
                    options.append(CaptureFormatOption(index: index, width: Int(size.width), height: Int(size.height),
                        minimumFPS: range.minFrameRate, maximumFPS: range.maxFrameRate))
                }
            }
            if let choice = preferredCaptureFormat(options) {
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    device.activeFormat = device.formats[choice.index]
                    let duration = CMTime(seconds: 1 / choice.targetFPS, preferredTimescale: 600_000)
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    status.negotiatedFPS = choice.targetFPS
                } catch {
                    candidate.commitConfiguration()
                    setPhase("设备格式配置失败", "未开始采集。错误码 \((error as NSError).code)；可重连或换设备再试。")
                    return
                }
            }
            let supported = dataOutput.availableVideoPixelFormatTypes
            let preferred: [OSType] = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_32BGRA]
            guard let pixelFormat = preferred.first(where: { supported.contains($0) }) ?? supported.first else {
                candidate.commitConfiguration()
                setPhase("没有可用像素格式", "采集卡不能提供此输出所需的像素缓冲。")
                return
            }
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(self, queue: queue)
            if let connection = dataOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            }
            candidate.commitConfiguration()
            session = candidate
            output = dataOutput
            observeSession(candidate)
            startedAt = ProcessInfo.processInfo.systemUptime
            candidate.startRunning() // Blocking AVFoundation work stays off main thread.
            status.sessionStartMS = (ProcessInfo.processInfo.systemUptime - (startedAt ?? 0)) * 1_000
            if candidate.isRunning {
                setPhase("会话已启动，等待帧", "尚未收到有效像素缓冲；不代表 Switch 画面可用。")
            } else {
                tearDown()
                setPhase("会话未能启动", "没有进入运行状态，请重试并记录采集卡与系统版本。")
            }
        } catch {
            tearDown()
            setPhase("视频输入失败", "无法打开设备，错误码 \((error as NSError).code)。请检查连接与系统占用。")
        }
    }

    private func observeSession(_ observed: AVCaptureSession) {
        let names: [Notification.Name] = [AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification]
        for name in names {
            sessionTokens.append(NotificationCenter.default.addObserver(forName: name, object: observed, queue: nil) {
                [weak self, weak observed] notification in
                self?.queue.async { [weak self, weak observed] in
                    guard let self, let observed, self.session === observed else { return }
                    if name == AVCaptureSession.wasInterruptedNotification {
                        self.status.epoch = self.frames.invalidate()
                        self.status.hasLiveFrames = false
                        let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
                        self.setPhase("采集被系统中断", "中断原因码 \(reason?.intValue ?? 0)；旧帧已清除，等待系统恢复。")
                    } else if name == AVCaptureSession.interruptionEndedNotification {
                        self.tearDown()
                        self.resumeIfPossible()
                    } else {
                        let code = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code ?? 0
                        self.tearDown()
                        if code == AVError.Code.mediaServicesWereReset.rawValue && self.resetAttempts < 1 {
                            self.resetAttempts += 1
                            self.resumeIfPossible()
                        } else {
                            self.setPhase("采集运行错误", "错误码 \(code)；会话已释放。点击启动采集重试。")
                        }
                    }
                }
            })
        }
    }

    private func tearDown() {
        status.epoch = frames.invalidate()
        status.hasLiveFrames = false
        status.width = 0; status.height = 0; status.pixelFormat = 0; status.frameAge = nil
        output?.setSampleBufferDelegate(nil, queue: nil)
        sessionTokens.forEach(NotificationCenter.default.removeObserver)
        sessionTokens.removeAll()
        session?.stopRunning()
        session = nil
        output = nil
        startedAt = nil
    }

    private func setPhase(_ phase: String, _ detail: String) {
        status.phase = phase; status.detail = detail
        publish()
    }
    private func publish() { onUpdate?(status, session) }
    private func heartbeat() {
        guard let session, status.wantsCapture, foreground else { return }
        let now = ProcessInfo.processInfo.systemUptime
        status.frameAge = status.metrics.age(at: now)
        guard !session.isInterrupted else { publish(); return }
        let stale = status.frameAge.map { $0 >= 3 } ?? (now - (startedAt ?? now) >= 3)
        if stale {
            if status.hasLiveFrames { status.epoch = frames.invalidate() }
            status.hasLiveFrames = false
            status.phase = "没有收到新帧"
            status.detail = "会话存在但像素输出停滞。检查 HDMI 信号、USB 供电与线材，可暂停后重新启动。"
        }
        publish() // At most one routine UI update per second.
    }

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard captureOutput === output, status.wantsCapture, foreground,
              session?.isInterrupted == false else { return }
        let begin = ProcessInfo.processInfo.systemUptime
        defer { status.metrics.recordCallback(seconds: ProcessInfo.processInfo.systemUptime - begin) }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetWidth(buffer) > 0, CVPixelBufferGetHeight(buffer) > 0 else {
            status.metrics.reject()
            return
        }
        status.metrics.receive(at: begin)
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        frames.store(buffer, epoch: status.epoch, presentationSeconds: pts, receivedSeconds: begin)
        status.width = CVPixelBufferGetWidth(buffer)
        status.height = CVPixelBufferGetHeight(buffer)
        status.pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        if !status.hasLiveFrames {
            status.hasLiveFrames = true
            status.frameAge = 0
            setPhase("正在接收视频帧", "请目视确认这是 Switch 游戏画面；帧到达不能判断 HDMI 内容。")
        }
    }
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard captureOutput === output else { return }
        status.metrics.drop()
    }
}
