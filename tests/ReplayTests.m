// Headless driver. Only input acquisition, Vision observations and HTTP are
// substituted; production timer, postprocessing, stability, identity, cache,
// request serialization, decoding and main-queue delivery remain in use.
#import "LearningAppTestSupport.h"
#import "FYTestCaptureCardInput.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <sys/stat.h>

static NSTimeInterval ReplayNow;
static NSDictionary *Scenario;
static FYTranslationTrace *ReplayTrace;
static NSMutableArray *Tasks, *Sources, *DirectResults;
static NSUInteger Assertions, StepIndex;
static NSDictionary *Failure;

static void CheckReplay(BOOL ok, NSString *message, id expected, id actual) {
    Assertions++;
    if (!ok) {
        Failure = @{@"step": @(StepIndex), @"message": message,
                    @"expected": expected ?: NSNull.null, @"actual": actual ?: NSNull.null};
        @throw [NSException exceptionWithName:@"ReplayFailure" reason:message userInfo:nil];
    }
}
static void ReplayPump(BOOL (^done)(void)) {
    // First Vision invocation may initialize its models. Text-only scenes keep
    // the shorter deadline; media fixtures explicitly allow that cold start.
    NSTimeInterval timeout=Scenario[@"callback_timeout_ms"] ? [Scenario[@"callback_timeout_ms"] doubleValue]/1000 : 5;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    }
    CheckReplay(done(), @"异步任务未在场景的回调期限内达到检查点", @YES, @NO);
}
static void MainBarrier(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    ReplayPump(^BOOL { return done; });
}

@interface ReplayTask : NSObject
@property(copy) void (^completion)(NSData *, NSURLResponse *, NSError *);
@property NSDictionary *spec;
@property NSURL *url;
@property BOOL resumed, completed;
@property NSUInteger cancelCalls;
- (void)resume;
- (void)cancel;
- (void)fire;
@end
@implementation ReplayTask
- (void)resume { self.resumed = YES; }
// Deliver even after cancellation: a result may already be queued. Production
// generation/epoch checks must reject it rather than trusting cancellation.
- (void)cancel { self.cancelCalls++; }
- (void)fire {
    CheckReplay(self.resumed && !self.completed, @"响应只能释放一次且必须已经提交", @YES, @NO);
    self.completed = YES;
    NSError *error = self.spec[@"error_code"] ? [NSError errorWithDomain:NSURLErrorDomain
        code:[self.spec[@"error_code"] integerValue] userInfo:nil] : nil;
    NSData *data = self.spec[@"raw_body"] ? [self.spec[@"raw_body"] dataUsingEncoding:NSUTF8StringEncoding]
        : Envelope(self.spec[@"translation"] ?: @"");
    NSHTTPURLResponse *response = error ? nil : [[NSHTTPURLResponse alloc] initWithURL:self.url
        statusCode:self.spec[@"status"] ? [self.spec[@"status"] integerValue] : 200
        HTTPVersion:@"HTTP/1.1" headerFields:nil];
    self.completion(data, response, error);
}
@end
@interface ReplaySession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation ReplaySession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    NSString *source = [payload[@"messages"] lastObject][@"content"] ?: @"";
    NSUInteger index = Sources.count;
    [Sources addObject:source];
    NSArray *responses = Scenario[@"responses"];
    CheckReplay(index < responses.count, @"生产链路产生了没有 mock 的额外请求", @(responses.count), @(index + 1));
    NSDictionary *spec = responses[index];
    if (spec[@"source"]) { CheckReplay([spec[@"source"] isEqual:source], @"请求原文不符合预期", spec[@"source"], source); }
    ReplayTask *task = [ReplayTask new]; task.spec = spec; task.completion = completion; task.url = request.URL;
    [Tasks addObject:task]; return task;
}
@end
@interface FYTestURLSession (Replay)
+ (id)replaySession;
@end
@implementation FYTestURLSession (Replay)
+ (id)replaySession { return [ReplaySession new]; }
@end
@interface FYTranslationTrace (Replay)
+ (id)replayShared;
@end
@implementation FYTranslationTrace (Replay)
+ (id)replayShared { return ReplayTrace; }
@end

@interface ReplayControl : NSObject
@property NSInteger state, selectedSegment;
@property double doubleValue;
@property(copy) NSString *stringValue;
@end
@implementation ReplayControl
@end

