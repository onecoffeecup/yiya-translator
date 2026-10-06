#import "LearningAppTestSupport.h"
@interface FYImmersiveTestApp : AppDelegate
@end
@implementation FYImmersiveTestApp
- (BOOL)translationTargetIsForeground {return YES;}
@end
static void Screenshot(NSView *view,NSString *path){[view layoutSubtreeIfNeeded];NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"screenshot write failed");}
static void CheckQuickWindowDrag(AppDelegate *app) {
    NSView *host=app.quickSentencePanel.contentView;
    [host layoutSubtreeIfNeeded];
    FYOverlayDragHeader *header=nil;
    for(NSView *view in host.subviews){if([view isKindOfClass:FYOverlayDragHeader.class])header=(FYOverlayDragHeader *)view;}
    Require(header!=nil,@"quick sentence has a draggable title area");
    NSStackView *titles=(NSStackView *)header.arrangedSubviews.firstObject;
    for(NSTextField *title in titles.arrangedSubviews){
        NSPoint point=[title convertPoint:NSMakePoint(NSMidX(title.bounds),NSMidY(title.bounds)) toView:header.superview];
        Require([header hitTest:point]==header && !title.selectable,@"dragging either title must reach window drag instead of text selection");
    }
    NSButton *close=(NSButton *)header.arrangedSubviews.lastObject;
    NSPoint point=[close convertPoint:NSMakePoint(NSMidX(close.bounds),NSMidY(close.bounds)) toView:header.superview];
    Require([header hitTest:point]==close,@"close button must remain clickable inside drag header");
    Require([header acceptsFirstMouse:nil],@"inactive game overlay accepts its first drag");
    NSTextField *reading=[app quickReadingLabel:@"原句と訳文" size:19 weight:NSFontWeightRegular color:app.uiInk];
    Require(reading.selectable,@"reading text outside the title remains selectable");
}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];
    FYImmersiveTestApp *emptyApp=[FYImmersiveTestApp new];[emptyApp createMainWindow];[emptyApp createCaptionWindow];[emptyApp showStudyChatOverlay:nil];
    for(NSUInteger cycle=0;cycle<100;cycle++){
        [emptyApp refreshStudyChatViews];Tick();
        Require(fabs(NSWidth(emptyApp.studyChatPanel.frame)-340)<1 && NSHeight(emptyApp.studyChatPanel.frame)>=500,@"empty conversation keeps intended width and useful height");
        NSScrollView *viewport=[emptyApp.overlayStudyChatView valueForKey:@"messagesScroll"];
        Require(NSWidth(viewport.frame)>250 && NSHeight(viewport.frame)>100,@"chat viewport remains usable, not clipped to a strip");
        if(cycle%20==0){[emptyApp closeStudyOverlay:nil];[emptyApp showStudyChatOverlay:nil];}
    }
    [emptyApp closeStudyOverlay:nil];[emptyApp.mainWindow orderOut:nil];[emptyApp.captionPanel orderOut:nil];[emptyApp.captionDockPanel orderOut:nil];
    FYStudyChatSession *session=[FYStudyChatSession new];session.analyzer.baseURL=@"https://example.invalid/v1";session.analyzer.apiKey=@"test-only";session.analyzer.model=@"mock-model";
    __block void (^pending)(NSData *,NSURLResponse *,NSError *);__block NSDictionary *payload;
    session.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){pending=[done copy];payload=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];};
    [session referenceSource:@"絵が得意でも、練習が必要だ。" translation:@"即使擅长，也需要练习。"];
    [session send:@"为什么用でも？"];
    Require(session.sending && session.messages.count==1,@"one send becomes pending and records its reference");
    [session send:@"重复提交"];
    Require(session.messages.count==1,@"pending send cannot duplicate question");
    Require([payload[@"messages"][1][@"content"] containsString:@"絵が得意"],@"API gets actual referenced source");
    pending(Envelope(@"这是让步表达。"),Response(),nil);Pump(^BOOL{return !session.sending;});
    Require(session.messages.count==2,@"answer appended to shared history");
    [session send:@"再解释一次"];void (^old)(NSData *,NSURLResponse *,NSError *)=[pending copy];
    [session referenceSource:@"雨が降った。" translation:@"下雨了。"];
    NSUInteger before=session.messages.count;old(Envelope(@"过期回复"),Response(),nil);Tick();Require(session.messages.count==before,@"late answer cannot overwrite changed context");
    [session send:@"这句什么意思？"];Require([[(NSArray *)payload[@"messages"] lastObject][@"content"] containsString:@"雨が降った"],@"latest reference is explicit and used by next question");
    pending(nil,nil,[NSError errorWithDomain:@"mock" code:500 userInfo:@{NSLocalizedDescriptionKey:@"模拟失败"}]);Pump(^BOOL{return !session.sending;});Require([session.messages.lastObject[@"status"] isEqualToString:@"error"],@"failure visible and sending recovers");
    FYImmersiveTestApp *app=[FYImmersiveTestApp new];[app createMainWindow];[app createCaptionWindow];
    app.captionPanelShownByUser=YES;[app updateCaptionAppearance];[app.captionPanel.contentView layoutSubtreeIfNeeded];
    Require(NSHeight(app.captionPanel.frame)>=140 && NSHeight(app.captionContainer.frame)>=140,@"caption body cannot collapse to line");
    for(NSView *control in app.captionContainer.subviews){
        if([control isKindOfClass:NSButton.class] && [[(NSButton *)control title] isEqualToString:@"看原句"]){
            Require(NSWidth(control.frame)>45 && NSHeight(control.frame)>=30,@"sentence button has visible clickable frame");
            [(NSButton *)control performClick:nil];Require(app.quickSentencePanel.isVisible,@"actual sentence button opens quick panel");[app closeStudyOverlay:nil];
        }
    }
    Require(app.mainStudyChatView.window==app.mainWindow,@"main rail is integrated");
    [app toggleMainStudyChat:nil];Require(app.mainStudyChatView.hidden && app.mainStudyChatView.window==app.mainWindow && app.workspaceWidth.constant==-190,@"collapse hides the rail and releases its width without destroying the chat view");
    [app toggleMainStudyChat:nil];Require(!app.mainStudyChatView.hidden && app.mainStudyChatView.window==app.mainWindow && app.workspaceWidth.constant==-510,@"reopen restores the same chat view and width");
    app.studyChatSession=session;[app refreshStudyChatViews];
    NSRect dockScreen=NSScreen.mainScreen.visibleFrame;
    [app.captionPanel setFrame:NSMakeRect(NSMinX(dockScreen)+80,NSMinY(dockScreen)+150,900,180) display:NO];
    [app hideCaptionPanel:nil];[app.captionDockPanel.contentView layoutSubtreeIfNeeded];Require(NSHeight(app.captionDockPanel.contentView.frame)>=46 && NSWidth(app.captionDockPanel.contentView.frame)>=260,@"dock keeps full content bounds");Require(!app.captionPanel.isVisible && app.captionDockPanel.isVisible,@"collapsed caption retains visible recovery dock");
    NSRect collapsedDock=app.captionDockPanel.frame;
    Require(fabs(NSMinY(collapsedDock)-NSMinY(app.captionPanel.frame))<1 && fabs(NSMidX(collapsedDock)-NSMidX(app.captionPanel.frame))<1,@"collapse keeps the prototype baseline and horizontal center");
    NSString *hiddenLongText=[@"隐藏时新译文仍会更新，但是恢复小条不能随着文本长度掉到底部。" stringByPaddingToLength:700 withString:@"长译文测试。" startingAtIndex:0];
    [app resizeCaptionWindowForText:hiddenLongText];
    for(NSUInteger cycle=0;cycle<12;cycle++){[app refreshOverlayVisibility:nil];Tick();}
    Require(NSEqualRects(app.captionDockPanel.frame,collapsedDock),@"hidden long translations and visibility refresh cannot move recovery dock");
    NSPoint draggedDock=NSMakePoint(NSMinX(collapsedDock)+20,NSMinY(collapsedDock)+40);
    [app.captionDockPanel setFrameOrigin:draggedDock];[app hideCaptionPanel:nil];[app refreshOverlayVisibility:nil];
    Require(NSEqualPoints(app.captionDockPanel.frame.origin,draggedDock),@"repeated collapse and refresh preserve a manually moved dock");
    [app showCaptionPanel:nil];Require(app.captionPanel.isVisible && !app.captionDockPanel.isVisible,@"expand returns caption and hides dock");
    Require(fabs(NSMinY(app.captionPanel.frame)-draggedDock.y)<1 && fabs(NSMidX(app.captionPanel.frame)-NSMidX(app.captionDockPanel.frame))<1,@"expand restores subtitle at current dock baseline");
    [app showStudyChatOverlay:nil];
    NSRect stableChatFrame=app.studyChatPanel.frame;
    for(NSUInteger cycle=0;cycle<80;cycle++){
        Tick();Require(fabs(NSWidth(app.studyChatPanel.frame)-NSWidth(stableChatFrame))<1 && fabs(NSHeight(app.studyChatPanel.frame)-NSHeight(stableChatFrame))<1,@"idle AI panel must not grow with each layout pass");
    }
    NSString *longReply=[@"这是一段用于检查消息滚动区的长回复。" stringByPaddingToLength:10000 withString:@"长回复应滚动，不应扩大窗口。\n" startingAtIndex:0];
    [app.overlayStudyChatView setMessages:@[@{@"role":@"assistant",@"content":longReply}]];
    for(NSUInteger cycle=0;cycle<40;cycle++){
        Tick();Require(fabs(NSWidth(app.studyChatPanel.frame)-NSWidth(stableChatFrame))<1 && fabs(NSHeight(app.studyChatPanel.frame)-NSHeight(stableChatFrame))<1,@"long reply stays inside fixed scrolling viewport");
    }
    Require(app.studyChatPanel.isVisible && !app.quickSentencePanel.isVisible,@"AI opens alone");
    [app closeStudyOverlay:nil];[app showStudyChatOverlay:nil];Require(app.studyChatSession==session && session.messages.count>2,@"closing overlay preserves shared messages");
    [app showQuickSentence:nil];Require(app.quickSentencePanel.isVisible && !app.studyChatPanel.isVisible,@"quick sentence replaces only overlay");
    CheckQuickWindowDrag(app);
    if(argc>1){Screenshot(app.quickSentencePanel.contentView,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"native-quick-sentence.png"]);}
    app.quickSentenceSource=[@"相談あったら何でも聞いて？お店に来てくれたらサービスしちゃう！" stringByPaddingToLength:500 withString:@"相談あったら何でも聞いて？" startingAtIndex:0];
    app.quickSentenceTranslation=[@"如果有什么想商量的事情，可以随时来问我。" stringByPaddingToLength:500 withString:@"你可以来找我。" startingAtIndex:0];[app renderQuickSentence];Tick();
    Require(NSWidth(app.quickSentencePanel.frame)<=442,@"long original and translation wrap without widening quick panel");
    Require((app.mainWindow.styleMask & NSWindowStyleMaskResizable) && (app.studyChatPanel.styleMask & NSWindowStyleMaskResizable) && (app.quickSentencePanel.styleMask & NSWindowStyleMaskResizable),@"all three windows expose native edge resizing");
    [app.quickSentencePanel setContentSize:NSMakeSize(700,760)];Tick();
    [app renderQuickSentence];Tick();
    CheckQuickWindowDrag(app);
    Require(fabs(NSWidth(app.quickSentencePanel.contentView.bounds)-700)<1 && fabs(NSHeight(app.quickSentencePanel.contentView.bounds)-760)<1,@"quick result refresh preserves manually enlarged content size");
    [app closeStudyOverlay:nil];[app showQuickSentence:nil];Tick();
    Require(fabs(NSWidth(app.quickSentencePanel.frame)-700)<1,@"reopening quick panel preserves user width");
    // 内联块查句卡（440×500）：标题必须完整显示「已固定」，关闭按钮贴卡片右端。
    // AppKit 的 NSStackView 默认 GravityAreas 会把两者挤在卡片中间，标题截成「选中内容 ·」。
    [app openInlineLearningForBlockText:@"カレンさんでーす！\n初メールしました！" translation:@"我是卡莲！第一次给你发邮件。"];
    Pump(^BOOL{return !app.quickSentenceAnalyzing;});
    [app.quickSentencePanel setContentSize:NSMakeSize(440,500)];Tick();
    {
        NSTextField *headline=nil;NSButton *close=nil;
        NSMutableArray<NSView *> *queue=[NSMutableArray arrayWithObject:app.quickSentencePanel.contentView];
        while(queue.count>0){
            NSView *view=queue.firstObject;[queue removeObjectAtIndex:0];
            for(NSView *child in view.subviews){
                if([child isKindOfClass:NSTextField.class] && [((NSTextField *)child).stringValue hasPrefix:@"选中内容"]){headline=(NSTextField *)child;}
                if([child isKindOfClass:NSButton.class] && [[(NSButton *)child toolTip] hasPrefix:@"收起"]){close=(NSButton *)child;}
                [queue addObject:child];
            }
        }
        Require(headline!=nil && [headline.stringValue isEqualToString:@"选中内容 · 已固定"],
                @"quick card headline must stay complete (no 选中内容 · truncation)");
        // 浮动学习卡仍然保留「问 AI」，主界面那套入口被移除不影响它。
        BOOL hasAskAI=NO;
        NSMutableArray<NSView *> *askStack=[NSMutableArray arrayWithObject:app.quickSentencePanel.contentView];
        while(askStack.count>0){NSView *v=askStack.firstObject;[askStack removeObjectAtIndex:0];
            if([v isKindOfClass:NSButton.class] && [[(NSButton *)v title] containsString:@"问 AI"]){hasAskAI=YES;}
            for(NSView *c in v.subviews){[askStack addObject:c];}}
        Require(hasAskAI,@"the floating learning card must keep its 问 AI entry");
        NSRect closeInCard=[close convertRect:close.bounds toView:app.quickSentencePanel.contentView];
        Require(close!=nil && NSWidth(app.quickSentencePanel.contentView.bounds)-NSMaxX(closeInCard)<34,
                @"the quick card close button must sit at the card's right edge");
    }
    [app closeStudyOverlay:nil];Tick();
    [app showStudyChatOverlay:nil];[app.studyChatPanel setContentSize:NSMakeSize(600,800)];Tick();
    NSScrollView *resizedChat=[app.overlayStudyChatView valueForKey:@"messagesScroll"];
    Require(NSWidth(resizedChat.contentView.bounds)>500,@"AI message viewport expands with manual resize");
    [app closeStudyOverlay:nil];[app showStudyChatOverlay:nil];Tick();
    for(NSUInteger cycle=0;cycle<20;cycle++){[app refreshStudyChatViews];Tick();Require(fabs(NSWidth(app.studyChatPanel.frame)-600)<1 && fabs(NSHeight(app.studyChatPanel.frame)-800)<1,@"AI reopen and refresh keep resized frame stable");}
    [app.mainWindow setContentSize:NSMakeSize(1000,660)];Tick();
    CGFloat compactWorkspaceWidth=NSWidth(app.mainWorkspaceRoot.frame);
    [app.mainWindow setContentSize:NSMakeSize(1150,740)];Tick();
    Require(NSWidth(app.mainWorkspaceRoot.frame)>compactWorkspaceWidth+100 && fabs(NSWidth(app.mainWorkspaceRoot.frame)-NSWidth(app.mainWindow.contentView.bounds))<1,@"main workspace expands with window resize within available screen");
    [app showQuickSentence:nil];Tick();
    [app.quickSentencePanel cancelOperation:nil];Require(!app.quickSentencePanel.isVisible,@"Escape closes quick view");
    NSString *db=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"]];
    FYLearningStore *store=Store(db);FYGrammarCatalog *catalog=[FYGrammarCatalog new];
    app.learningStore=store;app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    FYRequestIdentity *first=[app.learningCoordinator recordText:@"前の句です。" kind:FYSentenceKindDialogue];[app.learningCoordinator setTranslation:@"上一句。" forIdentity:first];[app.learningCoordinator pinCurrent];
    FYRequestIdentity *latest=[app.learningCoordinator recordText:@"新しい句です。" kind:FYSentenceKindDialogue];[app.learningCoordinator setTranslation:@"新的一句。" forIdentity:latest];Drain(store);
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return [session.source isEqualToString:@"新しい句です。"];});
    Require([app.learningCoordinator.currentSourceText isEqualToString:@"前の句です。"],@"chat latest lookup preserves pinned reading source");
    [app showQuickSentence:nil];Pump(^BOOL{return [app.quickSentenceSource isEqualToString:@"新しい句です。"];});
    [app.learningCoordinator recordText:@"さらに次の句。" kind:FYSentenceKindDialogue];Drain(store);
    [app askQuickSentence:nil];Require([session.source isEqualToString:@"新しい句です。"],@"asking quick sentence freezes displayed snapshot despite new OCR");
    app.framePreview.image=[[NSImage alloc] initWithContentsOfFile:@".build/workspace-scene.png"];app.previewPlaceholder.hidden=YES;
    app.learningSourceTextView.string=@"絵が得意でも、毎日練習しないと上達しない。";app.learningTranslationLabel.stringValue=@"即使擅长画画，不每天练习也不会进步。";
    [app.mainWindow orderFront:nil];Tick();
    if(argc>1){NSString *out=[NSString stringWithUTF8String:argv[1]];Screenshot(app.mainWindow.contentView,[out stringByAppendingPathComponent:@"native-three-column.png"]);Screenshot(app.captionPanel.contentView,[out stringByAppendingPathComponent:@"native-caption.png"]);Screenshot(app.captionDockPanel.contentView,[out stringByAppendingPathComponent:@"native-caption-dock.png"]);[app showStudyChatOverlay:nil];Screenshot(app.studyChatPanel.contentView,[out stringByAppendingPathComponent:@"native-chat-overlay.png"]);}
    [app closeStudyOverlay:nil];[app.captionPanel orderOut:nil];[app.captionDockPanel orderOut:nil];[app.mainWindow orderOut:nil];
    NSLog(@"PASS: isolated chat context, history, failures, stale replies, three-column toggle, recovery dock, independent AI and quick sentence panels");
}return 0;}
