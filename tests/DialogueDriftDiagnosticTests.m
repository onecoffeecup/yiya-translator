// Diagnostic reproducer: calls the production timer/OCR-routing pipeline with
// synthetic images, predetermined OCR and a mock translator. No NSApplication,
// windows, real capture, network, preferences or user store are used.
#import "LearningAppTestSupport.h"

@interface DriftSwitch : NSObject
@property NSInteger state;
@end
@implementation DriftSwitch
@end

@interface DriftDiagnosticApp : AppDelegate
@property NSArray<OCRTextItem *> *fixture;
@property NSMutableArray<NSString *> *requests;
@property NSMutableArray<NSString *> *captions;
@end
@implementation DriftDiagnosticApp
- (uint32_t)selectedWindowID { return 42; }
- (WindowItem *)selectedWindowItem { return nil; }
- (BOOL)autoContentModeEnabled { return NO; }
- (NSInteger)effectiveModeSegment { return ContentModeDialogue; }
- (NSString *)systemPrompt { return @"fixed diagnostic prompt"; }
- (void)updateRunState {}
- (void)setStatus:(NSString *)s {}
- (void)updatePreviewFromImage:(CGImageRef)i generation:(NSInteger)g {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)m {}
- (void)showError:(NSString *)s { Require(s.length == 0, @"unexpected production error"); }
- (void)updateTranslationCount {}
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [self.captions addObject:text]; }
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)e {
    *blocks = self.fixture; return [[self.fixture valueForKey:@"text"] componentsJoinedByString:@"\n"];
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)b inImage:(CGImageRef)i normalizedExclusions:(NSArray<NSValue *> *)e { return b; }
- (void)translateTextRealtime:(NSString *)text systemPrompt:(NSString *)p maxTokens:(NSInteger)m completion:(void (^)(NSString *, NSError *))done {
    [self.requests addObject:text];
    done([NSString stringWithFormat:@"模拟译文%lu", (unsigned long)self.requests.count], nil);
}
@end

static OCRTextItem *Line(NSString *text, CGFloat y, CGFloat w) {
    OCRTextItem *b = [OCRTextItem new]; b.text = text;
    b.boundingBox = CGRectMake(.20, y, w, .055); return b;
}
static DriftDiagnosticApp *NewApp(void) {
    DriftDiagnosticApp *a = [DriftDiagnosticApp new];
    a.requests = [NSMutableArray new]; a.captions = [NSMutableArray new]; a.running = YES;
    DriftSwitch *stable = [DriftSwitch new]; stable.state = NSControlStateValueOn;
    DriftSwitch *fit = [DriftSwitch new]; fit.state = NSControlStateValueOff;
    a.stableTextCheckbox = (id)stable; a.autoFitRegionCheckbox = (id)fit;
    // Coordinator uses real identity logic; nil persistence avoids any DB I/O.
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    return a;
}
static void Cycle(DriftDiagnosticApp *a, NSArray *frame) {
    a.fixture = frame; [a timerFired:nil]; Pump(^BOOL { return !a.inFlight; });
}
static void StableFrame(DriftDiagnosticApp *a, NSArray *frame) { Cycle(a, frame); Cycle(a, frame); }

int main(void) { @autoreleasepool {
    unsetenv("FUYI_DIAG");
    NSArray *full = @[Line(@"明日はみんなで図書館に行きましょう。", .20, .65)];
    NSArray *clipped = @[Line(@"明日はみんなで", .20, .31)];
    DriftDiagnosticApp *control = NewApp();
    for (NSUInteger i=0; i<8; i++) StableFrame(control, full);
    Require(control.requests.count == 1, @"unchanged OCR must request once");
    NSLog(@"CONTROL unchanged frames: requests=%lu", (unsigned long)control.requests.count);

    DriftDiagnosticApp *a = NewApp();
    StableFrame(a, full); StableFrame(a, clipped); StableFrame(a, full);
    Require(a.requests.count == 3, @"expected current complete/partial/complete drift to reproduce");
    Require([a.requests[0] isEqual:a.requests[2]], @"restored source must equal the initial source exactly");
    Require(![a.captions.firstObject isEqual:a.captions.lastObject], @"mock paraphrases must replace the displayed translation");
    NSLog(@"REPRO complete/partial/complete: requests=%lu same_first_last_source=YES captions=%@", (unsigned long)a.requests.count, a.captions);

    DriftDiagnosticApp *mode = NewApp();
    StableFrame(mode, full);
    // Mirrors the coordinator effect of actual UI-route recording. This is a
    // component sequence, not proof that QuickTime triggers auto classification.
    [mode.learningCoordinator recordItems:@[@"設定メニュー"] kind:FYSentenceKindUI];
    mode.lastTranslatedNormalizedText = nil; mode.lastSubmittedNormalizedText = nil;
    StableFrame(mode, full);
    Require(mode.requests.count == 2, @"UI context invalidates the original dialogue identity");
    NSLog(@"REPRO dialogue/UI-context/same-dialogue: requests=%lu", (unsigned long)mode.requests.count);
    Require(NSApp == nil, @"diagnostic must never initialize the application UI");
    NSLog(@"PASS diagnostic expectations; current bugs reproduced, NOT fixed; no application UI or real network/capture");
} return 0; }
