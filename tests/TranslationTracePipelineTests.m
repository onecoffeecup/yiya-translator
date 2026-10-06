// Production timer + translation/cache/response pipeline, synthetic OCR and
// capture, in-memory HTTP completion. No NSApplication or real network.
#import "LearningAppTestSupport.h"
#import <objc/runtime.h>
#import <sys/stat.h>

static FYTranslationTrace *TestTrace;
static NSUInteger MockRequests;
static NSMutableArray *SubmittedSources;
static BOOL HoldResponse;
static void (^PendingResponse)(void);

@interface FYTranslationTrace (PipelineTest)
+ (instancetype)pipelineTestShared;
@end
@implementation FYTranslationTrace (PipelineTest)
+ (instancetype)pipelineTestShared { return TestTrace; }
@end

@interface TraceTask : NSObject
@property(copy) void (^response)(void);
- (void)resume;
- (void)cancel;
@end
@implementation TraceTask
- (void)resume { if (HoldResponse) { PendingResponse = self.response; } else { self.response(); } }
- (void)cancel {}
@end
@interface TraceSession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation TraceSession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    // Inspect only fictional test request body; never output or log credentials.
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    NSString *source = [body[@"messages"] lastObject][@"content"];
    [SubmittedSources addObject:source];
    MockRequests++;
    NSString *translated = [source hasPrefix:@"1. "] ? @"1. 测试界面" : [NSString stringWithFormat:@"测试译文%lu", (unsigned long)MockRequests];
    TraceTask *task = [TraceTask new];
    task.response = ^{ completion(Envelope(translated), Response(), nil); };
    return task;
}
@end
@interface FYTestURLSession (PipelineTest)
+ (id)pipelineTestSession;
@end
@implementation FYTestURLSession (PipelineTest)
+ (id)pipelineTestSession { return [TraceSession new]; }
@end

@interface TraceControl : NSObject
@property NSInteger state;
@property NSInteger selectedSegment;
@property(copy) NSString *stringValue;
@end
@implementation TraceControl
@end

@interface TracePipelineApp : AppDelegate
@property NSArray<OCRTextItem *> *fixture;
@property NSMutableArray *captions;
@property uint32_t fixtureWindowID;
@property NSInteger fixtureMode;
@property NSUInteger inlineApplies;
@end
@implementation TracePipelineApp
- (uint32_t)selectedWindowID { return self.fixtureWindowID; }
- (WindowItem *)selectedWindowItem { return nil; }
- (BOOL)autoContentModeEnabled { return NO; }
- (NSInteger)effectiveModeSegment { return self.fixtureMode; }
- (NSString *)systemPrompt { return @"TRACE_PRIVATE_PROMPT_SENTINEL"; }
- (void)updateRunState {}
- (void)setStatus:(NSString *)s {}
- (void)updatePreviewFromImage:(CGImageRef)i generation:(NSInteger)g {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)m {}
- (void)showError:(NSString *)s { Require(s.length == 0, @"unexpected pipeline error"); }
- (void)updateTranslationCount {}
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [self.captions addObject:text]; }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items { self.inlineApplies++; }
- (NSArray *)filteredInlineTextItems:(NSArray *)items strict:(BOOL)strict { return items; }
- (NSArray *)mergedInlineTextItemsFromItems:(NSArray *)items { return items; }
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)e {
    *blocks = self.fixture; return [[self.fixture valueForKey:@"text"] componentsJoinedByString:@"\n"];
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)b inImage:(CGImageRef)i normalizedExclusions:(NSArray<NSValue *> *)e { return b; }
@end

