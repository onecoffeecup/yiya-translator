#import "settings/FYSettingsStore.h"
#import "settings/FYServiceTestController.h"
#import "diagnostics/FYDiagnosticsController.h"
#import "FYLocalAPIKeyStore.h"
#import "FYRuntimeDiagnostics.h"
#import <Cocoa/Cocoa.h>

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(2); }
}
static void Pump(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!done() && limit.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    Check(done(), @"isolated callback completes");
}
static void DrainMain(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    Pump(^BOOL { return done; });
}

// Synthetic cancellation handle; no session or network task is created.
@interface ExtractionTask : NSObject
@property(nonatomic) NSUInteger cancelCalls;
@end
@implementation ExtractionTask
- (void)cancel { self.cancelCalls++; }
@end

static void Settings(void) {
    FYTestDefaults *defaults = [FYTestDefaults new];
    NSMutableString *model = [@"draft-model" mutableCopy];
    NSMutableDictionary *drafts = [@{@"custom":model} mutableCopy];
    NSMutableDictionary *values = [@{@"providerModels":drafts, @"apiKey":@"synthetic-old-key", @"language":@1} mutableCopy];
    FYSettingsSnapshot *frozen = [[FYSettingsSnapshot alloc] initWithValues:values];
    [model setString:@"changed"]; drafts[@"other"] = @"new"; values[@"language"] = @0;
    Check([frozen.values[@"providerModels"][@"custom"] isEqual:@"draft-model"] && !frozen.values[@"providerModels"][@"other"], @"nested preferences freeze independently of input drafts");
    Check([frozen.values[@"language"] isEqual:@1] && !frozen.values[@"apiKey"], @"ordinary snapshots exclude credentials");
    [defaults setObject:@{@"apiKey":@"synthetic-legacy-key", @"model":@"saved-model"} forKey:SettingsKey];
    FYTestLocalAPIKeyValue = @"synthetic-local-key";
    FYSettingsStore *store = [[FYSettingsStore alloc] initWithDefaults:(id)defaults];
    FYSettingsSnapshot *loaded = [store load];
    Check([store.persistedAPIKey isEqual:@"synthetic-local-key"] && !store.credentialLoadFailed, @"separate production unit sees the shared isolated credential");
    Check(![defaults objectForKey:SettingsKey][@"apiKey"] && [loaded.values[@"model"] isEqual:@"saved-model"], @"legacy credential removed while ordinary settings survive");
    NSDictionary *before = [defaults objectForKey:SettingsKey];
    FYTestLocalAPIKeyFailWrites = YES;
    Check([store saveSnapshot:frozen apiKey:@"synthetic-replacement-key"] == FYSettingsCredentialWriteFailed, @"credential write failure is reported");
    Check([[defaults objectForKey:SettingsKey] isEqual:before] && [store.persistedAPIKey isEqual:@"synthetic-local-key"] && [FYTestLocalAPIKeyValue isEqual:@"synthetic-local-key"], @"failed write preserves prior preferences and credential");
    Check([store saveSnapshot:frozen apiKey:@"synthetic-local-key"] == FYSettingsSaved, @"unchanged credential does not require a write");
    FYTestLocalAPIKeyFailWrites = NO;
    Check([store saveSnapshot:frozen apiKey:@""] == FYSettingsSaved && !FYTestLocalAPIKeyValue, @"explicit clear removes the isolated credential");
    store.credentialLoadFailed = YES;
    Check([store saveSnapshot:loaded apiKey:@"synthetic-new-key"] == FYSettingsCredentialReadBlocked && !FYTestLocalAPIKeyValue, @"read failure blocks later writes");
    NSMutableString *url = [@"https://example.invalid/v1" mutableCopy];
    FYTranslationConfiguration *config = [[FYTranslationConfiguration alloc] initWithBaseURL:url model:@"one-model" learningModel:nil apiKey:@"synthetic-key"];
    [url setString:@"https://changed.invalid"];
    Check([config.baseURL isEqual:@"https://example.invalid/v1"] && [config.model isEqual:@"one-model"] && config.learningModel.length == 0, @"request configuration is copied independently of mutable fields");
    __block NSUInteger saves = 0;
    store.loading = YES; [store scheduleSave:^{ saves++; }];
    Check(!store.saveTimer, @"loading does not schedule a save");
    store.loading = NO;
    [store scheduleSave:^{ saves += 10; }]; NSTimer *old = store.saveTimer;
    [store scheduleSave:^{ saves++; }];
    Check(!old.valid, @"replacing a save cancels its previous timer");
    Pump(^BOOL { return saves > 0; });
    Check(saves == 1 && !store.saveTimer, @"debounced save fires only the latest callback");
    [store scheduleSave:^{ saves++; }]; old = store.saveTimer; [store cancelScheduledSave];
    Check(!old.valid && !store.saveTimer, @"explicit save/stop can cancel pending work");
    __weak FYSettingsStore *released;
    @autoreleasepool {
        FYSettingsStore *temporary = [[FYSettingsStore alloc] initWithDefaults:(id)defaults];
        [temporary scheduleSave:^{ saves++; }]; old = temporary.saveTimer; released = temporary;
    }
    Check(!released && !old.valid, @"save timer does not retain a closed settings owner");
}

