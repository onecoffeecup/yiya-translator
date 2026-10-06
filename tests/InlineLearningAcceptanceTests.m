#import "LearningAppTestSupport.h"

// Independent acceptance probes. Mock services and temporary data only;
// collect all failures so one broken entry point does not hide later defects.
@interface FYInlineAcceptanceApp : AppDelegate
@end
@implementation FYInlineAcceptanceApp
- (BOOL)translationTargetIsForeground { return YES; }
@end
static NSUInteger failures = 0;
static void Audit(BOOL condition, NSString *name, NSString *evidence) {
    if (!condition) failures++;
    NSLog(@"AUDIT %@: %@ — %@",condition?@"PASS":@"FAIL",name,evidence);
}
static OCRTextItem *Line(NSString *text, CGRect box) {
    OCRTextItem *item=[OCRTextItem new];item.text=text;item.boundingBox=box;return item;
}
static NSScrollView *QuickScroll(AppDelegate *app) {
    for(NSView *view in app.quickSentencePanel.contentView.subviews)
        if([view isKindOfClass:NSScrollView.class])return (NSScrollView *)view;
    return nil;
}
static void Shot(NSView *view,NSString *path) {
    [view layoutSubtreeIfNeeded];
    if(NSWidth(view.bounds)<1 || NSHeight(view.bounds)<1){NSLog(@"AUDIT SCREENSHOT UNAVAILABLE: zero-sized view %@",path);return;}
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"audit screenshot");
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *out=[NSString stringWithUTF8String:argv[1]];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"inline-audit.sqlite3"];
    FYLearningStore *store=Store(path);
    FYGrammarCatalog *catalog=[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Require([catalog loadWithError:NULL],@"catalog");
    FYInlineAcceptanceApp *app=[FYInlineAcceptanceApp new];
    app.learningStore=store;app.learningAnalyzer=Analyzer(catalog);app.grammarCatalog=catalog;
    app.japaneseTokenizer=[FYJapaneseTokenizer new];
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:app.learningAnalyzer tokenizer:app.japaneseTokenizer catalog:catalog];
    app.inlineTranslationPanels=[NSMutableArray new];app.inlineLongCardPanels=[NSMutableArray new];
    [app createMainWindow];
    app.baseURLField.stringValue=@"https://example.invalid/v1";app.apiKeyField.stringValue=@"audit-dummy-key";app.modelField.stringValue=@"audit-model";
    app.quickSentenceAnalyzer=Analyzer(catalog);

    OCRTextItem *wideButton=[[app mergedInlineTextItemsFromItems:@[Line(@"戻る",CGRectMake(.1,.7,.30,.03))]] firstObject];
    Audit(wideButton.blockKind==InlineBlockKindShort,@"short wide label remains noninteractive",[NSString stringWithFormat:@"kind=%ld",(long)wideButton.blockKind]);
    NSArray *menu=[app mergedInlineTextItemsFromItems:@[
        Line(@"キャラクターの設定",CGRectMake(.1,.70,.28,.03)),
        Line(@"サウンドの設定変更",CGRectMake(.1,.65,.28,.03)),
        Line(@"コントローラー設定",CGRectMake(.1,.60,.28,.03))]];
    Audit(menu.count==3,@"independent menu entries remain separate",[NSString stringWithFormat:@"blocks=%lu, text=%@",(unsigned long)menu.count,[menu valueForKey:@"text"]]);

    NSString *source=@"カレンさんでーす！\n初メールしました！\nこれからメールでも\nヨロシクね♥";
    OCRTextItem *item=[[app mergedInlineTextItemsFromItems:@[Line(source,CGRectMake(.55,.35,.3,.2))]] firstObject];
    NSPanel *card=[app inlineLongPanelForTranslation:@"我是卡莲！第一次给你发邮件，以后邮件里也请多关照。" item:item frame:NSMakeRect(100,100,340,170)];
    [card orderFrontRegardless];Tick();[card.contentView layoutSubtreeIfNeeded];
    NSScrollView *cardScroll=nil;
    for(NSView *child in card.contentView.subviews) if([child isKindOfClass:NSScrollView.class]) cardScroll=(NSScrollView *)child;
    NSTextField *cardText=(NSTextField *)cardScroll.documentView;
    NSPoint textPoint=[cardText convertPoint:NSMakePoint(NSMidX(cardText.bounds),NSMidY(cardText.bounds)) toView:card.contentView.superview];
    NSView *cardHit=[card.contentView hitTest:textPoint];
    Audit(NSHeight(cardScroll.documentView.frame)>20 && NSWidth(cardText.frame)>20,@"long-card document has readable geometry",[NSString stringWithFormat:@"doc=%@ text=%@",NSStringFromRect(cardScroll.documentView.frame),NSStringFromRect(cardText.frame)]);
    if(NSHeight(cardScroll.documentView.frame)>20)
        Audit(cardHit==card.contentView,@"long-card text click reaches its learning handler",[NSString stringWithFormat:@"hit=%@, selectable=%d",NSStringFromClass(cardHit.class),cardText.selectable]);
    else NSLog(@"AUDIT NOT RUN: long-card click blocked by zero document geometry; panel=%@ content=%@",NSStringFromRect(card.frame),NSStringFromRect(card.contentView.bounds));
    Shot(card.contentView,[out stringByAppendingPathComponent:@"long-card.png"]);

    [app openInlineLearningForBlockText:source translation:@"我是卡莲！第一次给你发邮件，以后邮件里也请多关照。"];
    Pump(^BOOL{return !app.quickSentenceAnalyzing;});
    Audit(app.inlineBlockSnapshot.lineBoxes.count>0,@"selected snapshot retains source line rectangles",[NSString stringWithFormat:@"lineBoxes=%lu",(unsigned long)app.inlineBlockSnapshot.lineBoxes.count]);
    FYAnalysisResult *analysis=[FYAnalysisResult new];analysis.status=FYAnalysisStatusSuccess;
    FYGrammarItem *g=[FYGrammarItem new];g.name=@"〜ました";g.meaning=@"礼貌的过去表达";g.connection=@"动词ます形去掉ます，加ました";g.matchedText=@"しました";g.matchedRange=[source rangeOfString:g.matchedText];
    g.explanation=[@"本句表示已经完成的动作。\n" stringByPaddingToLength:550 withString:@"本句表示已经完成的动作。\n" startingAtIndex:0];
    analysis.grammar=@[g];app.quickSentenceAnalysis=analysis;app.quickSentenceAnalysisSource=source;app.quickSentenceAnalysisTranslation=app.quickSentenceTranslation;
    [app renderQuickSentence];[app.quickSentencePanel setContentSize:NSMakeSize(440,500)];Tick();
    NSScrollView *scroll=QuickScroll(app);[scroll.contentView scrollToPoint:NSMakePoint(0,40)];[scroll reflectScrolledClipView:scroll.contentView];
    CGFloat before=scroll.contentView.bounds.origin.y;
    Require(before>30,@"scroll fixture must actually scroll");
    Shot(app.quickSentencePanel.contentView,[out stringByAppendingPathComponent:@"grammar.png"]);
    [app askQuickSentence:nil];Tick();
    [app.studyChatPanel.contentView layoutSubtreeIfNeeded];
    NSPoint returnPoint=[app.inlineReturnButton convertPoint:NSMakePoint(NSMidX(app.inlineReturnButton.bounds),NSMidY(app.inlineReturnButton.bounds)) toView:app.studyChatPanel.contentView.superview];
    NSView *returnHit=[app.studyChatPanel.contentView hitTest:returnPoint];
    Audit(!app.inlineReturnButton.hidden && returnHit==app.inlineReturnButton,@"return button is visible and reachable",[NSString stringWithFormat:@"hidden=%d hit=%@",app.inlineReturnButton.hidden,NSStringFromClass(returnHit.class)]);
    Shot(app.studyChatPanel.contentView,[out stringByAppendingPathComponent:@"ai.png"]);
    [app returnFromStudyChatToInlineLearning:nil];Tick();
    CGFloat after=QuickScroll(app).contentView.bounds.origin.y;
    Audit(fabs(after-before)<1,@"return preserves grammar scroll",[NSString stringWithFormat:@"before=%.1f after=%.1f",before,after]);

    [app askQuickSentence:nil];
    [app.overlayStudyChatView restoreDraftText:@"块 A 的未发送草稿"];
    __block void (^answerDone)(NSData *,NSURLResponse *,NSError *);
    app.studyChatSession.analyzer=Analyzer(catalog);
    app.studyChatSession.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){answerDone=[done copy];};
    [app.studyChatSession send:@"请解释块 A 的语法"];
    Require(app.studyChatSession.sending && answerDone!=nil,@"pending chat fixture");
    [app returnFromStudyChatToInlineLearning:nil];[app askQuickSentence:nil];
    Audit(app.studyChatSession.sending,@"same-block round trip keeps pending AI request",[NSString stringWithFormat:@"sending=%d",app.studyChatSession.sending]);
    answerDone(Envelope(@"块 A 的回答"),Response(),nil);Tick();
    Audit(app.studyChatSession.messages.count==2,@"pending answer survives same-block round trip",[NSString stringWithFormat:@"messages=%lu",(unsigned long)app.studyChatSession.messages.count]);

    [app openInlineLearningForBlockText:@"明日は図書館で一緒に勉強しましょう。" translation:@"明天一起去图书馆学习吧。"];
    Pump(^BOOL{return !app.quickSentenceAnalyzing;});[app askQuickSentence:nil];
    NSTextView *input=[app.overlayStudyChatView valueForKey:@"input"];
    Audit(app.studyChatSession.messages.count==0 && input.string.length==0,@"switching blocks isolates history and draft",[NSString stringWithFormat:@"messages=%lu draft=%@",(unsigned long)app.studyChatSession.messages.count,input.string]);

    // Same-size capped cards are reused when changing articles; the scroll document must grow.
    NSString *huge=[@"这是一段需要完整滚动阅读的新文章。" stringByPaddingToLength:1800 withString:@"这是一段需要完整滚动阅读的新文章。" startingAtIndex:0];
    NSPanel *reuse=[app inlineLongPanelForTranslation:[huge substringToIndex:600] item:item frame:NSMakeRect(100,100,340,240)];
    [app updateInlineLongCard:reuse translation:huge item:item frame:reuse.frame];
    NSScrollView *reuseScroll=nil;
    for(NSView *child in reuse.contentView.subviews) if([child isKindOfClass:NSScrollView.class]) reuseScroll=(NSScrollView *)child;
    NSPanel *fresh=[app inlineLongPanelForTranslation:huge item:item frame:reuse.frame];
    NSScrollView *freshScroll=nil;
    for(NSView *child in fresh.contentView.subviews) if([child isKindOfClass:NSScrollView.class]) freshScroll=(NSScrollView *)child;
    Audit(fabs(NSHeight(reuseScroll.documentView.frame)-NSHeight(freshScroll.documentView.frame))<1,@"reused long card updates document height for new translation",[NSString stringWithFormat:@"docHeight=%.0f viewport=%.0f chars=%lu",NSHeight(reuseScroll.documentView.frame),NSHeight(reuseScroll.contentView.bounds),(unsigned long)huge.length]);
    FYInlineBlockSnapshot *chosen=[app inlineSnapshotForItem:item translation:@"原块"];
    app.inlineBlockSnapshot=chosen;
    OCRTextItem *duplicate=Line(item.text,CGRectMake(.1,.1,.2,.1));
    Audit(![app inlineBlockIsSelectedForItem:duplicate],@"identical text at another position is not marked selected",@"same source text, different source rectangle");
    [reuse close];[fresh close];
    [card orderOut:nil];[app closeStudyOverlay:nil];[app.mainWindow orderOut:nil];
    __block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){closed=YES;}];Pump(^BOOL{return closed;});
    NSLog(@"AUDIT SUMMARY: %lu failures; production source unchanged by audit",(unsigned long)failures);
    return failures ? 1 : 0;
} }
