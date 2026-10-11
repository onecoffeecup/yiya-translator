#import "LearningAppTestSupport.h"

static FYLearningColumnsView *FindColumns(NSView *view) {
    if ([view isKindOfClass:FYLearningColumnsView.class]) { return (FYLearningColumnsView *)view; }
    for (NSView *child in view.subviews) { FYLearningColumnsView *columns = FindColumns(child); if (columns) { return columns; } }
    return nil;
}
static void Layout(AppDelegate *app) {
    Tick(); [app.mainWindow.contentView layoutSubtreeIfNeeded]; [app.mainWindow displayIfNeeded]; Tick();
}
static NSView *ReadingCard(NSView *view) {
    for (NSView *ancestor=view.superview; ancestor; ancestor=ancestor.superview) {
        if ([ancestor isKindOfClass:FYAdventurePanel.class]) { return ancestor; }
    }
    return nil;
}
static NSTextField *FindLabel(NSView *view, NSString *text) {
    if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqualToString:text]) { return (NSTextField *)view; }
    for (NSView *child in view.subviews) { NSTextField *label=FindLabel(child,text); if(label)return label; }
    return nil;
}
static void ReadingSnapshot(NSView *view, NSRect rect, NSString *output) {
    [view scrollRectToVisible:rect]; Tick();
    [view.window.contentView layoutSubtreeIfNeeded]; [view.window displayIfNeeded]; Tick();
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:rect];
    [view cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:output atomically:YES], @"reading screenshot save failed");
}
static void CheckEmptyReadingCards(AppDelegate *app, NSString *output) {
    NSRect originalWindow=app.mainWindow.frame;
    [app refreshLearningSource]; Layout(app);
    NSView *translated=ReadingCard(app.learningTranslationLabel);
    NSTextField *title=FindLabel(translated,@"中文翻译");
    NSRect titleRect=[title convertRect:title.bounds toView:translated];
    CGFloat top=translated.isFlipped ? NSMinY(titleRect) : NSHeight(translated.bounds)-NSMaxY(titleRect);
    NSLog(@"EMPTY_READING: Chinese title top inset=%.1f, card height=%.1f",top,NSHeight(translated.bounds));
    Require(fabs(top-14)<1 && NSMinX(titleRect)<=16, @"empty Chinese title stays at the card's top-left instead of stretching toward the middle");
    NSTextField *waiting=FindLabel(app.pages[0],@"等待识别当前对白，识别后可选词学习。");
    NSView *original=ReadingCard(waiting);
    Require(waiting && !waiting.hidden && original, @"empty original shows a waiting hint");
    Require(app.learningSourceTextView.enclosingScrollView.hidden &&
        FindLabel(original,@"点击选词，或按住拖拽选择词语／短语").hidden && !app.pinSentenceButton.enabled,
        @"empty original hides selection instructions and disables pinning");
    Require(fabs(app.learningTranslationLabel.font.pointSize-14)<.1 &&
        [app.learningTranslationLabel.stringValue isEqualToString:@"开始翻译后，译文会显示在这里。"], @"empty Chinese hint uses secondary 14 pt text");
    for(NSNumber *width in @[@720,@1320]) {
        if (width.integerValue==720 && !app.mainStudyChatView.hidden) { [app toggleMainStudyChat:nil]; Layout(app); }
        [app.mainWindow setFrame:NSMakeRect(140,99,width.doubleValue,975) display:YES]; Layout(app);
        titleRect=[title convertRect:title.bounds toView:translated];
        top=translated.isFlipped ? NSMinY(titleRect) : NSHeight(translated.bounds)-NSMaxY(titleRect);
        Require(fabs(top-14)<1 && fabs(NSHeight(translated.bounds)-104)<1 && fabs(NSHeight(original.bounds)-104)<1,
            @"wide and narrow empty cards remain compact and keep the title at the top");
    }
    if(output) {
        NSView *document=((NSScrollView *)app.pages[0]).documentView;
        NSRect a=[translated convertRect:translated.bounds toView:document],b=[original convertRect:original.bounds toView:document];
        ReadingSnapshot(document,NSUnionRect(a,b),[output stringByAppendingPathComponent:@"reading-empty-detail.png"]);
        [document scrollRectToVisible:NSMakeRect(0,0,1,1)]; Layout(app);
        ReadingSnapshot(app.mainWindow.contentView,app.mainWindow.contentView.bounds,[output stringByAppendingPathComponent:@"reading-empty-main.png"]);
    }
    [app.mainWindow setFrame:originalWindow display:YES]; Layout(app);
}
static void CheckReadingCards(AppDelegate *app, NSString *output) {
    [app.mainWindow setFrame:NSMakeRect(140,99,1320,975) display:YES]; Layout(app);
    NSString *source=@"晴菜\n今日はいい天気ですね。\n一緒に歩きませんか？";
    FYRequestIdentity *identity=[app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
    [app refreshLearningSource]; Layout(app);
    Require(app.liveSourceEmptyLabel.hidden && !app.learningSourceTextView.enclosingScrollView.hidden &&
        !app.liveSourceSelectionHintLabel.hidden && app.pinSentenceButton.enabled &&
        [app.learningTranslationLabel.stringValue isEqualToString:@"等待该句译文"] && fabs(app.learningTranslationLabel.font.pointSize-14)<.1,
        @"first original restores reading and selection controls while waiting for its translation");
    [app.learningCoordinator setTranslation:@"晴菜\n今天天气真好。\n一起去散步，好吗？" forIdentity:identity];
    [app refreshLearningSource]; Layout(app);
    NSView *original=ReadingCard(app.learningSourceTextView), *translated=ReadingCard(app.learningTranslationLabel);
    Require(original && translated, @"both independent reading cards must exist");
    NSTextField *translationTitle=FindLabel(translated,@"中文翻译");
    NSRect heading=[translationTitle convertRect:translationTitle.bounds toView:translated];
    Require(fabs(NSHeight(translated.bounds)-NSMaxY(heading)-14)<1, @"translated Chinese heading also stays at the top");
    NSFont *translationBody=[app.learningTranslationLabel.attributedStringValue attribute:NSFontAttributeName atIndex:app.learningTranslationLabel.stringValue.length-1 effectiveRange:NULL];
    Require(fabs(translationBody.pointSize-23)<.1, @"arriving translation restores the approved Chinese reading size");
    Require([app.learningSourceTextView.string isEqualToString:source], @"speaker styling preserves every original character and selection index");
    NSFont *speakerFont=[app.learningSourceTextView.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    NSFont *bodyFont=[app.learningSourceTextView.textStorage attribute:NSFontAttributeName atIndex:source.length-1 effectiveRange:NULL];
    Require(fabs(speakerFont.pointSize-13)<.1 && fabs(bodyFont.pointSize-19)<.1, @"speaker is secondary while the Japanese body stays at 19 pt");
    NSTextField *title=FindLabel(original,@"当前对白");
    Require(title && app.pinSentenceButton.superview==title.superview && app.learningPinnedLabel.superview==title.superview,
        @"pin action and follow state share the original title row");
    [app.learningSourceTextView.layoutManager ensureLayoutForTextContainer:app.learningSourceTextView.textContainer];
    CGFloat originalGlyphHeight=NSMaxY([app.learningSourceTextView.layoutManager usedRectForTextContainer:app.learningSourceTextView.textContainer])+12;
    Require(app.sourceReadingHeight.constant>=originalGlyphHeight-2, @"short original viewport includes the last glyph and text insets");
    Require(NSHeight(translated.bounds)>=155 && NSHeight(original.bounds)<=NSHeight(translated.bounds)*1.25+2,
        @"short reading cards keep balanced heights without the previous oversized original area");
    NSLog(@"READING_LAYOUT: workspace=%.0f Chinese=%.0f original=%.0f originalViewport=%.0f",NSWidth(original.bounds),NSHeight(translated.bounds),NSHeight(original.bounds),app.sourceReadingHeight.constant);
    NSView *document=((NSScrollView *)app.pages[0]).documentView;
    if(output){
        NSRect a=[translated convertRect:translated.bounds toView:document], b=[original convertRect:original.bounds toView:document];
        ReadingSnapshot(document,NSUnionRect(a,b),[output stringByAppendingPathComponent:@"reading-cards-wide.png"]);
        ReadingSnapshot(app.mainWindow.contentView,app.mainWindow.contentView.bounds,[output stringByAppendingPathComponent:@"reading-main-wide.png"]);
    }
    [app.pinSentenceButton performClick:nil];
    [app.learningCoordinator recordText:@"次の台詞です。" kind:FYSentenceKindDialogue];
    [app refreshLearningSource];
    [app.mainWindow setFrame:NSMakeRect(140,120,720,700) display:YES]; Layout(app);
    NSRect button=[app.pinSentenceButton convertRect:app.pinSentenceButton.bounds toView:original];
    NSRect state=[app.learningPinnedLabel convertRect:app.learningPinnedLabel.bounds toView:original];
    Require(app.learningCoordinator.isPinned && [app.learningPinnedLabel.stringValue containsString:@"有新台词"] &&
        NSMinX(button)>=0 && NSMaxX(state)<=NSWidth(original.bounds)+1, @"narrow pinned state and resume action fit without losing their identities");
    if(output){
        NSRect a=[translated convertRect:translated.bounds toView:document], b=[original convertRect:original.bounds toView:document];
        ReadingSnapshot(document,NSUnionRect(a,b),[output stringByAppendingPathComponent:@"reading-cards-narrow.png"]);
    }
    [app.pinSentenceButton performClick:nil];
    Require(!app.learningCoordinator.isPinned && [app.learningSourceTextView.string isEqualToString:@"次の台詞です。"], @"header action resumes following the latest original");
    NSMutableArray *lines=[NSMutableArray new];
    for(NSUInteger i=0;i<12;i++){[lines addObject:[NSString stringWithFormat:@"长译文第 %lu 行：继续完整阅读，不省略后面的内容。",(unsigned long)i+1]];}
    identity=[app.learningCoordinator recordText:@"これは長い説明です。" kind:FYSentenceKindDialogue];
    NSString *longTranslation=[lines componentsJoinedByString:@"\n"];
    [app.learningCoordinator setTranslation:longTranslation forIdentity:identity];
    [app refreshLearningSource]; Layout(app);
    CGFloat required=[app.learningTranslationLabel.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(app.learningTranslationLabel.bounds),CGFLOAT_MAX)].height;
    Require([app.learningTranslationLabel.stringValue isEqualToString:longTranslation] && app.learningTranslationLabel.maximumNumberOfLines==0 &&
        NSHeight(app.learningTranslationLabel.bounds)>=required-2 && NSHeight(translated.bounds)>300,
        @"long Chinese translation grows beyond eight lines without truncation");
    NSString *wrappingSource=@"这是合成布局夹具。これは折り返しを確認するための長い台詞です。ゲームの画面を見ながら、すべての文字を最後まで読みます。";
    [app.learningCoordinator recordText:wrappingSource kind:FYSentenceKindDialogue];
    [app refreshLearningSource]; Layout(app); CGFloat narrow=app.sourceReadingHeight.constant;
    [app.mainWindow setFrame:NSMakeRect(140,120,1320,900) display:YES]; Layout(app);
    Require(app.sourceReadingHeight.constant<narrow && [app.learningSourceTextView.string isEqualToString:wrappingSource],
        @"resizing without another OCR frame remeasures source height and preserves its text");
    NSAttributedString *unnamed=[app liveReadingText:@"先去图书馆\n然后在那里见面。" japanese:NO];
    Require(fabs([(NSFont *)[unnamed attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize]-23)<.1,
        @"a short Chinese first paragraph without a confirmed speaker remains full-sized body text");
    // A fresh coordinator models a new empty session without changing persisted history.
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:app.learningStore analyzer:app.learningAnalyzer tokenizer:app.japaneseTokenizer catalog:app.grammarCatalog];
    CheckEmptyReadingCards(app,nil);
}
static void DisclosureButtons(NSView *view, NSMutableArray<NSButton *> *buttons) {
    if([view isKindOfClass:NSButton.class] && [(NSButton *)view action]==@selector(toggleDisclosure:)){[buttons addObject:(NSButton *)view];}
    for(NSView *child in view.subviews){DisclosureButtons(child,buttons);}
}
static void UpdatePreview(AppDelegate *app, size_t width, size_t height) {
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color); Require(context != NULL, @"fixture context failed");
    CGContextSetRGBFillColor(context, 0.09, 0.24, 0.28, 1); CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    app.lastPreviewDate = nil; app.framePreview.image = nil;
    [app updatePreviewFromImage:image generation:app.translationGeneration]; CGImageRelease(image);
    Pump(^BOOL { return app.framePreview.image != nil; }); Layout(app);
    NSSize pixels = app.framePreview.image.size;
    double scale = MIN(1.0, 2560.0 / MAX(width, height));
    Require(fabs(pixels.width - llround(width * scale)) < 1 && fabs(pixels.height - llround(height * scale)) < 1,
            @"preview must preserve native detail up to a 2560-pixel longest edge without upsampling");
}
static void CheckWindow(AppDelegate *app, CGFloat width, NSString *scenario) {
    NSLog(@"%@: window=%@ image=%@ preview=%@", scenario, NSStringFromRect(app.mainWindow.frame), NSStringFromSize(app.framePreview.image.size), NSStringFromRect(app.framePreview.frame));
    Require(fabs(app.mainWindow.frame.size.width - width) < 2, [scenario stringByAppendingString:@": captured image must not widen window"]);
    Require(app.framePreview.frame.size.width > 0 && app.framePreview.frame.size.height > 0 && app.framePreview.frame.size.height <= 481, @"preview must remain visible within its height limit");
    NSSize image = app.framePreview.image.size;
    CGFloat expectedHeight = MIN(480, NSWidth(app.framePreview.bounds) * image.height / image.width);
    Require(fabs(NSHeight(app.framePreview.bounds) - expectedHeight) < 2,
            [scenario stringByAppendingString:@": preview must fit the actual capture ratio, using full width until the height cap"]);
    NSRect visiblePreview=[app.framePreview convertRect:app.framePreview.bounds toView:app.pages[0].superview];
    Require(NSMinX(visiblePreview)>=-2 && NSMaxX(visiblePreview)<=NSWidth(app.pages[0].superview.bounds)+2, @"preview must fit within the central workspace viewport");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"preview.sqlite3"]);
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]]; Require([catalog loadWithError:NULL], @"catalog failed");
        AppDelegate *app = App(store, Analyzer(catalog), catalog);
        app.mainWindow.title = @"译芽 · 预览布局回归测试";
        [app.mainWindow orderFront:nil]; Layout(app);
        CGFloat initialWidth = app.mainWindow.frame.size.width;
        // AppKit may reduce a 1320x1000 content window when it exceeds screen height.
        Require(initialWidth>=980 && initialWidth<=1322, @"initial window must stay within supported width bounds");
        CheckEmptyReadingCards(app,argc>1?[NSString stringWithUTF8String:argv[1]]:nil);
        UpdatePreview(app, 1920, 1080); CheckWindow(app, initialWidth, @"1080p capture at default width");
        Require(NSHeight(app.framePreview.bounds) > 300, @"wide workspace must enlarge a 16:9 preview beyond the old 240-point cap");
        // 确认方案先读中文，原文留作选词学习。
        NSView *document = ((NSScrollView *)app.pages[0]).documentView;
        Require(document.isFlipped, @"workbench document view is flipped so top-to-bottom order is readable");
        NSRect previewRect = [app.framePreview convertRect:app.framePreview.bounds toView:document];
        NSRect dialogueRect = [app.liveSourceEmptyLabel convertRect:app.liveSourceEmptyLabel.bounds toView:document];
        NSRect translationRect = [app.learningTranslationLabel convertRect:app.learningTranslationLabel.bounds toView:document];
        NSRect grammarRect = [app.grammarStatusLabel convertRect:app.grammarStatusLabel.bounds toView:document];
        Require(NSMaxY(previewRect) <= NSMinY(translationRect) + 2 &&
                NSMaxY(translationRect) <= NSMinY(dialogueRect) + 2 &&
                NSMaxY(dialogueRect) <= NSMinY(grammarRect) + 2,
                @"reading column orders picture, Chinese translation, dialogue and grammar from top to bottom");
        Require(fabs(app.learningTranslationLabel.font.pointSize-14)<.1 &&
                fabs(app.learningSourceTextView.font.pointSize-19)<.1,
                @"empty Chinese hint is secondary and the native Japanese reader retains 19 pt");
        if (!app.mainStudyChatView.hidden) { [app toggleMainStudyChat:nil]; Layout(app); }
        [app.mainWindow setFrame:NSMakeRect(140, 120, 980, 660) display:YES]; Layout(app);
        CheckWindow(app, 980, @"window resize without a new captured frame");
        UpdatePreview(app, 3840, 2160); CheckWindow(app, 980, @"4K capture at minimum width");
        NSRect previewSmall = [app.framePreview convertRect:app.framePreview.bounds toView:document];
        NSRect dialogueSmall = [app.liveSourceEmptyLabel convertRect:app.liveSourceEmptyLabel.bounds toView:document];
        Require(NSMaxY(previewSmall) <= NSMinY(dialogueSmall) + 2, @"minimum width keeps the picture above the dialogue card");
        UpdatePreview(app, 1080, 1920); CheckWindow(app, 980, @"portrait capture at minimum width");
        UpdatePreview(app, 320, 180); CheckWindow(app, 980, @"small capture at minimum width");
        UpdatePreview(app, 1440, 1080); CheckWindow(app, 980, @"4:3 capture at minimum width");
        UpdatePreview(app, 3440, 1440); CheckWindow(app, 980, @"ultrawide capture at minimum width");
        [app showPreviewUnavailable:@"等待画面"]; Layout(app);
        Require(app.framePreview.image == nil && !app.previewPlaceholder.hidden, @"unavailable capture must show the placeholder");
        Require(fabs(NSHeight(app.framePreview.bounds) - NSWidth(app.framePreview.bounds) * 9.0 / 16.0) < 2,
                @"empty preview returns to its default 16:9 ratio");
        for (NSUInteger i = 0; i < app.pages.count; i++) {
            [app selectPageAtIndex:i]; Layout(app);
            Require(fabs(app.mainWindow.frame.size.width - 980) < 2, @"switching pages after capture must not widen the window");
            NSMutableArray<NSButton *> *disclosures=[NSMutableArray new];DisclosureButtons(app.pages[i],disclosures);
            for(NSButton *button in disclosures){
                [button performClick:nil];Layout(app);
                Require(fabs(NSWidth(app.mainWindow.frame)-980)<2,@"expanded settings must not widen the minimum window");
                [button performClick:nil];Layout(app);
            }
            if(i==5){
                NSRect keyFrame=[app.apiKeyField convertRect:app.apiKeyField.bounds toView:app.pages[i].superview];
                Require(NSMinX(keyFrame)>=0 && NSMaxX(keyFrame)<=NSWidth(app.pages[i].superview.bounds),@"API Key input fits in narrow workspace");
            }
        }
        [app selectPageAtIndex:0]; [app.mainWindow setContentSize:NSMakeSize(1320, 1000)]; Layout(app);
        CGFloat restoredWidth=NSWidth(app.mainWindow.frame);
        Require(restoredWidth>=980 && restoredWidth<=1322, @"restored width must respect the requested size and native screen fitting");
        UpdatePreview(app, 3840, 2160); CheckWindow(app, restoredWidth, @"4K capture after restoring default size");
        CheckReadingCards(app,argc>1?[NSString stringWithUTF8String:argv[1]]:nil);
        if (argc > 1) {
            NSView *view = app.mainWindow.contentView;
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSString *output = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"preview-layout-fixed.png"];
            Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:output atomically:YES], @"test screenshot save failed");
        }
        [app.mainWindow orderOut:nil]; __block BOOL closed = NO;
        [store closeWithCompletion:^(NSError *error) { Require(!error, @"close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        NSLog(@"PASS: empty title top-left/104 pt cards/14 pt hints, empty-to-waiting-to-translated-to-empty transitions, picture/translation/original order, 23/19 pt, balanced short cards, speaker indices, narrow pin/follow, twelve-line translation, resize remeasurement, seven capture ratios and all %lu pages; no real capture/API/user database.", (unsigned long)app.pages.count);
    }
    return 0;
}
