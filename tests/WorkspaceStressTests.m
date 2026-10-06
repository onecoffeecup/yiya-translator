#import "LearningAppTestSupport.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"stress.sqlite3"]);
    FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]]; Require([catalog loadWithError:NULL], @"catalog failed");
    AppDelegate *app = App(store, Analyzer(catalog), catalog);
    [app refreshLearningSource]; [app freezeLearningSentenceForSelection]; [app.learningCoordinator pinCurrent];
    Require(!app.learningCoordinator.isPinned && !app.pinSentenceButton.enabled && !app.grammarPageAnalyzeButton.enabled, @"empty source must not become pinned or expose analysis actions");
    FYRequestIdentity *identity = [app.learningCoordinator recordText:@"名前\n雨が降っても行きます。\n一緒に行きましょう。\nここで待っていてください。" kind:FYSentenceKindDialogue];
    [app refreshLearningSource];
    Require([app.learningSourceTextView.string isEqualToString:identity.sourceText] && app.grammarPageAnalyzeButton.enabled, @"first recognized dialogue must still follow into the source after an empty-area click");
    NSMutableArray *grammar = [NSMutableArray array];
    for (NSUInteger i=0;i<12;i++) { FYGrammarItem *item=[FYGrammarItem new];item.name=[NSString stringWithFormat:@"語法 %lu",(unsigned long)i]; item.matchedText=@"ても"; item.matchedRange=[identity.sourceText rangeOfString:@"ても"];item.meaning=@"即使……也……";item.connection=@"动词て形＋も";item.explanation=@"表达不受前项情况影响，依然采取行动。"; [grammar addObject:item]; }
    FYAnalysisResult *analysis=[FYAnalysisResult new];analysis.status=FYAnalysisStatusSuccess;analysis.sentenceID=identity.sentenceID;analysis.version=identity.version;analysis.grammar=grammar;analysis.sentenceNote=@"即使下雨也会前往，并邀请对方同行。";
    [app.mainWindow orderFront:nil];
    for (NSUInteger i=0;i<200;i++) { @autoreleasepool {
        [app.mainWindow setContentSize:i%2 ? NSMakeSize(1320,880):NSMakeSize(980,680)];
        app.currentAnalysis=analysis;app.selectedGrammarIndex=i%grammar.count;[app refreshGrammarResults];
        Require([app.sentenceInsightLabel.stringValue isEqualToString:analysis.sentenceNote] && !app.grammarPointsPane.hidden, @"analysis must render the sentence note and default to the grammar points tab");
        Require(app.grammarQuestionField.enabled, @"followups must be available after valid analysis");
        [app selectPageAtIndex:i%6];[app.mainWindow.contentView layoutSubtreeIfNeeded];
        [app clearAnalysisDisplay];
        Require(app.sentenceInsightStack.hidden && !app.grammarQuestionField.enabled, @"source change must remove old explanation and disable old followups");
        Tick();
    }}
    [app selectPageAtIndex:0]; [app refreshLearningSource];
    Require(app.sourceReadingHeight.constant>110, @"four-line source must not be squeezed into the old fixed-height viewport");
    [app.mainWindow orderOut:nil];__block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){Require(!error,@"close failed");closed=YES;}];Pump(^BOOL{return closed;});
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    NSLog(@"PASS: 200 grammar/source/page/resize cycles, 12 grammar points, insight visibility, followup states and multiline source; no capture, user data or real API.");
}return 0;}
