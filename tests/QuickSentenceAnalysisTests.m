#import "LearningAppTestSupport.h"
@interface FYQuickAnalysisTestApp : AppDelegate
@property(nonatomic) BOOL targetForeground;
@end
@implementation FYQuickAnalysisTestApp
- (BOOL)translationTargetIsForeground {return self.targetForeground;}
@end
static BOOL Shows(NSView *view,NSString *text){
    if([view isKindOfClass:NSTextField.class] && [[(NSTextField *)view stringValue] containsString:text]){return YES;}
    for(NSView *child in view.subviews){if(Shows(child,text)){return YES;}}
    return NO;
}
static NSButton *GrammarChoice(NSView *view,NSInteger index){
    if([view isKindOfClass:NSButton.class] && [(NSButton *)view action]==@selector(selectQuickGrammar:) && [(NSButton *)view tag]==index){return (NSButton *)view;}
    for(NSView *child in view.subviews){NSButton *button=GrammarChoice(child,index);if(button){return button;}}
    return nil;
}
static void SaveQuick(NSView *view,NSString *path){[view layoutSubtreeIfNeeded];NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"native quick screenshot saved");}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];
    NSString *db=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"]];
    FYLearningStore *store=Store(db);FYGrammarCatalog *catalog=[FYGrammarCatalog new];
    FYQuickAnalysisTestApp *app=[FYQuickAnalysisTestApp new];app.targetForeground=YES;
    app.learningStore=store;app.grammarCatalog=catalog;
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    [app createMainWindow];[app createCaptionWindow];
    app.baseURLField.stringValue=@"https://example.invalid/v1";app.apiKeyField.stringValue=@"mock-key";app.modelField.stringValue=@"mock-model";
    app.quickSentenceAnalyzer=Analyzer(catalog);
    __block NSUInteger requests=0;__block NSDictionary *payload;
    __block void (^pending)(NSData *,NSURLResponse *,NSError *);
    app.quickSentenceAnalyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){
        requests++;pending=[done copy];payload=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    };
    app.quickSentenceRequested=YES;app.quickSentenceSource=@"";[app analyzeQuickSentence:nil];Require(requests==0,@"empty source does not request analysis");[app closeStudyOverlay:nil];
    FYRequestIdentity *pinned=[app.learningCoordinator recordText:@"前の句です。" kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"上一句。" forIdentity:pinned];[app.learningCoordinator pinCurrent];
    FYRequestIdentity *latest=[app.learningCoordinator recordText:@"絵が得意でも、毎日練習しないと上達しない。" kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"即使擅长画画，不每天练习也不会进步。" forIdentity:latest];Drain(store);
    [app showQuickSentence:nil];Pump(^BOOL{return requests==1;});
    if(argc>1){Tick();SaveQuick(app.quickSentencePanel.contentView,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"quick-loading.png"]);}
    Require(app.quickSelectedGrammarIndex==0,@"new analysis defaults to first grammar");
    Require(app.quickSentenceAnalyzing && Shows(app.quickSentencePanel.contentView,@"正在分析"),@"opening sentence automatically starts analysis and shows progress");
    Require([payload[@"messages"][1][@"content"] containsString:@"絵が得意でも、毎日練習しないと上達しない。"],@"request uses displayed latest source");
    Require([app.learningCoordinator.currentSentenceID isEqualToString:pinned.sentenceID],@"quick analysis preserves main pinned identity");
    [app showQuickSentence:nil];Tick();Require(requests==1,@"repeated clicks do not duplicate pending request");
    [app.learningCoordinator recordText:@"さらに次の句。" kind:FYSentenceKindDialogue];Drain(store);
    NSString *json=@"{\"schema_version\": 1, \"grammar\": [{\"name\": \"〜でも\", \"matched_text\": \"得意でも\", \"occurrence\": 0, \"connection\": \"な形容词词干＋でも\", \"meaning_zh\": \"让步\", \"explanation_zh\": \"「得意でも」承认能力，但说明后面的结论仍然成立。\"}, {\"name\": \"〜ないと\", \"matched_text\": \"練習しないと\", \"occurrence\": 0, \"connection\": \"动词ない形＋と\", \"meaning_zh\": \"否定条件\", \"explanation_zh\": \"“如果不……就……”。这句强调：不持续练习，就不会进步。\"}], \"vocabulary\": [], \"sentence_note_zh\": \"先让步，再说条件和结果。\", \"structure_title_zh\": \"先让步，再说条件和结果\", \"structure_parts\": [{\"text\": \"絵が得意でも\", \"meaning_zh\": \"即使擅长画画\", \"role_zh\": \"让步\", \"occurrence\": 0}, {\"text\": \"毎日練習しないと\", \"meaning_zh\": \"如果不每天练习\", \"role_zh\": \"条件\", \"occurrence\": 0}, {\"text\": \"上達しない\", \"meaning_zh\": \"不会进步\", \"role_zh\": \"结果\", \"occurrence\": 0}]}";
    pending(Envelope(json),Response(),nil);Pump(^BOOL{return !app.quickSentenceAnalyzing;});
    Require([app.quickSentenceSource isEqualToString:@"絵が得意でも、毎日練習しないと上達しない。"] && Shows(app.quickSentencePanel.contentView,@"承认能力"),@"new OCR cannot switch analyzed snapshot, result appears in overlay");
    Require(!Shows(app.quickSentencePanel.contentView,@"不持续练习，就不会进步"),@"default shows first grammar detail only");
    NSButton *second=GrammarChoice(app.quickSentencePanel.contentView,1);Require(second!=nil && app.quickStructureButtons.count==3,@"grammar choices and complete structure remain reachable");[app.quickStructureButtons[1] performClick:nil];Tick();
    Require(app.quickSelectedGrammarIndex==1 && Shows(app.quickSentencePanel.contentView,@"不持续练习") && !Shows(app.quickSentencePanel.contentView,@"承认能力"),@"selecting second grammar replaces first detail");
    Require(GrammarChoice(app.quickSentencePanel.contentView,1).state==NSControlStateValueOn && GrammarChoice(app.quickSentencePanel.contentView,0).state==NSControlStateValueOff && requests==1,@"selected grammar highlighted, switch does not call API");
    NSButton *firstChoice=GrammarChoice(app.quickSentencePanel.contentView,0);[firstChoice performClick:nil];Tick();
    Require(Shows(app.quickSentencePanel.contentView,@"承认能力") && !Shows(app.quickSentencePanel.contentView,@"不持续练习，就不会进步"),@"switching back leaves exactly one detail visible");
    [app.quickSentencePanel setContentSize:NSMakeSize(440,500)];[app.quickSentencePanel.contentView layoutSubtreeIfNeeded];Tick();
    NSScrollView *switchScroll=app.quickGrammarStack.enclosingScrollView;NSView *sameHost=app.quickSentencePanel.contentView;
    Require(NSHeight(switchScroll.documentView.frame)-NSHeight(switchScroll.contentView.bounds)>40,@"compact panel has genuinely scrollable grammar content");
    [switchScroll.contentView scrollToPoint:NSMakePoint(0,40)];[switchScroll reflectScrolledClipView:switchScroll.contentView];
    for(NSUInteger switchIndex=0;switchIndex<12;switchIndex++){
        [GrammarChoice(app.quickSentencePanel.contentView,switchIndex%2) performClick:nil];Tick();
        Require(app.quickSentencePanel.contentView==sameHost && app.quickGrammarStack.enclosingScrollView==switchScroll,@"grammar switch updates detail in place");
        Require(fabs(switchScroll.contentView.bounds.origin.y-40)<1,@"grammar switching preserves scrolled reading position");
    }
    [GrammarChoice(app.quickSentencePanel.contentView,0) performClick:nil];
    [app.quickSentencePanel setContentSize:NSMakeSize(440,640)];Tick();
    if(argc>1){Tick();SaveQuick(app.quickSentencePanel.contentView,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"quick-result.png"]);}
    NSScrollView *reading=nil;for(NSView *child in app.quickSentencePanel.contentView.subviews){if([child isKindOfClass:NSScrollView.class]){reading=(NSScrollView *)child;}}
    Require(reading && NSHeight(reading.frame)>250 && NSWidth(reading.frame)>400,@"reading body has usable fixed viewport");
    Require(NSWidth(app.quickSentencePanel.frame)<=442,@"analysis results stay within quick panel width");
    Require(app.quickSentenceAnalysis.structureParts.count==3 && Shows(app.quickSentencePanel.contentView,@"先让步，再说条件和结果"),@"verified whole-sentence structure displayed including result clause");
    [GrammarChoice(app.quickSentencePanel.contentView,1) performClick:nil];
    [app.quickGrammarBookmarkButton performClick:nil];Pump(^BOOL{return !app.quickGrammarBookmarkPending;});
    __block NSArray *saved=nil;[store fetchGrammarBookmarksWithCompletion:^(NSArray *bookmarks,NSError *error){Require(!error,@"grammar bookmark load");saved=bookmarks;}];Pump(^BOOL{return saved!=nil;});
    Require(saved.count==1 && [((FYGrammarBookmark *)saved[0]).name isEqualToString:@"〜ないと"] && [((FYGrammarBookmark *)saved[0]).sourceTextSnapshot isEqualToString:app.quickSentenceSource] && [app.learningCoordinator.currentSentenceID isEqualToString:pinned.sentenceID],@"quick grammar bookmark saves selected grammar and frozen source without changing main sentence");
    [app.quickGrammarBookmarkButton performClick:nil];Pump(^BOOL{return !app.quickGrammarBookmarkPending;});
    saved=nil;[store fetchGrammarBookmarksWithCompletion:^(NSArray *bookmarks,NSError *error){saved=bookmarks;}];Pump(^BOOL{return saved!=nil;});Require(saved.count==0,@"quick bookmark can be cancelled");
    [app.quickSentenceBookmarkButton performClick:nil];Pump(^BOOL{return !app.sentenceBookmarkPending;});
    __block NSArray *sentenceSaves=nil;[store fetchSentenceBookmarks:^(NSArray *values,NSError *error){Require(!error,@"saved sentence read");sentenceSaves=values;}];Pump(^BOOL{return sentenceSaves!=nil;});
    Require(sentenceSaves.count==1 && [((FYRequestIdentity *)sentenceSaves[0]).sentenceID isEqualToString:latest.sentenceID],@"quick sentence save uses displayed identity despite newer OCR");
    [app.quickSentenceBookmarkButton performClick:nil];Pump(^BOOL{return !app.sentenceBookmarkPending;});
    sentenceSaves=nil;[store fetchSentenceBookmarks:^(NSArray *values,NSError *error){sentenceSaves=values;}];Pump(^BOOL{return sentenceSaves!=nil;});Require(sentenceSaves.count==0,@"quick sentence bookmark cancel");
    app.learningSourceTextView.editable=NO;
    [GrammarChoice(app.quickSentencePanel.contentView,1) performClick:nil];
    [app openStudyWorkspace:nil];
    Require(app.currentAnalysis.structureParts.count==3,@"structure transfers to main workspace");
    Require(app.selectedGrammarIndex==1,@"workspace keeps grammar selected in quick panel");
    Require([app.learningCoordinator.currentSentenceID isEqualToString:latest.sentenceID] && app.learningCoordinator.currentVersion==latest.version && app.learningCoordinator.isPinned,@"workspace jump pins exact overlay identity after newer OCR");
    Require([app.learningSourceTextView.string isEqualToString:@"絵が得意でも、毎日練習しないと上達しない。"] && [app.learningTranslationLabel.stringValue isEqualToString:@"即使擅长画画，不每天练习也不会进步。"],@"workspace receives overlay original and translation");
    Require([app analysisMatchesCurrentSentence] && app.currentAnalysis.grammar.count==2 && requests==1 && !app.quickSentencePanel.isVisible,@"finished quick analysis transfers without duplicate API request");
    [app closeStudyOverlay:nil];
    // Latest is now another sentence; close while pending and reject its late response.
    [app showQuickSentence:nil];Pump(^BOOL{return requests==2;});Require(app.quickSelectedGrammarIndex==0,@"different sentence resets selected grammar");
    void (^late)(NSData *,NSURLResponse *,NSError *)=[pending copy];
    [app closeStudyOverlay:nil];late(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"),Response(),nil);Tick();
    Require(!app.quickSentenceRequested && !app.quickSentencePanel.isVisible && !app.quickSentenceAnalyzing,@"late response cannot reopen closed panel");
    [app showQuickSentence:nil];Pump(^BOOL{return requests==3;});
    pending(nil,nil,[NSError errorWithDomain:@"mock" code:500 userInfo:@{NSLocalizedDescriptionKey:@"模拟失败"}]);Pump(^BOOL{return !app.quickSentenceAnalyzing;});
    Require(Shows(app.quickSentencePanel.contentView,@"模拟失败") && Shows(app.quickSentencePanel.contentView,@"这一句的语法"),@"failure stays in overlay");
    [app analyzeQuickSentence:nil];Require(requests==4 && app.quickSentenceAnalyzing,@"retry starts dedicated analysis");
    pending(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[],\"sentence_note_zh\":\"句子说明\"}"),Response(),nil);Pump(^BOOL{return !app.quickSentenceAnalyzing;});
    [app closeStudyOverlay:nil];[app showQuickSentence:nil];Tick();Require(requests==4 && Shows(app.quickSentencePanel.contentView,@"句子说明"),@"reopening same analyzed snapshot reuses result");
    [app closeStudyOverlay:nil];app.targetForeground=NO;[app showQuickSentence:nil];Tick();Require(requests==4 && !app.quickSentencePanel.isVisible,@"background target cannot open or request analysis");
    app.targetForeground=YES;
    __block BOOL followed=NO;[app.learningCoordinator followLatestWithCompletion:^{followed=YES;}];Pump(^BOOL{return followed;});
    FYAnalysisResult *existing=[FYAnalysisResult new];existing.grammar=@[];existing.vocabulary=@[];existing.sentenceNote=@"已有的主界面解析";
    existing.sentenceID=app.learningCoordinator.currentSentenceID;existing.version=app.learningCoordinator.currentVersion;
    app.currentAnalysis=existing;app.learningSourceTextView.editable=NO;app.quickSentenceAnalysis=nil;
    [app showQuickSentence:nil];Tick();Require(requests==4 && Shows(app.quickSentencePanel.contentView,@"已有的主界面解析"),@"matching main analysis is reused without new API request");
    [app closeStudyOverlay:nil];
    [app.learningCoordinator recordText:@"また新しい句。" kind:FYSentenceKindDialogue];Drain(store);
    [app showQuickSentence:nil];Pump(^BOOL{return requests==5;});late=[pending copy];
    [app showStudyChatOverlay:nil];late(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"),Response(),nil);Tick();
    Require(app.studyChatPanel.isVisible && !app.quickSentencePanel.isVisible && !app.quickSentenceAnalyzing,@"switching to AI rejects late quick analysis");
    [app closeStudyOverlay:nil];
    app.learningAnalyzer=[app.learningCoordinator valueForKey:@"analyzer"];
    __block NSUInteger mainRequests=0;__block void (^mainPending)(NSData *,NSURLResponse *,NSError *);
    app.learningAnalyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){mainRequests++;mainPending=[done copy];};
    [app showQuickSentence:nil];Pump(^BOOL{return requests==6;});late=[pending copy];
    [app openStudyWorkspace:nil];Pump(^BOOL{return mainRequests==1;});
    Require(app.learningAnalysisBusy && app.learningCoordinator.isPinned && [app.learningSourceTextView.string isEqualToString:@"また新しい句。"],@"jump during pending quick request starts main analysis automatically on displayed sentence");
    [app.learningCoordinator recordText:@"游戏又出现新句。" kind:FYSentenceKindDialogue];Drain(store);
    mainPending(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[],\"sentence_note_zh\":\"主界面自动分析结果\"}"),Response(),nil);Pump(^BOOL{return !app.learningAnalysisBusy;});
    Require([app analysisMatchesCurrentSentence] && [app.sentenceInsightLabel.stringValue isEqualToString:@"主界面自动分析结果"],@"main automatic analysis displays result despite newer OCR");
    late(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"),Response(),nil);Tick();
    Require(!app.quickSentencePanel.isVisible && [app.sentenceInsightLabel.stringValue isEqualToString:@"主界面自动分析结果"],@"cancelled quick reply cannot reopen or overwrite transferred workspace");
    [app closeStudyOverlay:nil];[app.mainWindow orderOut:nil];[app.captionPanel orderOut:nil];
    NSLog(@"PASS: automatic quick grammar, snapshot isolation, pending deduplication, close/switch cancellation, retry and cached reopen");
}return 0;}
