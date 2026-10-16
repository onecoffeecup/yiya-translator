#import "LearningAppTestSupport.h"
#import <objc/runtime.h>

@interface PresentationProbeApp : AppDelegate
@property(nonatomic) NSUInteger collectionActions;
@end
@implementation PresentationProbeApp
- (void)selectLearningCollection:(NSButton *)sender {
    self.collectionActions++;
    [super selectLearningCollection:sender];
}
@end

static NSUInteger checks;
static void Check(BOOL value, NSString *message) { checks++; Require(value, message); }

int main(void) { @autoreleasepool {
    // Cold access must not create windows, load user settings or retain the host.
    __weak AppDelegate *released;
    FYMainWindowController *window;
    FYCollectionController *collection;
    FYGrammarPresentationController *grammar;
    FYStudyPresentationController *study;
    FYReferencePresentationController *reference;
    @autoreleasepool {
        AppDelegate *cold = [AppDelegate new]; released = cold;
        window = cold.mainWindowController; collection = cold.collectionController;
        grammar = cold.grammarPresentationController; study = cold.studyPresentationController;
        reference = cold.referencePresentationController;
        Check(!cold.mainWindow && !cold.quickSentencePanel && !cold.studyChatPanel, @"controller access stays cold");
        Check([cold conformsToProtocol:@protocol(FYMainWindowControllerHost)] &&
            [cold conformsToProtocol:@protocol(FYCollectionControllerHost)] &&
            [cold conformsToProtocol:@protocol(FYGrammarPresentationControllerHost)] &&
            [cold conformsToProtocol:@protocol(FYStudyPresentationControllerHost)] &&
            [cold conformsToProtocol:@protocol(FYReferencePresentationControllerHost)], @"host provides explicit presentation contracts");
    }
    Check(!released && !window.host && !collection.host && !grammar.host && !study.host && !reference.host,
          @"presentation controllers do not retain a closed host");
    for (NSString *name in @[@"_mainWindow", @"_selectedPage", @"_reviewList", @"_wordCardsGeneration",
        @"_currentAnalysis", @"_analysisRequestGeneration", @"_quickSentenceSource", @"_studyChatSession", @"_referenceRecords"]) {
        Check(class_getInstanceVariable(AppDelegate.class, name.UTF8String) == NULL, @"legacy facade has no duplicate UI state ivar");
    }

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Check([catalog loadWithError:NULL], @"synthetic test loads bundled grammar catalog");
    FYLearningStore *store = Store([NSTemporaryDirectory() stringByAppendingPathComponent:@"presentation-ownership.sqlite3"]);
    PresentationProbeApp *app = [PresentationProbeApp new];
    app.learningStore = store; app.learningAnalyzer = Analyzer(catalog); app.grammarCatalog = catalog;
    app.japaneseTokenizer = [FYJapaneseTokenizer new];
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:store analyzer:app.learningAnalyzer
        tokenizer:app.japaneseTokenizer catalog:catalog];
    [app createMainWindow];
    Check(app.mainWindow == app.mainWindowController.mainWindow && app.mainWindow.delegate == app,
          @"native window and delegate retain the original host entry");
    Check(app.learningCoordinator == app.collectionController.host.learningCoordinator &&
          app.learningCoordinator == app.studyPresentationController.host.learningCoordinator,
          @"controllers use the same learning identity service");
    FYStudyChatSession *session = app.studyChatSession;
    FYStudyChatView *chat = app.mainStudyChatView;
    [chat setDraftText:@"保留这份草稿"];
    NSTextView *input = [chat valueForKey:@"input"];
    [app selectPageAtIndex:2]; [app selectPageAtIndex:0];
    [app toggleMainStudyChat:nil]; [app toggleMainStudyChat:nil];
    Check(app.studyChatSession == session && app.mainStudyChatView == chat &&
          [input.string isEqual:@"保留这份草稿"], @"page/sidebar changes preserve the same conversation view and draft");
    NSButton *tab = app.learningCollectionTabs[3];
    NSUInteger before = app.collectionActions;
    Check(tab.target == app, @"native collection action retains host subclass hooks");
    [tab performClick:nil];
    Check(app.collectionActions == before + 1 && app.learningCollectionIndex == 3 &&
          app.collectionController.learningCollectionIndex == 3, @"native action reaches one collection owner");
    FYAnalysisResult *analysis = [FYAnalysisResult new];
    app.currentAnalysis = analysis;
    Check(app.grammarPresentationController.currentAnalysis == analysis, @"analysis facade writes its sole owner");
    app.quickSentenceSource = @"猫です。";
    app.studyPresentationController.quickSentenceVersion = 4;
    Check([app.studyPresentationController.quickSentenceSource isEqual:@"猫です。"] && app.quickSentenceVersion == 4,
          @"quick reading state is shared through compatibility accessors");
    app.referencePresentationController.referenceRecords = @[@{@"id":@1}];
    Check(app.referenceRecords == app.referencePresentationController.referenceRecords,
          @"reference results have one owner");
    [app.mainWindow orderOut:nil];
    Drain(store);
    printf("PASS PresentationOwnershipTests: %lu checks; cold/weak ownership, unique state, native action hooks, shared identity, retained drafts\n", (unsigned long)checks);
} return 0; }
