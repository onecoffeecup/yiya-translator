// 采集卡真实硬件探针：调用**生产类** FYCaptureCardInput 读取外接采集卡画面。
// 只采视频、不采音频、不截屏、不读用户设置与学习库、不访问网络。
// 与 .build/clean-video-probe 的独立验证程序同一纪律：
//   * 只认显式指定的设备名，找不到就失败，绝不回退到内置/手机摄像头；
//   * 权限没批准就不采集；
//   * 结束时释放会话并记录 session_released。
//
// 用法：
//   CaptureCardProbe inspect   <私有输出目录>
//   CaptureCardProbe authorize <私有输出目录>
//   CaptureCardProbe capture   <私有输出目录> <设备显示名> <帧数>
//
// 无参数时（用 open 经 LaunchServices 启动）从 <默认目录>/request.json 读取
// {"mode":..., "device_name":..., "frames":..., "directory":...}。
// 这一步很重要：直接从终端跑子进程时，TCC 会把它归到终端/父进程名下，
// 相机授权状态读出来就不对；经 LaunchServices 启动才是探针自己的身份。
#define main FuyiMainForCaptureCardProbe
#import "LiveCaptionTranslator.m"
#undef main
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>
#import <unistd.h>

@interface FYCaptureCardProbe : NSObject
@property(nonatomic, copy) NSString *mode;
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, copy) NSString *deviceName;
@property(nonatomic) NSInteger wantedFrames;
@property(nonatomic, strong) FYCaptureCardInput *input;
@property(nonatomic, strong) NSMutableDictionary *status;
@property(nonatomic, strong) NSMutableArray *frames;
@property(nonatomic) uint64_t lastSavedIndex;
@property(nonatomic) NSTimeInterval lastSavedTime;
@property(nonatomic) NSTimeInterval started;
@property(nonatomic) BOOL finished;
@property(nonatomic, strong) NSTimer *poll;
@end

@implementation FYCaptureCardProbe

- (void)writeStatus {
    self.status[@"updated_unix_ms"] = @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
    self.status[@"frames"] = [self.frames copy];
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.status options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:NULL];
    NSString *path = [self.directory stringByAppendingPathComponent:@"status.json"];
    if (data && path) {
        [data writeToFile:path atomically:YES];
        chmod(path.fileSystemRepresentation, 0600);
    }
}

- (BOOL)quickTimeRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.QuickTimePlayerX"].count > 0;
}
- (BOOL)obsRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.obsproject.obs-studio"].count > 0;
}

- (void)finishWithState:(NSString *)state {
    if (self.finished) { return; }
    self.finished = YES;
    [self.poll invalidate];
    self.poll = nil;
    self.status[@"state"] = state;
    self.status[@"stopping"] = @YES;
    self.status[@"quicktime_running_at_end"] = @([self quickTimeRunning]);
    self.status[@"obs_running_at_end"] = @([self obsRunning]);
    [self writeStatus];
    // stopRunning 在驱动异常时可能长时间阻塞；给探针自己一个硬超时，绝不去动别的应用。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        self.status[@"forced_probe_exit"] = @YES;
        [self writeStatus];
        _exit(124);
    });
    [self.input stop];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.status[@"session_released"] = @(self.input.sessionReleased);
        self.status[@"session_epoch"] = @(self.input.sessionEpoch);
        self.status[@"received_frames"] = @(self.input.receivedFrameCount);
        self.status[@"stored_frames"] = @(self.input.storedFrameCount);
        self.status[@"skipped_frames"] = @(self.input.skippedFrameCount);
        self.status[@"conversion_failures"] = @(self.input.conversionFailureCount);
        self.status[@"stopping"] = @NO;
        [self writeStatus];
        [NSApp terminate:nil];
    });
}

- (void)pollFrames {
    uint64_t index = self.input.latestFrameIndex;
    if (index == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (index == 0 || index == self.lastSavedIndex) { return; }
    if (self.lastSavedTime > 0 && now - self.lastSavedTime < 0.25) { return; }
    CGImageRef frame = [self.input copyLatestFrame];
    if (!frame) { return; }
    self.lastSavedIndex = index;
    self.lastSavedTime = now;
    NSString *name = [NSString stringWithFormat:@"frame-%02lu.png", (unsigned long)self.frames.count + 1];
    NSString *path = [self.directory stringByAppendingPathComponent:name];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    BOOL saved = NO;
    if (destination) {
        CGImageDestinationAddImage(destination, frame, NULL);
        saved = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    size_t width = CGImageGetWidth(frame), height = CGImageGetHeight(frame);
    CGImageRelease(frame);
    if (!saved) { [self finishWithState:@"frame_save_failed"]; return; }
    chmod(path.fileSystemRepresentation, 0600);
    [self.frames addObject:@{@"file": name, @"width": @(width), @"height": @(height),
                             @"stream_index": @(index),
                             @"time_unix_ms": @((long long)(now * 1000))}];
    [self writeStatus];
    if ((NSInteger)self.frames.count >= self.wantedFrames) {
        [self finishWithState:@"captured_requested_frames"];
    }
}

- (void)runInspect {
    NSMutableArray *devices = [NSMutableArray array];
    for (FYCaptureCardDeviceInfo *device in [self.input availableDevices]) {
        [devices addObject:@{@"display_name": device.displayName,
                             @"in_use_by_another_application": @(device.inUseByAnotherApplication)}];
    }
    self.status[@"available_capture_devices"] = devices;
    self.status[@"camera_authorization"] = FYCaptureCardAvailabilityLabel([self.input availability]);
    self.status[@"capture_started"] = @NO;
    self.status[@"permissions_requested"] = @NO;
    self.status[@"state"] = @"inspected_only";
    self.finished = YES;
    [self writeStatus];
    [NSApp terminate:nil];
}

- (void)runAuthorize {
    self.status[@"permissions_requested"] = @YES;
    self.status[@"state"] = @"waiting_for_camera_permission";
    self.status[@"camera_authorization_before"] = FYCaptureCardAvailabilityLabel([self.input availability]);
    [self writeStatus];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self finishWithState:@"permission_wait_timeout_no_capture"];
    });
    [self.input requestAccessWithCompletion:^(FYCaptureCardAvailability availability) {
        self.status[@"camera_authorization"] = FYCaptureCardAvailabilityLabel(availability);
        self.status[@"capture_started"] = @NO;
        [self finishWithState:availability == FYCaptureCardAvailabilityAuthorized ? @"authorized_only_no_capture"
                                                                                : @"permission_not_granted"];
    }];
}

