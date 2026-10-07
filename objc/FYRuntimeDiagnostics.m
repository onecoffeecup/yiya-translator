#import "FYRuntimeDiagnostics.h"
#import <math.h>

static const NSTimeInterval FYDiagnosticRetention = 300;

static NSDictionary *FYDiagnosticNumbers(NSDictionary *input, NSArray<NSString *> *keys) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = input[key];
        if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) { result[key] = value; }
    }
    return result;
}

static NSString *FYDiagnosticRole(id role) {
    return [@[@"yiya", @"quicktime", @"obs", @"other", @"unknown"] containsObject:role ?: @""] ? role : @"unknown";
}

@interface FYRuntimeDiagnostics ()
@property(nonatomic, copy) NSTimeInterval (^clock)(void);
@property(nonatomic) NSUInteger capacity;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *events;
@property(nonatomic) NSUInteger discarded;
@end

@implementation FYRuntimeDiagnostics
+ (instancetype)shared {
    static FYRuntimeDiagnostics *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] initWithClock:^{ return NSDate.date.timeIntervalSince1970; } capacity:600]; });
    return instance;
}
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock capacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _clock = [clock copy];
        _capacity = MIN(MAX(capacity, 1), 600);
        _events = [NSMutableArray array];
    }
    return self;
}
- (void)prune {
    NSTimeInterval oldest = self.clock() - FYDiagnosticRetention;
    while (self.events.count && [self.events.firstObject[@"time_unix_ms"] doubleValue] < oldest * 1000) {
        [self.events removeObjectAtIndex:0];
        self.discarded++;
    }
}
- (void)recordEvent:(NSString *)event fields:(NSDictionary *)fields {
    if (![@[@"window_check", @"selection", @"start", @"stop", @"cycle", @"capture", @"ocr", @"http", @"translation", @"caption", @"export"] containsObject:event]) { return; }
    NSMutableDictionary *record = [FYDiagnosticNumbers(fields, @[@"window_id", @"display_window_id", @"generation", @"input_source", @"running", @"screen_permission", @"raw_windows", @"candidate_windows", @"own_windows", @"external_windows", @"success", @"blocks", @"width", @"height", @"elapsed_ms", @"error_code", @"http_status", @"visible", @"frame_index"]) mutableCopy];
    if (fields[@"window_role"]) { record[@"window_role"] = FYDiagnosticRole(fields[@"window_role"]); }
    record[@"event"] = event;
    @synchronized (self) {
        record[@"time_unix_ms"] = @(llround(self.clock() * 1000));
        [self prune];
        if (self.events.count >= self.capacity) { [self.events removeObjectAtIndex:0]; self.discarded++; }
        [self.events addObject:[record copy]];
    }
}
- (NSArray<NSDictionary *> *)recentEvents {
    @synchronized (self) { [self prune]; return [self.events copy]; }
}
+ (NSDictionary *)sanitizeSnapshot:(NSDictionary *)snapshot {
    NSMutableDictionary *result = [FYDiagnosticNumbers(snapshot, @[@"screen_permission", @"input_source", @"running", @"in_flight", @"generation", @"selected_window_id", @"display_window_id", @"selected_is_self", @"selected_exists", @"raw_windows", @"candidate_windows", @"own_windows", @"external_windows", @"quicktime_running", @"quicktime_windows", @"screen_count", @"camera_authorized", @"capture_running", @"translated_process"]) mutableCopy];
    // System values only, provided by NSBundle / NSProcessInfo / uname; never settings.
    for (NSString *key in @[@"app_version", @"app_build", @"macos_version", @"architecture"]) {
        id value = snapshot[key];
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_- "];
        if ([value isKindOfClass:NSString.class] && [value length] <= 64 &&
            [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) { result[key] = [value copy]; }
    }
    result[@"selected_role"] = FYDiagnosticRole(snapshot[@"selected_role"]);
    NSMutableArray *windows = [NSMutableArray array];
    NSArray *raw = [snapshot[@"windows"] isKindOfClass:NSArray.class] ? snapshot[@"windows"] : @[];
    for (id input in raw) {
        if (windows.count >= 100) { break; }
        if (![input isKindOfClass:NSDictionary.class]) { continue; }
        NSMutableDictionary *window = [FYDiagnosticNumbers(input, @[@"window_id", @"pid", @"layer", @"x", @"y", @"width", @"height", @"candidate", @"is_self", @"owner_present", @"title_present"]) mutableCopy];
        window[@"role"] = FYDiagnosticRole(input[@"role"]);
        [windows addObject:[window copy]];
    }
    result[@"windows"] = windows;
    result[@"window_list_truncated"] = @(raw.count > 100);
    return result;
}
+ (NSArray<NSDictionary *> *)findingsForSnapshot:(NSDictionary *)raw events:(NSArray<NSDictionary *> *)events {
    NSDictionary *s = [self sanitizeSnapshot:raw];
    NSMutableArray *findings = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSString *) = ^(NSString *code, NSString *level, NSString *message) {
        [findings addObject:@{@"code": code, @"level": level, @"message": message}];
    };
    BOOL card = [s[@"input_source"] integerValue] == 1;
    if ([s[@"selected_is_self"] boolValue]) {
        add(@"self_selected", @"error", @"选中了译芽自身窗口。请刷新窗口列表，选择 QuickTime 的游戏画面。");
    }
    if (!card && ![s[@"screen_permission"] boolValue]) {
        add(@"screen_permission_missing", @"error", @"屏幕录制权限未对当前进程生效。请打开权限设置，允许译芽后完全退出并重新打开。");
    }
    if ([s[@"external_windows"] integerValue] == 0 && [s[@"own_windows"] integerValue] > 0) {
        add(@"only_self_visible", @"warning", @"目前只能列出译芽自己的窗口。请检查权限，并让 QuickTime 的画面窗口保持在当前桌面、不要最小化。");
    } else if ([s[@"candidate_windows"] integerValue] == 0) {
        add(@"no_candidates", @"warning", @"当前没有可选择的画面窗口。请打开 QuickTime 的视频画面，退出全屏或最小化后刷新。");
    }
    if ([s[@"quicktime_running"] boolValue] && [s[@"quicktime_windows"] integerValue] == 0) {
        add(@"quicktime_not_visible", @"warning", @"QuickTime 正在运行，但当前列表没有它的画面窗口。请检查它是否在其他桌面或已经最小化。");
    }
    if (![s[@"selected_window_id"] unsignedIntValue]) {
        add(@"no_selection", @"warning", @"尚未选择画面窗口。请在画面来源中选择 QuickTime／OBS 或游戏窗口。");
    } else if (![s[@"selected_exists"] boolValue]) {
        add(@"selected_window_missing", @"error", @"选中的窗口当前不可见或已经关闭。请回到目标画面，再刷新并重新选择。");
    }
    if (card && ![s[@"camera_authorized"] boolValue]) {
        add(@"camera_permission_missing", @"error", @"采集卡需要相机权限。请点开始翻译并允许访问，或打开相机权限设置。");
    }
    // Only diagnose the latest result in the current target/generation, so an old
    // failure cannot override a subsequent success or a different window.
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        NSString *kind = event[@"event"];
        if (![@[@"capture", @"ocr", @"http", @"translation"] containsObject:kind] || [seen containsObject:kind]) { continue; }
        if (event[@"window_id"] && [event[@"window_id"] unsignedIntValue] != [s[@"display_window_id"] unsignedIntValue]) { continue; }
        if (event[@"generation"] && s[@"generation"] && ![event[@"generation"] isEqual:s[@"generation"]]) { continue; }
        [seen addObject:kind];
        if ([kind isEqual:@"capture"] && ![event[@"success"] boolValue]) {
            add(@"capture_failed", @"error", @"最近一次窗口截图失败。请检查目标窗口是否仍打开，以及屏幕录制权限是否生效。");
        } else if ([kind isEqual:@"ocr"] && [event[@"error_code"] integerValue] != 0) {
            add(@"ocr_failed", @"error", @"最近一次文字识别出错。请导出诊断包，将错误码交给开发者检查。");
        } else if ([kind isEqual:@"ocr"] && [event[@"blocks"] integerValue] == 0) {
            add(@"ocr_empty", @"warning", @"最近一帧没有识别到文字。请检查预览画面、识别区域和原文语言。");
        } else if ([kind isEqual:@"http"] && ([event[@"error_code"] integerValue] != 0 || [event[@"http_status"] integerValue] >= 400)) {
            add(@"translation_request_failed", @"error", @"最近一次翻译请求失败。请在翻译服务中测试连接；诊断包会保留状态码，不包含密钥。");
        } else if ([kind isEqual:@"translation"] && ![event[@"success"] boolValue]) {
            add(@"translation_result_failed", @"error", @"最近一次翻译没有得到有效结果。请测试翻译服务，并导出诊断包供开发者检查。");
        }
    }
    if (!findings.count) { add(@"no_obvious_issue", @"info", @"未发现明显的权限或窗口配置问题；这不代表实际识别和翻译已经通过验证。"); }
    return findings;
}
- (NSDictionary *)reportForSnapshot:(NSDictionary *)snapshot {
    @synchronized (self) {
        NSDictionary *safe = [self.class sanitizeSnapshot:snapshot];
        NSArray *events = [self recentEvents];
        return @{@"format": @"yiya-diagnostics", @"schema_version": @1,
                 @"report_id": NSUUID.UUID.UUIDString, @"created_unix_ms": @(llround(self.clock() * 1000)),
                 @"retention_seconds": @(FYDiagnosticRetention), @"event_limit": @(self.capacity),
                 @"discarded_events": @(self.discarded), @"snapshot": safe, @"events": events,
                 @"findings": [self.class findingsForSnapshot:safe events:events],
                 @"privacy": @"不包含截图、台词、译文、窗口标题、API Key、接口地址、用户设置或学习数据库。仅由用户导出后自行发送。"};
    }
}
+ (BOOL)writeReport:(NSDictionary *)report toURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!data) { return NO; }
    // NSSavePanel chooses the destination. Atomic replacement avoids partial reports.
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}
@end
