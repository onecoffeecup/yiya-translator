#import "LearningAppTestSupport.h"

static FYLearningColumnsView *FindColumns(NSView *view) {
    if ([view isKindOfClass:FYLearningColumnsView.class]) { return (FYLearningColumnsView *)view; }
    for (NSView *child in view.subviews) { FYLearningColumnsView *columns = FindColumns(child); if (columns) { return columns; } }
    return nil;
}
static void Layout(AppDelegate *app) {
    Tick(); [app.mainWindow.contentView layoutSubtreeIfNeeded]; [app.mainWindow displayIfNeeded]; Tick();
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
        UpdatePreview(app, 1920, 1080); CheckWindow(app, initialWidth, @"1080p capture at default width");
        Require(NSHeight(app.framePreview.bounds) > 300, @"wide workspace must enlarge a 16:9 preview beyond the old 240-point cap");
        // 新中栏按「画面 → 当前对白 → 中文翻译 → 语法」自上而下排列。
        NSView *document = ((NSScrollView *)app.pages[0]).documentView;
        Require(document.isFlipped, @"workbench document view is flipped so top-to-bottom order is readable");
        NSRect previewRect = [app.framePreview convertRect:app.framePreview.bounds toView:document];
        NSRect dialogueRect = [app.learningSourceTextView convertRect:app.learningSourceTextView.bounds toView:document];
        NSRect translationRect = [app.learningTranslationLabel convertRect:app.learningTranslationLabel.bounds toView:document];
        NSRect grammarRect = [app.grammarStatusLabel convertRect:app.grammarStatusLabel.bounds toView:document];
        Require(NSMaxY(previewRect) <= NSMinY(dialogueRect) + 2 &&
                NSMaxY(dialogueRect) <= NSMinY(translationRect) + 2 &&
                NSMaxY(translationRect) <= NSMinY(grammarRect) + 2,
                @"reading column orders picture, dialogue, translation and grammar from top to bottom");
        [app.mainWindow setFrame:NSMakeRect(140, 120, 980, 660) display:YES]; Layout(app);
        CheckWindow(app, 980, @"window resize without a new captured frame");
        UpdatePreview(app, 3840, 2160); CheckWindow(app, 980, @"4K capture at minimum width");
        NSRect previewSmall = [app.framePreview convertRect:app.framePreview.bounds toView:document];
        NSRect dialogueSmall = [app.learningSourceTextView convertRect:app.learningSourceTextView.bounds toView:document];
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
        NSLog(@"PASS: captured preview detail, seven image/size scenarios, resize without capture, empty state and all %lu pages; no capture, real API or user database used.", (unsigned long)app.pages.count);
    }
    return 0;
}