- (void)runCapture {
    FYCaptureCardAvailability availability = [self.input availability];
    self.status[@"camera_authorization"] = FYCaptureCardAvailabilityLabel(availability);
    if (availability != FYCaptureCardAvailabilityAuthorized) {
        self.status[@"capture_started"] = @NO;
        [self finishWithState:@"capture_requires_camera_authorization"];
        return;
    }
    NSString *uniqueID = nil;
    for (FYCaptureCardDeviceInfo *device in [self.input availableDevices]) {
        if ([device.displayName isEqualToString:self.deviceName]) {
            if (uniqueID) {
                [self finishWithState:@"device_name_ambiguous"];
                return;
            }
            uniqueID = device.uniqueID;
        }
    }
    if (!uniqueID) {
        self.status[@"capture_started"] = @NO;
        [self finishWithState:@"device_not_found_no_fallback"];
        return;
    }
    self.status[@"device_selected_by"] = @"exact display name among external capture devices; no fallback";
    self.status[@"selected_display_name"] = self.deviceName;
    self.started = NSDate.date.timeIntervalSince1970;
    if (![self.input startWithDeviceUniqueID:uniqueID]) {
        self.status[@"capture_started"] = @NO;
        self.status[@"state_detail"] = self.input.stateDetail;
        [self finishWithState:@"capture_start_failed"];
        return;
    }
    self.status[@"capture_started"] = @YES;
    self.status[@"state"] = @"waiting_for_video_frames";
    [self writeStatus];
    self.poll = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(pollFrames) userInfo:nil repeats:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self finishWithState:self.frames.count > 0 ? @"capture_timeout_with_frames" : @"capture_timeout_no_frames"];
    });
}

@end

static BOOL FYProbeDirectoryIsPrivate(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) { return NO; }
    return S_ISDIR(st.st_mode) && st.st_uid == getuid() && (st.st_mode & 077) == 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // 支持用 LaunchServices 启动（open -W 译芽采集卡探针.app）来触发系统权限提示：
        // open 不传参数，因此无参数时默认走 authorize，输出固定到 /tmp。
        NSString *defaultDirectory = @"/tmp/yiya-capture-card-probe";
        NSDictionary *request = nil;
        if (argc < 2) {
            [[NSFileManager defaultManager] createDirectoryAtPath:defaultDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:@{NSFilePosixPermissions: @0700}
                                                            error:NULL];
            NSData *requestData = [NSData dataWithContentsOfFile:[defaultDirectory stringByAppendingPathComponent:@"request.json"]];
            if (requestData) {
                id parsed = [NSJSONSerialization JSONObjectWithData:requestData options:0 error:NULL];
                if ([parsed isKindOfClass:NSDictionary.class]) { request = parsed; }
            }
        }
        NSString *mode = argc >= 2 ? @(argv[1]) : (request[@"mode"] ?: @"authorize");
        if (![mode isEqualToString:@"inspect"] && ![mode isEqualToString:@"authorize"] && ![mode isEqualToString:@"capture"]) {
            fprintf(stderr, "未知模式: %s\n", argv[1]);
            return 2;
        }
        FYCaptureCardProbe *probe = [FYCaptureCardProbe new];
        probe.mode = mode;
        probe.input = [FYCaptureCardInput new];
        probe.frames = [NSMutableArray array];
        probe.status = [@{
            @"program": @"译芽采集卡探针",
            @"mode": mode,
            @"audio_inputs": @0,
            @"screen_capture_used": @NO,
            @"capture_started": @NO,
            @"permissions_requested": @NO,
            @"pid": @(getpid()),
            @"quicktime_running_at_start": @([probe quickTimeRunning]),
            @"obs_running_at_start": @([probe obsRunning]),
        } mutableCopy];
        if ([mode isEqualToString:@"capture"]) {
            if (argc >= 2 && argc != 5) { return 2; }
            probe.deviceName = argc >= 5 ? @(argv[3]) : request[@"device_name"];
            NSInteger frames = argc >= 5 ? atoi(argv[4]) : [request[@"frames"] integerValue];
            probe.wantedFrames = MAX(1, frames);
        } else if (argc >= 2 && argc != 3) {
            return 2;
        }
        NSString *directory = argc >= 3 ? @(argv[2]) : request[@"directory"];
        probe.directory = directory.length > 0 ? directory : defaultDirectory;
        if (!probe.directory.isAbsolutePath || !FYProbeDirectoryIsPrivate(probe.directory)) {
            fprintf(stderr, "输出目录必须是调用方创建的私有目录（0700）\n");
            return 2;
        }
        if (probe.wantedFrames > 0) { probe.status[@"wanted_frames"] = @(probe.wantedFrames); }
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if ([mode isEqualToString:@"inspect"]) { [probe runInspect]; }
        else if ([mode isEqualToString:@"authorize"]) { [probe runAuthorize]; }
        else { [probe runCapture]; }
        [application run];
    }
    return 0;
}
