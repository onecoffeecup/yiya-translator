#import "FYSettingsStore.h"
#import "../FYLocalAPIKeyStore.h"

NSString *const SettingsKey = @"LiveCaptionTranslator.settings.v1";

@implementation FYSettingsSnapshot
- (instancetype)initWithValues:(NSDictionary *)values {
    if ((self = [super init])) {
        NSMutableDictionary *ordinary = [values mutableCopy] ?: [NSMutableDictionary new];
        [ordinary removeObjectForKey:@"apiKey"];
        // Nested model drafts and calibration maps must also stop changing.
        _values = CFBridgingRelease(CFPropertyListCreateDeepCopy(kCFAllocatorDefault,
            (__bridge CFPropertyListRef)ordinary, kCFPropertyListImmutable));
    }
    return self;
}
@end

@implementation FYTranslationConfiguration
- (instancetype)initWithBaseURL:(NSString *)baseURL model:(NSString *)model
                 learningModel:(NSString *)learningModel apiKey:(NSString *)apiKey {
    if ((self = [super init])) {
        _baseURL = [baseURL copy] ?: @"";
        _model = [model copy] ?: @"";
        _learningModel = [learningModel copy] ?: @"";
        _apiKey = [apiKey copy] ?: @"";
    }
    return self;
}
@end

@interface FYSettingsStore ()
@property(nonatomic, strong) id<FYSettingsPersistence> defaults;
@end

@implementation FYSettingsStore
- (instancetype)initWithDefaults:(id<FYSettingsPersistence>)defaults {
    if ((self = [super init])) { _defaults = defaults; }
    return self;
}
- (FYSettingsSnapshot *)load {
    NSDictionary *settings = [self.defaults objectForKey:SettingsKey];
    NSString *key = nil;
    FYAPIKeyStatus status = FYReadAPIKey(&key);
    if (status == FYAPIKeySuccess || status == FYAPIKeyNotFound) {
        self.persistedAPIKey = key ?: @"";
        self.credentialLoadFailed = NO;
        if (settings[@"apiKey"]) {
            NSMutableDictionary *sanitized = [settings mutableCopy];
            [sanitized removeObjectForKey:@"apiKey"];
            [self.defaults setObject:sanitized forKey:SettingsKey];
        }
    } else {
        self.persistedAPIKey = nil;
        self.credentialLoadFailed = YES;
    }
    return [[FYSettingsSnapshot alloc] initWithValues:settings];
}
- (FYSettingsSaveResult)saveSnapshot:(FYSettingsSnapshot *)snapshot apiKey:(NSString *)apiKey {
    if (self.credentialLoadFailed) { return FYSettingsCredentialReadBlocked; }
    apiKey = apiKey ?: @"";
    if (![apiKey isEqualToString:self.persistedAPIKey ?: @""]) {
        if (FYWriteAPIKey(apiKey) != FYAPIKeySuccess) { return FYSettingsCredentialWriteFailed; }
        self.persistedAPIKey = apiKey;
    }
    [self.defaults setObject:snapshot.values forKey:SettingsKey];
    return FYSettingsSaved;
}
- (void)scheduleSave:(void (^)(void))save {
    if (self.loading) { return; }
    [self cancelScheduledSave];
    __weak typeof(self) weakSelf = self;
    self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *timer) {
        // A replaced/cancelled timer must not write a later settings snapshot.
        if (timer != weakSelf.saveTimer) { return; }
        weakSelf.saveTimer = nil;
        save();
    }];
}
- (void)cancelScheduledSave {
    [self.saveTimer invalidate];
    self.saveTimer = nil;
}
- (void)dealloc { [_saveTimer invalidate]; }
@end
