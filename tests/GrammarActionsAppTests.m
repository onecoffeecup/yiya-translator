#import "LearningAppTestSupport.h"

static FYAnalysisResult *Fixture(NSString *source, FYRequestIdentity *identity) {
    FYGrammarItem *item=[FYGrammarItem new]; item.name=@"〜なら"; item.matchedText=@"誘うなら";
    item.matchedRange=[source rangeOfString:item.matchedText]; item.meaning=@"如果…"; item.explanation=@"以邀请出去玩为前提，提出地点建议。"; item.connection=@"动词辞书形＋なら";
    FYAnalysisResult *result=[FYAnalysisResult new]; result.schemaVersion=1; result.grammar=@[item];
    result.sentenceID=identity.sentenceID; result.version=identity.version; result.status=FYAnalysisStatusSuccess;
    return result;
}
static CGFloat ScrollToReadingPosition(NSScrollView *scroll, CGFloat requested) {
    [scroll.window.contentView layoutSubtreeIfNeeded];[scroll.documentView layoutSubtreeIfNeeded];
    CGFloat maxY=MAX(0,NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds));
    Require(maxY>60,@"scroll fixture has room below the top");
    CGFloat y=MIN(requested,maxY);
    [scroll.contentView scrollToPoint:NSMakePoint(0,y)];[scroll reflectScrolledClipView:scroll.contentView];
    return scroll.contentView.bounds.origin.y;
}
static void RequireScrollPosition(NSScrollView *scroll, CGFloat expected, NSString *message) {
    Tick();CGFloat maximum=MAX(0,NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds));
    Require(fabs(scroll.contentView.bounds.origin.y-MIN(expected,maximum))<1,message);
}
static void SaveView(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"native screenshot saved");
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *output=argc>1?[NSString stringWithUTF8String:argv[1]]:@".build/grammar-actions-check/ui";
    [[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:NULL];
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:@"grammar-actions.sqlite"]);
    FYGrammarCatalog *catalog=[FYGrammarCatalog new]; FYLearningAnalyzer *analyzer=Analyzer(catalog);
    AppDelegate *app=App(store,analyzer,catalog);
    app.baseURLField.stringValue=@"https://example.invalid/v1";app.modelField.stringValue=@"review-model";app.apiKeyField.stringValue=@"test-key";
    NSString *source=@"遊びに誘うなら、男の子が好む場所がよさそう。";
    FYRequestIdentity *identity=[app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"如果约他出去玩，选男孩子喜欢的地方似乎比较好。" forIdentity:identity];
    [app.learningCoordinator pinCurrent];Drain(store);
    [app refreshLearningSource];app.currentAnalysis=Fixture(source,identity);[app refreshGrammarResults];
    Require(!app.grammarReviewButton.hidden && !app.grammarExpandButton.hidden,@"main grammar result exposes both actions");
    __block NSUInteger explanationCalls=0;__block void (^explain)(NSData *,NSURLResponse *,NSError *);
    app.grammarActions.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){explanationCalls++;explain=[done copy];};
    [app toggleGrammarExplanation:app.grammarExpandButton];
    Require(!app.grammarExpandedLabel.hidden && !app.grammarExpandButton.enabled && app.currentAnalysis.grammar.count==1,@"explanation waits without discarding short analysis");
    [app toggleGrammarExplanation:app.grammarExpandButton];Require(explanationCalls==1,@"duplicate explanation action is blocked");
    explain(Envelope(@"「誘う」辞书形接「なら」，以邀请他为前提给建议。\n例句：日本に行くなら、京都がおすすめです。\n如果去日本，推荐去京都。"),Response(),nil);
    Pump(^BOOL{return app.grammarExpandButton.enabled;});
    Require([app.grammarExpandButton.title isEqual:@"收起解释"] && [app.grammarExpandedLabel.stringValue containsString:@"京都"],@"main expanded explanation rendered");
    [app toggleGrammarExplanation:app.grammarExpandButton];[app toggleGrammarExplanation:app.grammarExpandButton];
    Require(explanationCalls==1 && !app.grammarExpandedLabel.hidden,@"collapse/reopen uses local explanation cache");
    __block NSUInteger reviews=0;__block void (^review)(NSData *,NSURLResponse *,NSError *);
    analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){reviews++;review=[done copy];};
    NSScrollView *mainScroll=(NSScrollView *)app.pages[0];
    CGFloat mainStart=ScrollToReadingPosition(mainScroll,160);
    [app reviewGrammarSentence:app.grammarReviewButton];[app reviewGrammarSentence:app.grammarReviewButton];
    RequireScrollPosition(mainScroll,mainStart,@"main review click retains vertical reading position");
    Require(reviews==1 && !app.grammarReviewButton.enabled && app.currentAnalysis.grammar.count==1 && app.grammarExpandButton.enabled,@"manual review is independent and keeps reading actions available");
    mainStart=ScrollToReadingPosition(mainScroll,210);
    review(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
    Pump(^BOOL{return app.grammarReviewButton.enabled;});Require(app.currentAnalysis.grammar.count==1 && [app.grammarStatusLabel.stringValue containsString:@"保留"],@"failed review keeps original grammar");
    RequireScrollPosition(mainScroll,mainStart,@"main failed review retains latest scroll position");
    [app reviewGrammarSentence:app.grammarReviewButton];
    mainStart=ScrollToReadingPosition(mainScroll,245);
    review(Envelope(@"{\"schema_version\":1,\"grammar\":[{\"name\":\"连体修饰\",\"matched_text\":\"男の子が好む場所\",\"explanation_zh\":\"小句修饰地点。\"}],\"vocabulary\":[]}"),Response(),nil);
    Pump(^BOOL{return app.grammarReviewButton.enabled;});Require(app.currentAnalysis.grammar.count==2 && [app.grammarStatusLabel.stringValue containsString:@"补充"],@"successful manual review supplements current result");Drain(store);
    RequireScrollPosition(mainScroll,mainStart,@"main successful review retains position reached while waiting");
    __block BOOL cacheRead=NO;
    [app.learningCoordinator analyzeCurrent:^(FYAnalysisResult *result,NSError *error){Require(!error && result.grammar.count==2,@"manual review is saved into compatible first-pass cache");cacheRead=YES;}];Pump(^BOOL{return cacheRead;});Require(reviews==2,@"reading saved review does not launch another request");

    [app.mainWindow setContentSize:NSMakeSize(1100,900)];[app windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:app.mainWindow]];
    [app.mainWindow.contentView layoutSubtreeIfNeeded];
    SaveView(app.grammarPointsPane.superview.superview,[output stringByAppendingPathComponent:@"main-expanded.png"]);
    NSRect reviewFrame=[app.grammarReviewButton convertRect:app.grammarReviewButton.bounds toView:app.grammarReviewButton.superview];
    Require(NSMinX(reviewFrame)>=0 && NSMaxX(reviewFrame)<=NSWidth(app.grammarReviewButton.superview.bounds)+1,@"review button fits a resized native header");
    app.quickSentenceRequested=YES;app.quickSentenceSource=source;app.quickSentenceTranslation=app.learningCoordinator.currentTranslation;
    app.quickSentenceID=identity.sentenceID;app.quickSentenceVersion=identity.version;
    app.quickSentenceAnalysis=app.currentAnalysis;app.quickSentenceAnalysisSource=source;[app renderQuickSentence];
    Require(!app.quickGrammarReviewButton.hidden && app.quickGrammarExpandButton.tag==1,@"quick actions are scoped to quick surface");
    explanationCalls=0;app.quickGrammarActions.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){explanationCalls++;explain=[done copy];};
    [app toggleGrammarExplanation:app.quickGrammarExpandButton];
    explain(Envelope(@"接续：动词辞书形＋なら。以邀请他为前提给出建议。\n日本に行くなら、京都がおすすめです。\n如果去日本，推荐去京都。"),Response(),nil);
    Pump(^BOOL{return app.quickGrammarExpandButton.enabled;});
    Require([app.quickGrammarExpandButton.title isEqual:@"收起解释"],@"quick detailed explanation rendered");
    [app.quickSentencePanel setContentSize:NSMakeSize(440,640)];SaveView(app.quickSentencePanel.contentView,[output stringByAppendingPathComponent:@"quick-expanded.png"]);
    __block void (^quickReview)(NSData *,NSURLResponse *,NSError *);
    app.quickGrammarActions.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){quickReview=[done copy];};
    CGFloat quickStart=ScrollToReadingPosition([app quickSentenceScrollView],110);
    [app reviewGrammarSentence:app.quickGrammarReviewButton];
    RequireScrollPosition([app quickSentenceScrollView],quickStart,@"quick review click retains vertical reading position");
    Require(app.quickSentenceAnalysis.grammar.count==2 && !app.quickGrammarReviewButton.enabled && app.quickGrammarExpandButton.enabled,@"quick review leaves current explanation usable");
    quickStart=ScrollToReadingPosition([app quickSentenceScrollView],155);
    quickReview(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
    Pump(^BOOL{return app.quickGrammarReviewButton.enabled;});
    Require(app.quickSentenceAnalysis.grammar.count==2 && [app.quickGrammarReviewStatus.stringValue containsString:@"保留"],@"quick review failure preserves result");
    RequireScrollPosition([app quickSentenceScrollView],quickStart,@"quick failed review retains latest scroll position");
    [app reviewGrammarSentence:app.quickGrammarReviewButton];
    quickStart=ScrollToReadingPosition([app quickSentenceScrollView],180);
    quickReview(Envelope(@"{\"schema_version\":1,\"grammar\":[{\"name\":\"目的 に\",\"matched_text\":\"遊びに\"}],\"vocabulary\":[]}"),Response(),nil);
    Pump(^BOOL{return app.quickGrammarReviewButton.enabled;});
    Require(app.quickSentenceAnalysis.grammar.count==3 && [app.quickGrammarExpandButton.title isEqual:@"收起解释"],@"quick review supplements without losing expanded selection");
    RequireScrollPosition([app quickSentenceScrollView],quickStart,@"quick successful review retains position reached while waiting");
    app.quickGrammarActions.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){explanationCalls++;explain=[done copy];};
    NSButton *second=app.quickGrammarChoices[1];[app selectQuickGrammar:second];
    [app toggleGrammarExplanation:app.quickGrammarExpandButton];Require(explanationCalls==2,@"another grammar has an independent request");
    [app closeStudyOverlay:nil];explain(Envelope(@"旧解释"),Response(),nil);Tick();
    Require(!app.quickGrammarActions.expandedItem && app.quickGrammarActions.explanations.count==0,@"closing quick panel rejects a late explanation");
    [app clearAnalysisDisplay];Require(app.grammarReviewButton.hidden && app.grammarExpandedLabel.hidden,@"switching sentence clears manual action state");
    Require(FYTestCaptureCount()==0,@"grammar actions never start capture");
    NSLog(@"PASS: native grammar actions, one request per action, cache, failure preservation, request ownership and late-response isolation");
} return 0; }
