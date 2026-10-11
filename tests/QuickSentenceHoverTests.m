#import "LearningAppTestSupport.h"

@interface FYQuickHoverTestApp : AppDelegate
@end
@implementation FYQuickHoverTestApp
- (BOOL)translationTargetIsForeground { return YES; }
@end

static FYSelectableSourceTextView *SourceView(NSView *root, NSString *source) {
    if([root isKindOfClass:FYSelectableSourceTextView.class] && [((NSTextView *)root).string isEqualToString:source])return (FYSelectableSourceTextView *)root;
    for(NSView *child in root.subviews){FYSelectableSourceTextView *view=SourceView(child,source);if(view)return view;}
    return nil;
}
@interface FYDelayedQuickTokenizer : FYJapaneseTokenizer
@property(nonatomic, copy) NSString *submittedText;
@property(nonatomic, copy) void (^pending)(NSArray<NSValue *> *);
@end
@implementation FYDelayedQuickTokenizer
- (void)rangesInText:(NSString *)text completion:(void (^)(NSArray<NSValue *> *))completion {
    self.submittedText=text;self.pending=completion;
}
@end
@interface FYImmediateQuickTokenizer : FYJapaneseTokenizer
@end
@implementation FYImmediateQuickTokenizer
- (void)rangesInText:(NSString *)text completion:(void (^)(NSArray<NSValue *> *))completion {
    completion(@[[NSValue valueWithRange:NSMakeRange(0,2)]]);
}
@end
@interface FYDelayedQuickDictionary : FYReferenceDictionary
@property(nonatomic, copy) void (^pending)(NSArray<NSDictionary *> *,NSError *);
@end
@implementation FYDelayedQuickDictionary
- (void)lookupWord:(NSString *)word reading:(NSString *)reading completion:(void (^)(NSArray<NSDictionary *> *,NSError *))completion {self.pending=completion;}
@end
static NSString *Tip(FYSelectableSourceTextView *view,NSString *word) {
    return [view.textStorage attribute:FYSourceHoverAttributeName atIndex:[view.string rangeOfString:word].location effectiveRange:NULL];
}
static void Layout(AppDelegate *app) {
    for(NSUInteger i=0;i<4;i++){[app.quickSentencePanel.contentView layoutSubtreeIfNeeded];Tick();}
}
static NSEvent *Move(FYSelectableSourceTextView *view,NSString *word) {
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSRange range=[view.string rangeOfString:word];
    NSRange glyph=[view.layoutManager glyphRangeForCharacterRange:NSMakeRange(range.location,1) actualCharacterRange:NULL];
    NSRect box=[view.layoutManager boundingRectForGlyphRange:glyph inTextContainer:view.textContainer];
    NSPoint point=[view convertPoint:NSMakePoint(NSMidX(box)+view.textContainerOrigin.x,NSMidY(box)+view.textContainerOrigin.y) toView:nil];
    return [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point modifierFlags:0 timestamp:0 windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
}
static NSPanel *ShowHover(FYSelectableSourceTextView *view,NSString *word) {
    [view mouseMoved:Move(view,word)];
    Require(![[view valueForKey:@"sourceHoverPanel"] isVisible],@"hover waits for dwell before appearing");
    Pump(^BOOL{return [[view valueForKey:@"sourceHoverPanel"] isVisible];});
    return [view valueForKey:@"sourceHoverPanel"];
}
static void Snapshot(NSView *view,NSString *path) {
    [view displayIfNeeded];NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"save production view snapshot");
}
static void RenderSentence(AppDelegate *app,NSString *source) {
    app.quickSentenceSource=source;app.quickSentenceRequested=YES;app.quickSentenceID=@"synthetic-quick";app.quickSentenceVersion=1;
    app.quickSentenceAnalysis=nil;app.quickSentenceAnalysisSource=nil;
    [app renderQuickSentence];Layout(app);
}
static void CheckLateCallbacks(AppDelegate *app) {
    FYJapaneseTokenizer *realTokenizer=app.japaneseTokenizer;
    dispatch_sync([realTokenizer valueForKey:@"queue"],^{});Tick();
    FYDelayedQuickTokenizer *delayed=[FYDelayedQuickTokenizer new];app.japaneseTokenizer=delayed;
    NSString *first=@"仲間を救う。",*second=@"明日は休む。";
    Require(first.length==second.length,@"same-length replacement fixture");
    RenderSentence(app,first);FYSelectableSourceTextView *old=app.quickSourceTextView;
    void (^oldCompletion)(NSArray *)=[delayed.pending copy];
    RenderSentence(app,second);oldCompletion(@[[NSValue valueWithRange:NSMakeRange(0,2)]]);
    Require([delayed.submittedText isEqualToString:second] && !Tip(old,@"仲間") && !Tip(app.quickSourceTextView,@"明日"),@"old tokenization cannot annotate old or replaced quick view");
    RenderSentence(app,first);old=app.quickSourceTextView;oldCompletion=[delayed.pending copy];
    [old.textStorage replaceCharactersInRange:NSMakeRange(0,first.length) withString:second];
    Require([delayed.submittedText isEqualToString:first],@"tokenization request owns an immutable source snapshot");
    oldCompletion(@[[NSValue valueWithRange:NSMakeRange(0,2)]]);
    Require(!Tip(old,@"明日"),@"in-place equal-length edits reject pending token ranges");
    RenderSentence(app,first);oldCompletion=[delayed.pending copy];app.quickSentenceVersion++;
    oldCompletion(@[[NSValue valueWithRange:NSMakeRange(0,2)]]);
    Require(!Tip(app.quickSourceTextView,@"仲間"),@"changed displayed identity rejects old callbacks even with identical text");
    RenderSentence(app,first);oldCompletion=[delayed.pending copy];
    [app closeStudyOverlay:nil];oldCompletion(@[[NSValue valueWithRange:NSMakeRange(0,2)]]);
    Require(!Tip(app.quickSourceTextView,@"仲間"),@"closing quick reader invalidates pending tokenization");

    FYReferenceDictionary *realDictionary=app.referenceDictionary;
    FYDelayedQuickDictionary *dictionary=[[FYDelayedQuickDictionary alloc] initWithURL:nil];
    app.referenceDictionary=dictionary;app.sourceHoverCache=[NSCache new];app.japaneseTokenizer=[FYImmediateQuickTokenizer new];
    RenderSentence(app,first);void (^lookup)(NSArray *,NSError *)=[dictionary.pending copy];old=app.quickSourceTextView;
    RenderSentence(app,second);
    NSArray *records=@[@{@"readings":@[@"なかま"],@"senses":@[@{@"glosses":@[@"companion"]}]}];
    lookup(records,nil);
    Require(![Tip(old,@"仲間") containsString:@"JMdict"] && ![Tip(app.quickSourceTextView,@"明日") containsString:@"なかま"],@"late dictionary callback cannot mutate obsolete or current quick view");
    lookup=[dictionary.pending copy];NSString *before=Tip(app.quickSourceTextView,@"明日");[app closeStudyOverlay:nil];lookup(records,nil);
    Require([Tip(app.quickSourceTextView,@"明日") isEqualToString:before],@"closing quick reader rejects pending dictionary results");
    app.referenceDictionary=realDictionary;app.sourceHoverCache=[NSCache new];app.japaneseTokenizer=realTokenizer;
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:@"quick-hover.sqlite3"]);
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];
    FYQuickHoverTestApp *app=[FYQuickHoverTestApp new];app.learningStore=store;app.grammarCatalog=catalog;
    app.learningAnalyzer=Analyzer(catalog);app.japaneseTokenizer=[FYJapaneseTokenizer new];
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:app.learningAnalyzer tokenizer:app.japaneseTokenizer catalog:catalog];
    [app createMainWindow];
    app.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"resources/learning/reference/reference.sqlite"]]];
    FYRequestIdentity *pinned=[app.learningCoordinator recordText:@"以前の原句。" kind:FYSentenceKindDialogue];
    [app.learningCoordinator selectSentenceID:pinned.sentenceID version:pinned.version sourceText:pinned.sourceText translation:nil];Drain(store);[app refreshLearningSource];
    app.quickSentenceRequested=YES;app.quickSentenceID=@"synthetic-quick";app.quickSentenceVersion=1;
    app.quickSentenceSource=@"絵が得意でも、毎日練習しないと上達しない。";
    app.quickSentenceTranslation=@"即使擅长画画，如果不每天练习，也不会进步。";
    NSString *source=[app.quickSentenceSource copy];
    [app renderQuickSentence];Layout(app);
    FYSelectableSourceTextView *view=SourceView(app.quickSentencePanel.contentView,source);
    Require(view!=nil && view==app.quickSourceTextView,@"quick sentence uses the same native hover source view as live reading");
    Pump(^BOOL{return [Tip(view,@"上達") containsString:@"JMdict"];});
    Require([Tip(view,@"上達") containsString:@"じょうたつ"] && view.selectedRange.length==0 && [app.learningCoordinator.currentSentenceID isEqualToString:pinned.sentenceID],@"bundled dictionary supplies reading without selecting text or replacing main pinned identity");
    FYVocabularyEntry *word=[FYVocabularyEntry new];word.surface=@"上達";word.reading=@"じょうたつ";word.meaning=@"进步；长进；技艺提高。";
    FYGrammarItem *grammar=[FYGrammarItem new];grammar.name=@"〜ても";grammar.matchedText=@"得意でも";grammar.matchedRange=[source rangeOfString:grammar.matchedText];grammar.meaning=@"即使……也……";grammar.explanation=@"即使擅长画画，也仍然需要每天练习。";
    FYAnalysisResult *analysis=[FYAnalysisResult new];analysis.status=FYAnalysisStatusSuccess;analysis.sentenceID=app.quickSentenceID;analysis.version=1;analysis.vocabulary=@[word];analysis.grammar=@[grammar];
    app.quickSentenceAnalysis=analysis;app.quickSentenceAnalysisSource=source;
    [app renderQuickSentence];Layout(app);view=app.quickSourceTextView;
    Pump(^BOOL{return [Tip(view,@"上達") containsString:@"进步"] && [Tip(view,@"得意") containsString:@"〜ても"];});
    // Let dictionary callbacks finish: analyzed Chinese meaning/grammar retain precedence.
    dispatch_sync([app.japaneseTokenizer valueForKey:@"queue"],^{});Tick();Tick();
    Require([Tip(view,@"上達") containsString:@"AI 解析"] && [Tip(view,@"得意") containsString:@"仍然需要"],@"quick analysis overrides dictionary and overlapping grammar ranges have priority");
    [app.quickSentencePanel makeKeyAndOrderFront:nil];Layout(app);
    NSPanel *card=ShowHover(view,@"上達");
    Require([card.contentView isKindOfClass:FYAdventurePanel.class] && NSWidth(card.frame)==320 && card.ignoresMouseEvents && !card.canBecomeKeyWindow && view.selectedRange.length==0,@"quick reader displays actual live-hover card without taking focus or changing selection");
    if(argc>1){NSString *out=[NSString stringWithUTF8String:argv[1]];Snapshot(app.quickSentencePanel.contentView,[out stringByAppendingPathComponent:@"quick-reader.png"]);Snapshot(card.contentView,[out stringByAppendingPathComponent:@"word-hover.png"]);}
    NSEvent *exit=[NSEvent enterExitEventWithType:NSEventTypeMouseExited location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.quickSentencePanel.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
    [view mouseExited:exit];Require(!card.isVisible,@"exiting original dismisses card");
    [view mouseMoved:Move(view,@"上達")];[view dismissSourceHover];Tick();Tick();
    Require(!card.isVisible,@"cancelled dwell cannot reopen card");
    NSRange selection=[source rangeOfString:@"上達"];view.selectedRange=selection;[app refreshQuickSentenceHoverTips];Tick();
    Require(NSEqualRanges(view.selectedRange,selection),@"refresh preserves native selection");
    NSPasteboard *pasteboard=[NSPasteboard pasteboardWithUniqueName];
    Require([view writeSelectionToPasteboard:pasteboard types:@[NSPasteboardTypeString]] && [[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:@"上達"],@"selected native source copies exactly to private pasteboard");
    [pasteboard releaseGlobally];
    view.selectedRange=NSMakeRange(0,0);card=ShowHover(view,@"上達");[app closeStudyOverlay:nil];
    Require(!card.isVisible,@"closing quick reader dismisses visible hover");

    NSString *longSource=[@[@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。",@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。",@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。",@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。",@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。",@"仲間と一緒に遠い町まで歩いて、新しい景色を見つけた。"] componentsJoinedByString:@"\n"];
    RenderSentence(app,longSource);view=app.quickSourceTextView;
    view.selectedRange=NSMakeRange(0,2);CGFloat narrowHeight=0;
    for(NSNumber *width in @[@440,@680,@440]){
        [app.quickSentencePanel setContentSize:NSMakeSize(width.doubleValue,500)];Layout(app);
        NSRect used=[view.layoutManager usedRectForTextContainer:view.textContainer];
        Require(NSMaxY(used)<=NSHeight(view.bounds)+1 && fabs(view.textContainer.containerSize.width-NSWidth(view.bounds))<1,@"wrapped native source has sufficient natural height at actual width");
        Require([view.string isEqualToString:longSource] && NSEqualRanges(view.selectedRange,NSMakeRange(0,2)) && fabs(view.font.pointSize-19)<.1,@"resize preserves full characters, selection and 19 pt font");
        if(width.integerValue==440){narrowHeight=NSHeight(view.bounds);}else{Require(NSHeight(view.bounds)<narrowHeight,@"wider quick source shrinks naturally without retaining blank narrow height");}
    }
    Pump(^BOOL{return [Tip(view,@"仲間") containsString:@"JMdict"];});
    view.selectedRange=NSMakeRange(0,0);card=ShowHover(view,@"仲間");
    NSScrollView *scroll=view.enclosingScrollView;
    Require(NSHeight(scroll.documentView.frame)>NSHeight(scroll.contentView.bounds)+30,@"long source lives in genuinely scrollable quick document");
    [scroll.contentView scrollToPoint:NSMakePoint(0,30)];[scroll reflectScrolledClipView:scroll.contentView];Tick();
    Require(!card.isVisible,@"scrolling the surrounding quick document dismisses hover");
    CheckLateCallbacks(app);
    Require([app.learningCoordinator.currentSentenceID isEqualToString:pinned.sentenceID],@"all quick reading actions preserve main pinned identity");
    RenderSentence(app,@"");Require(app.quickSourceTextView==nil,@"empty quick reader does not mount fake hover text");
    [app closeStudyOverlay:nil];[app.mainWindow orderOut:nil];
    __block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){Require(!error,@"close isolated store");closed=YES;}];Pump(^BOOL{return closed;});
    NSLog(@"PASS: quick source hover, dictionary and analyzed meaning, native selection/copy, outer scrolling, width-dependent height, stale callback/identity/close isolation");return 0;
} }
