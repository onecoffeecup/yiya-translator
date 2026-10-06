#import "LearningAppTestSupport.h"

static FYLearningColumnsView *Columns(NSView *view) {
    if ([view isKindOfClass:FYLearningColumnsView.class]) { return (FYLearningColumnsView *)view; }
    for (NSView *child in view.subviews) { FYLearningColumnsView *value = Columns(child); if (value) { return value; } }
    return nil;
}
static void Render(AppDelegate *app, NSString *path) {
    [app.mainWindow.contentView layoutSubtreeIfNeeded];
    [app.mainWindow displayIfNeeded];
    NSView *view = app.mainWindow.contentView;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    Require(bitmap != nil, @"render bitmap unavailable");
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"render write failed");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Require(argc == 2, @"output directory argument required");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *output = [NSString stringWithUTF8String:argv[1]];
        NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"fuyi-native-ui-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        FYLearningStore *store = Store(temp);
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL], @"catalog missing");
        AppDelegate *app = App(store, Analyzer(catalog), catalog);
        app.mainWindow.title = @"浮译 · 独立 UI 审查窗口";
        // Same background that NSWindow provides; make offscreen bitmaps opaque.
        app.mainWindow.contentView.wantsLayer = YES;
        app.mainWindow.contentView.layer.backgroundColor = app.mainWindow.backgroundColor.CGColor;
        NSString *source = @"仲間を助けるために、\n危険だとわかっていても、\n進まざるを得ない。";
        FYRequestIdentity *identity = [app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
        [app.learningCoordinator setTranslation:@"为了救同伴，即使明知有危险，\n也不得不继续前进。" forIdentity:identity];
        [app.learningCoordinator pinCurrent]; [app refreshLearningSource]; [app refreshLearningStatus];
        app.latestTranslationLabel.stringValue = @"为了救同伴，即使明知有危险，\n也不得不继续前进。";
        app.latestSourceLabel.stringValue = source;
        Bookmark(app, @"仲間", @"仲間", @"なかま", @"同伴；伙伴");
        Bookmark(app, @"助ける", @"助ける", @"たすける", @"帮助；救助");
        FYGrammarItem *g1 = [FYGrammarItem new]; g1.name = @"〜ざるを得ない"; g1.matchedText = @"進まざるを得ない";
        g1.matchedRange = [source rangeOfString:g1.matchedText]; g1.referenceLevel = @"N2";
        g1.connection = @"动词ない形去掉「ない」＋ざるを得ない；「する」用「せざるを得ない」。";
        g1.meaning = @"没有其他选择，不得不做某事。"; g1.explanation = @"强调为了救同伴而不得不前进。";
        FYGrammarItem *g2 = [FYGrammarItem new]; g2.name = @"〜ために"; g2.matchedText = @"ために";
        g2.matchedRange = [source rangeOfString:g2.matchedText]; g2.meaning = @"为了。";
        FYAnalysisResult *analysis = [FYAnalysisResult new]; analysis.status = FYAnalysisStatusSuccess;
        analysis.sentenceID = identity.sentenceID; analysis.version = 1; analysis.grammar = @[g1, g2];
        app.currentAnalysis = analysis; [app refreshGrammarResults];
        Require(app.framePreview.frame.size.width >= app.learningSourceTextView.enclosingScrollView.frame.size.width - 2, @"game preview must span the reading column");
        Require(app.grammarPageAnalyzeButton.enabled, @"analysis must stay available on the read-only source");
        app.currentAnalysis = analysis; [app refreshGrammarResults];
        [app refreshHistory]; [app refreshVocabularyList];
        Pump(^BOOL { return app.historyRecords.count == 1 && app.reviewList.count == 2; }); Tick();

        // Show only this isolated fictional window, without activating it.
        // No loadSettings/setupLearning, application delegate, capture or real API.
        NSImage *preview = [[NSImage alloc] initWithSize:NSMakeSize(1280, 720)];
        [preview lockFocus];
        [[NSColor colorWithCalibratedRed:0.12 green:0.19 blue:0.26 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, 1280, 720));
        [@"画面预览 · 测试场景" drawAtPoint:NSMakePoint(48, 60) withAttributes:@{
            NSFontAttributeName:[NSFont systemFontOfSize:36], NSForegroundColorAttributeName:NSColor.whiteColor}];
        [preview unlockFocus];
        app.framePreview.image = preview; app.previewPlaceholder.hidden = YES;
        [app.mainWindow orderFront:nil]; Tick();
        [app.mainWindow.contentView layoutSubtreeIfNeeded]; [app.mainWindow displayIfNeeded];
        Require(app.pages.count == 6 && app.pageButtons.count == 6, @"all six navigation pages must exist");
        Require([app.pageButtons[3].title isEqualToString:@"运行设置"] && [app.windowPopup isDescendantOf:app.pages[3]], @"window selection must live on the run settings page");
        Require(![app.windowPopup isDescendantOf:app.pages[0]], @"live page must not contain run settings");
        Require([app.themeSwatches.firstObject isDescendantOf:app.pages[4]], @"caption colors must live on the appearance page");
        [app selectPageAtIndex:3]; Tick();
        Require([app.headerTitleLabel.stringValue isEqualToString:@"运行设置"] && app.pageButtons[3].state == NSControlStateValueOn, @"run settings navigation must select the matching page");
        [app selectPageAtIndex:0]; Tick();
        {
            // 中栏按「画面 → 当前对白 → 中文翻译 → 语法」自上而下；documentView 是 flipped。
            NSView *document = ((NSScrollView *)app.pages[0]).documentView;
            NSRect previewRect = [app.framePreview convertRect:app.framePreview.bounds toView:document];
            NSRect dialogueRect = [app.learningSourceTextView convertRect:app.learningSourceTextView.bounds toView:document];
            NSRect translationRect = [app.learningTranslationLabel convertRect:app.learningTranslationLabel.bounds toView:document];
            NSRect grammarRect = [app.grammarStatusLabel convertRect:app.grammarStatusLabel.bounds toView:document];
            Require(NSMaxY(previewRect) <= NSMinY(dialogueRect) + 2 &&
                    NSMaxY(dialogueRect) <= NSMinY(translationRect) + 2 &&
                    NSMaxY(translationRect) <= NSMinY(grammarRect) + 2,
                    @"live layout must read game, dialogue, translation then grammar vertically");
        }
        CGFloat liveWidth = app.learningSourceTextView.frame.size.width;
        CGFloat liveClip = app.learningSourceTextView.enclosingScrollView.contentView.bounds.size.width;
        Require([app.grammarPageAnalyzeButton isDescendantOf:app.pages[0]] && [app.grammarDetailNameLabel isDescendantOf:app.pages[0]], @"analysis and grammar must live on realtime page");
        Require([app.historyListStack isDescendantOf:app.pages[1]] && ![app.historyListStack isDescendantOf:app.pages[0]], @"history must have its own page");
        Require([app.pageButtons[1].title isEqualToString:@"最近台词"], @"navigation must expose recent dialogue");
        Require(liveWidth > 100 && fabs(liveWidth-liveClip)<2, @"source document width must follow clip width");
        NSButton *historyAction = [NSButton new]; historyAction.identifier = identity.sentenceID; historyAction.tag = 0;
        [app selectPageAtIndex:1]; [app openHistoryAnalysis:historyAction]; Tick();
        Require(app.selectedPage == 0 && app.learningCoordinator.isPinned, @"history selection must return to integrated analysis and pin the source");
        app.currentAnalysis = analysis; [app refreshGrammarResults];

        NSArray<NSString *> *names = @[@"native-live-default.png", @"native-history-default.png", @"native-words-default.png"];
        for (NSUInteger i = 0; i < names.count; i++) {
            [app selectPageAtIndex:i]; Tick(); Render(app, [output stringByAppendingPathComponent:names[i]]);
        }
        [app selectPageAtIndex:3]; Tick(); Render(app, [output stringByAppendingPathComponent:@"native-run-settings-default.png"]);
        [app selectPageAtIndex:4]; Tick(); Render(app, [output stringByAppendingPathComponent:@"native-appearance-default.png"]);
        [app selectPageAtIndex:0];
        [app.mainWindow setFrame:NSMakeRect(140, 120, 980, 660) display:YES]; Tick();
        NSLog(@"MINIMUM WINDOW: outer=%@ content=%@", NSStringFromRect(app.mainWindow.frame), NSStringFromRect(app.mainWindow.contentView.bounds));
        Require(fabs(app.mainWindow.frame.size.width - 980) < 2, @"native minimum window width must be 980");
        {
            NSView *document = ((NSScrollView *)app.pages[0]).documentView;
            NSRect previewSmall = [app.framePreview convertRect:app.framePreview.bounds toView:document];
            NSRect dialogueSmall = [app.learningSourceTextView convertRect:app.learningSourceTextView.bounds toView:document];
            Require(NSMaxY(previewSmall) <= NSMinY(dialogueSmall) + 2,
                    @"minimum live layout keeps the picture above the dialogue card");
        }
        Render(app, [output stringByAppendingPathComponent:@"native-live-minimum.png"]);
        [app selectPageAtIndex:1]; Tick();

        Render(app, [output stringByAppendingPathComponent:@"native-history-minimum.png"]);
        [app selectPageAtIndex:2]; Tick();
        Render(app, [output stringByAppendingPathComponent:@"native-words-minimum.png"]);
        [app selectPageAtIndex:3]; Tick();
        Render(app, [output stringByAppendingPathComponent:@"native-run-settings-minimum.png"]);
        [app selectPageAtIndex:4]; Tick();
        Render(app, [output stringByAppendingPathComponent:@"native-appearance-minimum.png"]);
        [app selectPageAtIndex:0]; [app.mainWindow setContentSize:NSMakeSize(1320, 1000)]; Tick();
        // Test the actual NSTextView tracking loop. A genuine click must open a
        // token selection after super consumes the mouse-up event.
        [app.mainWindow makeFirstResponder:app.learningSourceTextView];
        app.learningSourceTextView.selectedRange = NSMakeRange(0, 0);
        [app.learningSourceTextView.layoutManager ensureLayoutForTextContainer:app.learningSourceTextView.textContainer];
        NSRect glyph = [app.learningSourceTextView.layoutManager boundingRectForGlyphRange:NSMakeRange(0, 1) inTextContainer:app.learningSourceTextView.textContainer];
        NSPoint point = NSMakePoint(NSMidX(glyph) + app.learningSourceTextView.textContainerOrigin.x, NSMidY(glyph) + app.learningSourceTextView.textContainerOrigin.y);
        point = [app.learningSourceTextView convertPoint:point toView:nil];
        NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:1 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:1.1 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
        [NSApp postEvent:up atStart:YES]; [app.learningSourceTextView mouseDown:down];
        Pump(^BOOL { return app.learningSourceTextView.selectedRange.length > 0; });
        Require(!app.wordPickArea.hidden && [app selectedLearningText].length > 0 && app.learningCoordinator.isPinned, @"native word click must pin/select/open inline confirmation");
        Render(app, [output stringByAppendingPathComponent:@"native-word-confirmation.png"]);
        [app closeWordPick:nil];
        NSRect finalGlyph = [app.learningSourceTextView.layoutManager boundingRectForGlyphRange:NSMakeRange(5, 1) inTextContainer:app.learningSourceTextView.textContainer];
        NSPoint end = NSMakePoint(NSMidX(finalGlyph) + app.learningSourceTextView.textContainerOrigin.x, NSMidY(finalGlyph) + app.learningSourceTextView.textContainerOrigin.y);
        end = [app.learningSourceTextView convertPoint:end toView:nil];
        NSEvent *drag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:end modifierFlags:0 timestamp:2 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:3 clickCount:1 pressure:1];
        NSEvent *dragUp = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:end modifierFlags:0 timestamp:2.1 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:4 clickCount:1 pressure:0];
        [NSApp postEvent:dragUp atStart:YES]; [NSApp postEvent:drag atStart:YES];
        [app.learningSourceTextView mouseDown:down];
        Require(app.learningSourceTextView.selectedRange.length > 1 && app.learningCoordinator.isPinned && !app.wordPickArea.hidden, @"native drag selection must open inline confirmation on the pinned source");
        [app closeWordPick:nil];
        [app.learningSourceTextView selectAll:nil];
        Require(app.learningCoordinator.isPinned && app.learningSourceTextView.selectedRange.length == source.length, @"keyboard select-all must keep source pinned");
        [app closeWordPick:nil];
        // Long text wraps inside the source document rather than expanding the window.
        NSString *longText = [@"長い原文の表示確認。" stringByPaddingToLength:500 withString:@"仲間のために道を進む。" startingAtIndex:0];
        [app.learningCoordinator recordText:longText kind:FYSentenceKindDialogue];
        __block BOOL longFollowed = NO; [app.learningCoordinator followLatestWithCompletion:^{ longFollowed = YES; }]; Pump(^BOOL { return longFollowed; }); [app refreshLearningSource]; Tick();
        [app.mainWindow setFrame:NSMakeRect(140, 120, 980, 660) display:YES]; Tick();
        Require(fabs(app.mainWindow.frame.size.width - 980) < 2 && app.learningSourceTextView.frame.size.width == app.learningSourceTextView.enclosingScrollView.contentView.bounds.size.width, @"long source must wrap without widening minimum window");
        Render(app, [output stringByAppendingPathComponent:@"native-long-source.png"]);
        [app.mainWindow orderOut:nil];

        __block BOOL closed = NO; [store closeWithCompletion:^(NSError *e) { Require(!e, @"store close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
        [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[temp stringByAppendingString:@"-wal"] error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[temp stringByAppendingString:@"-shm"] error:NULL];
        NSLog(@"PASS: Native UI acceptance complete. Only the isolated fictional window and temporary database were used.");
    }
    return 0;
}