@interface ReplayApp : AppDelegate
@property NSArray *observations;
@property NSMutableArray *captions, *inlineOutputs;
@property uint32_t fixtureWindow;
@property NSInteger fixtureMode;
@property BOOL automaticMode, useVision, captureFailed;
@property NSUInteger ocrCalls, frameIndex, errorCount;
@property NSInteger ocrError;
@property CGRect fixtureScope;
@end
@implementation ReplayApp
- (uint32_t)selectedWindowID { return self.fixtureWindow; }
- (uint32_t)displayTargetWindowID { return self.fixtureWindow; }
- (BOOL)captureCardInputEnabled { return [Scenario[@"source"] isEqual:@"capture_card"]; }
- (BOOL)autoContentModeEnabled { return self.automaticMode; }
- (NSInteger)effectiveModeSegment { return self.automaticMode ? [super effectiveModeSegment] : self.fixtureMode; }
- (NSInteger)stableContentModeForBlocks:(NSArray *)blocks {
    return self.automaticMode ? [super stableContentModeForBlocks:blocks] : self.fixtureMode;
}
- (CGRect)selectedOCRScope { return self.fixtureScope; }
- (NSDate *)translationProcessingDate { return [NSDate dateWithTimeIntervalSince1970:1000 + ReplayNow]; }
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)window {
    return self.captureFailed ? NULL : [super copyFullCapturedImageForWindow:window];
}
- (NSArray *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fast languageSegment:(NSInteger)language error:(NSError **)error {
    self.ocrCalls++;
    if (self.ocrError) { if (error) *error = [NSError errorWithDomain:@"ReplayOCR" code:self.ocrError userInfo:nil]; return @[]; }
    if (self.useVision) { return [super recognizeTextItemsInImage:image fastOCR:fast languageSegment:language error:error]; }
    return self.observations;
}
// Terminal UI boundary: record exactly what production would hand to AppKit.
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [self.captions addObject:text ?: @""]; }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items placementRect:(NSRect)rect {
    [self.inlineOutputs addObject:@{@"sources": [items valueForKey:@"text"], @"translations": translations}];
    self.lastInlineRenderedItems = items;
}
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items {
    [self showInlineTranslations:translations forItems:items placementRect:NSMakeRect(0,0,800,600)];
}
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason { if (rect) *rect = NSMakeRect(0,0,800,600); return YES; }
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force {}
- (BOOL)recoverWindowSelectionIfRecreated { return NO; }
- (void)updateRuntimeDiagnostics {}
- (void)updateRunState {}
- (void)setStatus:(NSString *)status {}
- (void)showError:(NSString *)error { if (error.length) self.errorCount++; }
- (void)showPreviewUnavailable:(NSString *)message {}
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation {}
- (void)updateCaptureCardStatus {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)updateTranslationCount {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)mode {}
@end

