#import "FYAppDelegateInternal.h"

// Compatibility actions and aliases only; state belongs to the existing owners.
@interface AppDelegate (FYSettingsCompatibility)
@end

@implementation AppDelegate (FYSettingsCompatibility)
- (NSString *)persistedAPIKey { return [self settingsStore].persistedAPIKey; }

- (void)setPersistedAPIKey:(NSString *)value { [self settingsStore].persistedAPIKey = value; }

- (BOOL)credentialLoadFailed { return [self settingsStore].credentialLoadFailed; }

- (void)setCredentialLoadFailed:(BOOL)value { [self settingsStore].credentialLoadFailed = value; }

- (BOOL)loadingSettings { return [self settingsStore].loading; }

- (void)setLoadingSettings:(BOOL)value { [self settingsStore].loading = value; }

- (NSTimer *)saveTimer { return [self settingsStore].saveTimer; }

- (void)setSaveTimer:(NSTimer *)value { [self settingsStore].saveTimer = value; }

- (NSInteger)serviceTestGeneration { return [self serviceTestController].generation; }

- (void)setServiceTestGeneration:(NSInteger)value { [self serviceTestController].generation = value; }

- (FYTranslationTaskOwner *)serviceTestTaskOwner { return [self serviceTestController].taskOwner; }

- (void)setServiceTestTaskOwner:(FYTranslationTaskOwner *)value { [self serviceTestController].taskOwner = value; }

- (NSTextField *)diagnosticStatusLabel { return [self diagnosticsController].resultLabel; }

- (void)setDiagnosticStatusLabel:(NSTextField *)value { [self diagnosticsController].resultLabel = value; }

- (NSDate *)lastDiagnosticCheckDate { return [self diagnosticsController].lastCheckDate; }

- (void)setLastDiagnosticCheckDate:(NSDate *)value { [self diagnosticsController].lastCheckDate = value; }

- (BOOL)exportingDiagnostics { return [self diagnosticsController].exporting; }

- (void)setExportingDiagnostics:(BOOL)value { [self diagnosticsController].exporting = value; }

- (NSSharingService *)diagnosticMailService { return [self diagnosticsController].mailService; }

- (void)setDiagnosticMailService:(NSSharingService *)value { [self diagnosticsController].mailService = value; }

- (instancetype)init {
    self = [super init];
    if (self) {
        self.inlineTranslationPanels = [NSMutableArray array];
        self.inlineLongCardPanels = [NSMutableArray array];
        self.inlinePanelsByBlockID = [NSMutableDictionary dictionary];
        self.inlineManualOffsets = [NSMutableDictionary dictionary];
        self.inlineManualOffsetAge = [NSMutableDictionary dictionary];
        self.inlineStableBlockIDs = [NSMutableDictionary dictionary];
        self.inlineTranslationCache = [NSMutableDictionary dictionary];
        self.captureQueue = dispatch_queue_create("com.nanami.yiya.capture", DISPATCH_QUEUE_SERIAL);
        // Create the shared recognizer before any background OCR can access it.
        [self ocrManager];
    }
    return self;
}
@end