static void ServiceTests(void) {
    FYServiceTestController *controller = [FYServiceTestController new];
    controller.taskOwner = [FYTranslationTaskOwner new];
    __block BOOL running = NO;
    __block void (^firstReply)(NSString *, NSError *);
    __block void (^secondReply)(NSString *, NSError *);
    __block NSUInteger results = 0;
    __block NSString *lastStatus;
    __block NSString *lastResult;
    ExtractionTask *first = [ExtractionTask new], *second = [ExtractionTask new];
    FYServiceTestPresentationHandler present = ^(NSString *state, NSString *error, NSString *result) {
        if ([state isEqual:@"success"]) { results++; lastResult = result; }
    };
    void (^status)(NSString *) = ^(NSString *value) { lastStatus = value; };
    NSString *(^sanitize)(NSString *, NSString *) = ^NSString *(NSString *value, NSString *source) { return value; };
    [controller testSample:@"sample A" transport:^(NSString *source, void (^reply)(NSString *, NSError *)) {
        firstReply = reply; controller.taskOwner.activeTask = (id)first;
    } isRunning:^BOOL { return running; } status:status present:present sanitize:sanitize];
    NSInteger firstGeneration = controller.generation;
    Check(controller.pending && [lastStatus isEqual:@"正在测试翻译"], @"paused service test has its own pending state");
    running = YES;
    [controller testSample:@"sample B" transport:^(NSString *source, void (^reply)(NSString *, NSError *)) {
        secondReply = reply; controller.taskOwner.activeTask = (id)second;
    } isRunning:^BOOL { return running; } status:status present:present sanitize:sanitize];
    Check(first.cancelCalls == 1 && controller.generation > firstGeneration && second.cancelCalls == 0, @"a repeated service test cancels only its previous task");
    firstReply(@"old reply", nil); DrainMain();
    Check(results == 0 && controller.pending, @"old completion cannot finish the new service test");
    secondReply(@"new reply", nil); Pump(^BOOL { return results == 1; });
    Check(!controller.pending && [lastResult containsString:@"sample B"] && [lastResult containsString:@"new reply"], @"current test completes with its own sample");
    Check([lastStatus isEqual:@"正在测试翻译"], @"running test completion does not overwrite live status");
    controller.pending = YES; running = NO;
    [controller invalidateWhileRunning:running status:status];
    Check(!controller.pending && [lastStatus isEqual:@"服务未测试"], @"configuration change invalidates pending presentation");
}

static void Diagnostics(void) {
    NSDictionary *context = @{@"selected_window_id":@42, @"display_window_id":@42, @"screen_permission":@YES,
        @"input_source":@0, @"running":@NO, @"in_flight":@NO, @"generation":@3,
        @"apiKey":@"synthetic-private-key", @"baseURL":@"https://private.invalid", @"ocr":@"private content"};
    NSDictionary *window = @{(id)kCGWindowNumber:@42, (id)kCGWindowOwnerPID:@98765,
        (id)kCGWindowOwnerName:@"QuickTime Player", (id)kCGWindowName:@"PRIVATE_TITLE", (id)kCGWindowLayer:@0,
        (id)kCGWindowBounds:@{@"X":@20, @"Y":@30, @"Width":@800, @"Height":@500}};
    NSDictionary *snapshot = [FYDiagnosticsController snapshotForWindowInfos:@[window] context:context quickTimeRunning:YES];
    Check([snapshot[@"selected_role"] isEqual:@"quicktime"] && [snapshot[@"selected_exists"] boolValue] && [snapshot[@"candidate_windows"] integerValue] == 1, @"extracted snapshot preserves target classification");
    NSDictionary *report = [FYRuntimeDiagnostics.shared reportForSnapshot:snapshot];
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL] encoding:NSUTF8StringEncoding];
    Check(![json containsString:@"synthetic-private-key"] && ![json containsString:@"private.invalid"] && ![json containsString:@"private content"] && ![json containsString:@"PRIVATE_TITLE"], @"diagnostic boundary excludes unrecognized context and window titles");
    FYDiagnosticsController *controller = [FYDiagnosticsController new];
    Check([controller updateWithSnapshot:snapshot].count > 0 && controller.lastCheckDate != nil, @"diagnostic owner records check lifecycle without controls");
    Check(FYTestCaptureCount() == 0, @"metadata diagnostics never capture a frame");
}

int main(void) { @autoreleasepool {
    Settings(); ServiceTests(); Diagnostics();
    printf("PASS HostExtractionTests: %lu checks; frozen settings, isolated credentials, timer ownership, service epochs, private metadata\n", (unsigned long)checks);
} return 0; }