static TraceControl *TextControl(NSString *text) { TraceControl *c = [TraceControl new]; c.stringValue = text; return c; }
static TracePipelineApp *TraceApp(void) {
    TracePipelineApp *a = [TracePipelineApp new]; a.running = YES; a.fixtureWindowID = 42;
    a.captions = [NSMutableArray new]; a.inlineTranslationCache = [NSMutableDictionary new];
    TraceControl *stable = [TraceControl new]; stable.state = NSControlStateValueOn;
    TraceControl *fit = [TraceControl new]; fit.state = NSControlStateValueOff;
    a.stableTextCheckbox = (id)stable; a.autoFitRegionCheckbox = (id)fit;
    a.apiKeyField = (id)TextControl(@"TRACE_CREDENTIAL_SENTINEL");
    a.baseURLField = (id)TextControl(@"https://example.invalid/v1");
    a.modelField = (id)TextControl(@"test-model");
    a.realtimeModelField = (id)TextControl(@"test-model");
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    return a;
}
static NSArray *Fixture(NSString *text, CGFloat width) {
    OCRTextItem *item = [OCRTextItem new]; item.text = text; item.boundingBox = CGRectMake(.2, .2, width, .055);
    return @[item];
}
static void TraceCycle(TracePipelineApp *a, NSArray *fixture) {
    a.fixture = fixture; [a timerFired:nil]; Pump(^BOOL { return !a.inFlight; });
    Require(FYCurrentTrace() == nil, @"scoped context cannot leak after timer callback");
}
static TracePipelineApp *RunSequence(NSArray *full, NSArray *partial) {
    MockRequests = 0; SubmittedSources = [NSMutableArray new];
    TracePipelineApp *a = TraceApp();
    for (NSArray *f in @[full, full, partial, partial, full, full]) { TraceCycle(a, f); }
    return a;
}
static void ArmTrace(NSString *root) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *control = @{@"session": NSUUID.UUID.UUIDString, @"issued_at": @(now), @"expires_at": @(now + 120)};
    NSString *path = [root stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0600);
}
static NSArray *Records(NSString *log) {
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *records = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) { continue; }
        id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require(record != nil, @"valid JSONL"); [records addObject:record];
    }
    return records;
}
static NSUInteger Count(NSArray *records, NSString *event) {
    NSUInteger count = 0; for (NSDictionary *r in records) { if ([r[@"event"] isEqual:event]) { count++; } } return count;
}
int main(void) { @autoreleasepool {
    unsetenv("FUYI_DIAG");
    Require(![NSFileManager.defaultManager fileExistsAtPath:@"/tmp/fuyi-diag-armed"], @"legacy screenshot diagnostics must be off before tests");
    NSString *root = [FYTestTemporaryDirectory() stringByAppendingPathComponent:@"trace"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    TestTrace = [[FYTranslationTrace alloc] initWithDirectory:root clock:^{ return NSDate.date.timeIntervalSince1970; } maxBytes:1024 * 1024];
    method_exchangeImplementations(class_getClassMethod(FYTranslationTrace.class, @selector(shared)), class_getClassMethod(FYTranslationTrace.class, @selector(pipelineTestShared)));
    method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class, @selector(sharedSession)), class_getClassMethod(FYTestURLSession.class, @selector(pipelineTestSession)));
    NSString *log = [root stringByAppendingPathComponent:@"events.jsonl"];
    NSArray *full = Fixture(@"明日はみんなで図書館に行きましょう。", .65);
    NSArray *partial = Fixture(@"明日はみんなで", .31);
    TracePipelineApp *off = RunSequence(full, partial);
    NSArray *offSources = [SubmittedSources copy], *offCaptions = [off.captions copy];
    Require(MockRequests == 3 && ![NSFileManager.defaultManager fileExistsAtPath:log], @"disabled: same known three-request behavior and no log");
    ArmTrace(root);
    TracePipelineApp *on = RunSequence(full, partial);
    Require(MockRequests == 3 && [offSources isEqual:SubmittedSources] && [offCaptions isEqual:on.captions], @"trace must preserve requests and displayed outputs");
    NSArray *records = Records(log);
    Require(Count(records,@"request_submit") == 3 && Count(records,@"request_complete") == 3 && Count(records,@"caption_apply") == 3, @"real submit/response/apply call sites logged using mock transport");
    Require(Count(records,@"ocr") == 18 && Count(records,@"stable") == 6 && Count(records,@"mode") == 6, @"every synthetic OCR frame and stability decision logged");
    for (NSDictionary *submit in records) {
        if (![submit[@"event"] isEqual:@"request_submit"]) { continue; }
        BOOL response = NO, apply = NO;
        for (NSDictionary *r in records) {
            if (![r[@"request_id"] isEqual:submit[@"request_id"]]) { continue; }
            Require([r[@"cycle"] isEqual:submit[@"cycle"]] && [r[@"session"] isEqual:submit[@"session"]], @"same request stays in its cycle and session");
            response |= [r[@"event"] isEqual:@"request_complete"];
            apply |= [r[@"event"] isEqual:@"caption_apply"];
        }
        Require(response && apply, @"request completion and applied caption are linked");
    }
    TraceCycle(on, full);
    Require(MockRequests == 3, @"unchanged frame skips request");
    on.lastTranslatedNormalizedText = nil; on.lastSubmittedNormalizedText = nil;
    TraceCycle(on, full);
    Require(MockRequests == 3, @"cache hit does not submit another request");
    BOOL hit = NO, skipped = NO;
    for (NSDictionary *r in Records(log)) {
        hit |= [r[@"event"] isEqual:@"cache"] && [r[@"cache_hit"] boolValue];
        skipped |= [r[@"reason"] isEqual:@"same_as_last_translated"];
    }
    Require(hit && skipped, @"cache hit and unchanged skip are observable");
    TracePipelineApp *late = TraceApp();
    TraceCycle(late, full);
    HoldResponse = YES; late.fixture = full; [late timerFired:nil];
    Pump(^BOOL { return PendingResponse != nil; });
    late.fixtureWindowID = 43; PendingResponse(); PendingResponse = nil; HoldResponse = NO;
    Pump(^BOOL { return !late.inFlight; });
    Require(late.captions.count == 0, @"window change still drops response");
    BOOL dropped = NO;
    for (NSDictionary *r in Records(log)) { dropped |= [r[@"event"] isEqual:@"caption_drop"] && [r[@"reason"] isEqual:@"window_changed"]; }
    Require(dropped, @"window change reason logged");
    TracePipelineApp *ui = TraceApp(); ui.fixtureMode = ContentModeUI;
    TraceCycle(ui, Fixture(@"設定メニュー", .3));
    Pump(^BOOL { return ui.inlineApplies == 1; });
    Require(Count(Records(log), @"inline_apply") == 1, @"UI transition route can correlate inline application");
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    Require(![text containsString:@"TRACE_CREDENTIAL_SENTINEL"] && ![text containsString:@"TRACE_PRIVATE_PROMPT_SENTINEL"] && ![text containsString:@"Authorization"] && ![text containsString:@"example.invalid"], @"actual logging call sites exclude credential/prompt/header/URL");
    NSUInteger bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:@"control.json"] error:NULL];
    TraceCycle(on, partial); TraceCycle(on, partial);
    Require([[[NSFileManager defaultManager] attributesOfItemAtPath:log error:NULL] fileSize] == bytes, @"stop dynamically suppresses all pipeline writes");
    Require(NSApp == nil && FYCurrentTrace() == nil, @"no app UI and no leaked trace context");
    printf("PASS TranslationTracePipelineTests: off/on request parity=3; OCR/stability/cache/request/response/apply correlation; stale-window drop; inline route; credential exclusion; dynamic stop; synthetic capture and mock HTTP only\n");
} return 0; }