static ReplayControl *Control(NSString *text, BOOL on) {
    ReplayControl *value = [ReplayControl new]; value.stringValue = text; value.state = on; return value;
}
static ReplayApp *NewApp(void) {
    ReplayApp *a = [ReplayApp new]; a.fixtureWindow = 42; a.running = YES;
    a.fixtureMode = [Scenario[@"mode"] isEqual:@"ui"] ? ContentModeUI : ContentModeDialogue;
    a.detectedModeSegment = a.fixtureMode; a.automaticMode = [Scenario[@"auto_mode"] boolValue];
    a.fixtureScope = CGRectMake(0,0,1,1);
    if (Scenario[@"scope"]) { NSArray *s=Scenario[@"scope"]; a.fixtureScope=CGRectMake([s[0] doubleValue],[s[1] doubleValue],[s[2] doubleValue],[s[3] doubleValue]); }
    a.captions = [NSMutableArray new]; a.inlineOutputs = [NSMutableArray new];
    a.inlineTranslationCache = [NSMutableDictionary new];
    a.stableTextCheckbox = (id)Control(@"", Scenario[@"stable"] ? [Scenario[@"stable"] boolValue] : YES);
    a.autoFitRegionCheckbox = (id)Control(@"", [Scenario[@"auto_fit"] boolValue]);
    a.languageControl = (id)Control(@"", NO);
    ((ReplayControl *)(id)a.languageControl).selectedSegment = [Scenario[@"language"] isEqual:@"en"] ? 1 : 0;
    a.apiKeyField = (id)Control(@"REPLAY_SYNTHETIC_CREDENTIAL", NO);
    a.baseURLField = (id)Control(@"https://replay.invalid/v1", NO);
    a.modelField = (id)Control(@"replay-model", NO); a.realtimeModelField = (id)Control(@"replay-model", NO);
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    FYTestCaptureCardInput *input = [FYTestCaptureCardInput new];
    FYTestCaptureCardDevice *device = [FYTestCaptureCardDevice new]; device.uniqueID=@"replay-device"; device.displayName=@"Replay";
    input.testDevices = @[device]; input.testAvailability = FYCaptureCardAvailabilityAuthorized;
    a.captureCardInput = input;
    if ([a captureCardInputEnabled]) [input startWithDeviceUniqueID:device.uniqueID];
    return a;
}
static NSArray *ReadTrace(NSString *directory) {
    NSString *text = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:@"events.jsonl"] encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *events = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        id event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        CheckReplay(event != nil, @"诊断 JSONL 损坏", @YES, @NO); [events addObject:event];
    }
    return events;
}
static BOOL HasPending(void) {
    for (ReplayTask *task in Tasks) if (task.resumed && !task.completed) return YES;
    return NO;
}
static void ReleaseDue(void) {
    for (ReplayTask *task in [Tasks copy]) {
        if (task.resumed && !task.completed && ![task.spec[@"hold"] boolValue] &&
            [task.spec[@"release_at_ms"] doubleValue] <= ReplayNow * 1000) [task fire];
    }
}
static void Settle(ReplayApp *app) {
    ReplayPump(^BOOL { ReleaseDue(); return !app.inFlight || HasPending(); });
    // Flush nested main dispatches, including inline application, without a sleep.
    MainBarrier(); ReleaseDue(); MainBarrier(); MainBarrier();
}
static NSDictionary *Snapshot(ReplayApp *app, NSString *traceDirectory) {
    NSMutableArray *pending = [NSMutableArray new]; NSUInteger cancelled = 0;
    for (NSUInteger index=0; index<Tasks.count; index++) {
        ReplayTask *task=Tasks[index]; if (!task.completed) [pending addObject:@(index)]; cancelled+=task.cancelCalls;
    }
    NSMutableArray *reasons=[NSMutableArray new], *drops=[NSMutableArray new];
    NSMutableDictionary *counts=[NSMutableDictionary new];
    for (NSDictionary *event in ReadTrace(traceDirectory)) {
        NSString *name=event[@"event"]; counts[name]=@([counts[name] unsignedIntegerValue]+1);
        if (event[@"reason"]) [reasons addObject:event[@"reason"]];
        if ([name hasSuffix:@"_drop"]) [drops addObject:event[@"reason"] ?: @""];
    }
    return @{@"requests": @(Sources.count), @"sources": Sources, @"captions": app.captions,
        @"inline": app.inlineOutputs, @"errors": @(app.errorCount), @"in_flight": @(app.inFlight),
        @"pending": pending, @"cancel_calls": @(cancelled), @"ocr_calls": @(app.ocrCalls),
        @"mode": @([app effectiveModeSegment]), @"reasons": reasons, @"drops": drops,
        @"events": counts, @"direct_results": DirectResults};
}
static CGImageRef FrameImage(NSDictionary *step, NSString *base) {
    if (step[@"image"]) {
        NSString *path=[step[@"image"] isAbsolutePath] ? step[@"image"] : [base stringByAppendingPathComponent:step[@"image"]];
        NSData *data=[NSData dataWithContentsOfFile:path];
        CGImageSourceRef source=data ? CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL) : NULL;
        CGImageRef image=source ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
        if(source) CFRelease(source); return image;
    }
    if (step[@"video"]) {
        NSString *path=[step[@"video"] isAbsolutePath] ? step[@"video"] : [base stringByAppendingPathComponent:step[@"video"]];
        AVAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        AVAssetImageGenerator *generator=[[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform=YES;
        generator.requestedTimeToleranceBefore=kCMTimeZero; generator.requestedTimeToleranceAfter=kCMTimeZero;
        return [generator copyCGImageAtTime:CMTimeMakeWithSeconds([step[@"video_ms"] doubleValue]/1000,600)
            actualTime:NULL error:NULL];
    }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,800,600,8,3200,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space); if(!ctx) return NULL;
    CGContextSetRGBFillColor(ctx,1,1,1,1); CGContextFillRect(ctx,CGRectMake(0,0,800,600));
    CGImageRef image=CGBitmapContextCreateImage(ctx); CGContextRelease(ctx); return image;
}
static void ApplyFrame(ReplayApp *app, NSDictionary *step, NSString *base) {
    app.captureFailed=[step[@"capture_failed"] boolValue]; app.ocrError=[step[@"ocr_error"] integerValue];
    app.useVision=(step[@"image"] || step[@"video"]) && !step[@"blocks"] && !step[@"text"];
    NSMutableArray *items=[NSMutableArray new];
    NSArray *blocks=step[@"blocks"] ?: (step[@"text"] ? @[@{@"text": step[@"text"], @"box": @[@.2,@.2,@.65,@.055]}] : @[]);
    for (NSDictionary *block in blocks) {
        OCRTextItem *item=[OCRTextItem new]; item.text=block[@"text"]; item.confidence=1;
        NSArray *b=block[@"box"]; item.boundingBox=CGRectMake([b[0] doubleValue],[b[1] doubleValue],[b[2] doubleValue],[b[3] doubleValue]);
        [items addObject:item];
    }
    app.observations=items;
    CGImageRef image=FrameImage(step,base);
    CheckReplay(image!=NULL,@"不能读取回放图片或指定视频帧",@YES,@NO);
    FYTestSetWindowImage(image);
    if ([app captureCardInputEnabled] && !app.captureFailed) {
        [(FYTestCaptureCardInput *)app.captureCardInput testStoreFrame:image index:++app.frameIndex];
    }
    CGImageRelease(image); [app timerFired:nil]; Settle(app);
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc!=3) { fprintf(stderr,"Usage: ReplayTests scenario.json result.json\n"); return 2; }
    NSString *path=@(argv[1]), *output=@(argv[2]);
    Scenario=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
    if (![Scenario isKindOfClass:NSDictionary.class] || [Scenario[@"schema_version"] intValue]!=1) return 2;
    Tasks=[NSMutableArray new]; Sources=[NSMutableArray new]; DirectResults=[NSMutableArray new];
    NSString *directory=[FYTestTemporaryDirectory() stringByAppendingPathComponent:@"replay-trace"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    ReplayTrace=[[FYTranslationTrace alloc] initWithDirectory:directory clock:^{return 1000+ReplayNow;} maxBytes:1024*1024];
    if (![Scenario[@"trace_disabled"] boolValue]) {
        NSDictionary *control=@{@"session":NSUUID.UUID.UUIDString,@"issued_at":@1000,@"expires_at":@1300};
        NSString *controlPath=[directory stringByAppendingPathComponent:@"control.json"];
        [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:controlPath atomically:YES]; chmod(controlPath.fileSystemRepresentation,0600);
    }
    method_exchangeImplementations(class_getClassMethod(FYTranslationTrace.class,@selector(shared)),class_getClassMethod(FYTranslationTrace.class,@selector(replayShared)));
    method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class,@selector(sharedSession)),class_getClassMethod(FYTestURLSession.class,@selector(replaySession)));
    ReplayApp *app=NewApp(); NSMutableArray *checkpoints=[NSMutableArray new]; BOOL passed=NO;
    @try {
        for (NSDictionary *step in Scenario[@"steps"]) {
            ReplayNow=[step[@"at_ms"] doubleValue]/1000; NSString *action=step[@"action"];
            ReleaseDue(); MainBarrier(); MainBarrier();
            if ([action isEqual:@"frame"]) ApplyFrame(app,step,path.stringByDeletingLastPathComponent);
            else if ([action isEqual:@"tick"]) { [app timerFired:nil]; Settle(app); }
            else if ([action isEqual:@"advance"]) Settle(app);
            else if ([action isEqual:@"release"]) {
                NSUInteger index=[step[@"request"] unsignedIntegerValue];
                CheckReplay(index<Tasks.count,@"要释放的请求不存在",@(Tasks.count),@(index));
                [(ReplayTask *)Tasks[index] fire]; Settle(app);
            } else if ([action isEqual:@"window"]) app.fixtureWindow=[step[@"window_id"] unsignedIntValue];
            else if ([action isEqual:@"mode"]) app.fixtureMode=[step[@"mode"] isEqual:@"ui"] ? ContentModeUI : ContentModeDialogue;
            else if ([action isEqual:@"disconnect"]) [(FYTestCaptureCardInput *)app.captureCardInput testDisconnectActiveDevice];
            else if ([action isEqual:@"connect"]) [(FYTestCaptureCardInput *)app.captureCardInput startWithDeviceUniqueID:@"replay-device"];
            else if ([action isEqual:@"restart"]) {
                [app stop]; app.running=YES; app.translationGeneration++;
                [[app translationState] reset]; [[app stabilityOwner] reset];
                if ([app captureCardInputEnabled]) [(FYTestCaptureCardInput *)app.captureCardInput startWithDeviceUniqueID:@"replay-device"];
            } else if ([action isEqual:@"cache_probe"]) {
                // Same production gate retry, used to prove identity-cache reuse.
                app.lastTranslatedNormalizedText=nil; app.lastSubmittedNormalizedText=nil;
            } else if ([action isEqual:@"translate"]) {
                [app translateText:step[@"text"] completion:^(NSString *text,NSError *error) {
                    [DirectResults addObject:@{@"translation":text ?: @"",@"error_code":@(error.code)}];
                }]; Settle(app);
            } else CheckReplay(NO,@"未知回放动作",@"documented action",action);
            MainBarrier(); MainBarrier();
            NSDictionary *actual=Snapshot(app,directory);
            // Freeze containers so subsequent frames cannot mutate prior evidence.
            NSData *json=[NSJSONSerialization dataWithJSONObject:actual options:0 error:NULL];
            actual=[NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
            [checkpoints addObject:@{@"step":@(StepIndex),@"at_ms":step[@"at_ms"],@"actual":actual}];
            for (NSString *key in step[@"expect"]) {
                id expected=step[@"expect"][key];
                if ([key isEqual:@"has_reason"]) CheckReplay([actual[@"reasons"] containsObject:expected],@"诊断缺少预期原因",expected,actual[@"reasons"]);
                else if ([key isEqual:@"caption_contains"]) CheckReplay([[actual[@"captions"] lastObject] containsString:expected],@"字幕缺少预期子串",expected,[actual[@"captions"] lastObject]);
                else CheckReplay([expected isEqual:actual[key]],[NSString stringWithFormat:@"检查点字段 %@ 不符合预期",key],expected,actual[key]);
            }
            StepIndex++;
        }
        CheckReplay(Sources.count==[Scenario[@"responses"] count],@"mock 响应未全部使用",@([Scenario[@"responses"] count]),@(Sources.count));
        CheckReplay(!HasPending() && !app.inFlight,@"回放结束仍有未完成任务",@NO,@YES);
        if (![Scenario[@"trace_disabled"] boolValue]) {
            NSMutableSet *httpIDs=[NSMutableSet new];
            for (NSDictionary *event in ReadTrace(directory)) {
                if ([event[@"event"] isEqual:@"request_submit"]) {
                    NSString *httpID=event[@"http_task_id"];
                    CheckReplay(httpID && ![httpIDs containsObject:httpID],@"每个实际 HTTP 提交必须有独立身份",@YES,@NO);
                    [httpIDs addObject:httpID];
                }
            }
            NSString *log=[NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:@"events.jsonl"] encoding:NSUTF8StringEncoding error:NULL];
            CheckReplay(![log containsString:@"REPLAY_SYNTHETIC_CREDENTIAL"] && ![log containsString:@"replay.invalid"],@"诊断不得包含凭据或接口地址",@YES,@NO);
        }
        CheckReplay(NSApp==nil && FYCurrentTrace()==nil,@"回放不能创建应用窗口或泄漏诊断上下文",@YES,@NO);
        passed=YES;
    } @catch(NSException *exception) {
        if (!Failure) Failure=@{@"step":@(StepIndex),@"message":@"回放出现原生异常",@"exception":exception.name};
    }
    NSDictionary *report=@{@"schema_version":@1,@"scenario":Scenario[@"name"] ?: @"Replay",
        @"status":passed ? @"passed" : @"failed",@"assertions":@(Assertions),@"checkpoints":checkpoints,
        @"failure":Failure ?: NSNull.null,@"trace_path":[directory stringByAppendingPathComponent:@"events.jsonl"],
        @"scope":@"headless production pipeline; synthetic credentials; no real network/device/UI"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    if (![data writeToFile:output atomically:YES]) { fprintf(stderr,"Cannot write Replay result\n"); return 2; }
    chmod(output.fileSystemRepresentation,0600); FYTestSetWindowImage(NULL);
    printf("%s Replay: %lu checkpoints, %lu assertions; real API calls=0; device/UI=not_run\n",passed ? "PASS" : "FAIL",(unsigned long)checkpoints.count,(unsigned long)Assertions);
    return passed ? 0 : 1;
} }
