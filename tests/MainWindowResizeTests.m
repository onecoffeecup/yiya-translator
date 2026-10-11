#import "LearningAppTestSupport.h"

static void Layout(AppDelegate *app) {
    Tick(); [app.mainWindow.contentView layoutSubtreeIfNeeded]; Tick();
    Require(fabs(NSWidth(app.mainWorkspaceRoot.frame)-NSWidth(app.mainWindow.contentView.bounds))<2,
        @"the layout canvas follows the native window width");
}

// Request a width at AppKit's drag priority without manually changing the
// production constraints or calling live-resize callbacks. A width constraint
// on the window boundary would override this request and fail the regression.
static void ResizeThroughLayout(AppDelegate *app, CGFloat width) {
    CGFloat expectedWidth = MAX(width, app.mainWindow.contentMinSize.width);
    NSLayoutConstraint *drag = [app.mainWindow.contentView.widthAnchor constraintEqualToConstant:width];
    drag.priority = NSLayoutPriorityDragThatCanResizeWindow;
    drag.active = YES;
    Layout(app);
    NSLog(@"RESIZE_REQUEST desired=%.0f actual=%.0f", width, NSWidth(app.mainWindow.frame));
    Require(fabs(NSWidth(app.mainWindow.frame)-expectedWidth)<2,
        @"live-resize layout request must change the outer window width");
    drag.active = NO;
    Layout(app);
    NSLog(@"RESIZE_RELEASE desired=%.0f actual=%.0f preferred=%.0f", width,
        NSWidth(app.mainWindow.frame), app.mainWindowContentWidth.constant);
    Require(fabs(NSWidth(app.mainWindow.frame)-expectedWidth)<2,
        @"releasing a resize request must preserve the chosen width");
}

static void CheckPreviewContinuity(AppDelegate *app) {
    [app selectPageAtIndex:0];
    app.mainChatWantsVisible = YES;
    [app updateMainChatForWindowWidth];
    ResizeThroughLayout(app, 962);
    NSSize previous = app.framePreview.bounds.size;
    for (NSNumber *width in @[@960, @958, @960, @962]) {
        ResizeThroughLayout(app, width.doubleValue);
        NSSize current = app.framePreview.bounds.size;
        NSLog(@"PREVIEW_CONTINUITY window=%.0f preview=%@ chatHidden=%d", width.doubleValue,
            NSStringFromSize(current), app.mainStudyChatView.hidden);
        Require(fabs(current.width-previous.width)<=4 && fabs(current.height-previous.height)<=4,
            @"a two-point window drag must not suddenly expand or shrink the realtime preview");
        Require(!app.mainStudyChatView.hidden, @"resizing must not automatically close the AI sidebar");
        previous = current;
    }
    for (NSNumber *width in @[@1102, @1100, @1098, @1100, @1102]) {
        ResizeThroughLayout(app, width.doubleValue);
        NSSize current = app.framePreview.bounds.size;
        Require(fabs(current.width-previous.width)<=4 && fabs(current.height-previous.height)<=4,
            @"the open-sidebar minimum prevents a preview jump during diagonal resizing");
        previous = current;
    }
    for (NSNumber *width in @[@1100, @1098, @1100, @1102]) {
        NSRect frame=app.mainWindow.frame;
        frame.size.width=width.doubleValue; frame.size.height+=6;
        [app.mainWindow setFrame:frame display:NO]; Layout(app);
        NSSize current=app.framePreview.bounds.size;
        Require(!app.mainStudyChatView.hidden && fabs(current.width-previous.width)<=4 && fabs(current.height-previous.height)<=4,
            @"changing both window dimensions preserves the open sidebar and continuous preview sizing");
        previous=current;
    }
    FYStudyChatView *chat = app.mainStudyChatView;
    [app toggleMainStudyChat:nil]; Layout(app);
    Require(chat.hidden && app.mainWindow.contentMinSize.width==720, @"manual collapse releases the narrow-window range");
    ResizeThroughLayout(app, 962); previous = app.framePreview.bounds.size;
    for (NSNumber *width in @[@960, @958, @960, @962]) {
        ResizeThroughLayout(app, width.doubleValue);
        NSSize current = app.framePreview.bounds.size;
        Require(chat.hidden && fabs(current.width-previous.width)<=4 && fabs(current.height-previous.height)<=4,
            @"a manually closed sidebar stays closed and the preview scales continuously");
        previous = current;
    }
    ResizeThroughLayout(app, 1320);
    Require(chat.hidden, @"widening does not automatically reopen a manually closed sidebar");
    ResizeThroughLayout(app, 720);
    [app toggleMainStudyChat:nil]; Layout(app);
    Require(app.mainStudyChatView==chat && !chat.hidden && app.mainChatToggle.enabled && NSWidth(app.mainWindow.frame)>=1100,
        @"manual expansion from a narrow window keeps the same chat and supplies its minimum width");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        FYLearningStore *store=Store([directory stringByAppendingPathComponent:@"resize.sqlite3"]);
        FYGrammarCatalog *catalog=[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL], @"catalog failed");
        AppDelegate *app=App(store, Analyzer(catalog), catalog);
        app.mainWindow.title=@"译芽 · 窗口边缘缩放回归";
        [app.mainWindow orderFront:nil]; Layout(app);
        NSLog(@"RESIZE_BASELINE frame=%@ min=%@ max=%@", NSStringFromRect(app.mainWindow.frame),
            NSStringFromSize(app.mainWindow.minSize), NSStringFromSize(app.mainWindow.maxSize));
        CheckPreviewContinuity(app);
        ResizeThroughLayout(app, 1120);
        ResizeThroughLayout(app, 950);
        Require(!app.mainStudyChatView.hidden, @"shrinking preserves the open AI sidebar");
        [app toggleMainStudyChat:nil]; Layout(app);
        ResizeThroughLayout(app, 720);
        ResizeThroughLayout(app, 1280);
        Require(app.mainStudyChatView.hidden, @"growing preserves the manually closed AI sidebar");
        ResizeThroughLayout(app, 980);
        for (NSInteger page=0; page<(NSInteger)app.pages.count; page++) {
            [app selectPageAtIndex:page]; Layout(app);
            NSLog(@"RESIZE_PAGE index=%ld width=%.0f", (long)page, NSWidth(app.mainWindow.frame));
            Require(fabs(NSWidth(app.mainWindow.frame)-980)<2, @"page switching must preserve user width");
            if (page == 4) {
                Require(app.mainStudyChatView.hidden && app.mainChatToggle.enabled,
                    @"narrow appearance settings preserve the manually closed sidebar and allow expansion");
            }
            ResizeThroughLayout(app, 1180);
            if (page == 4) {
                Require(app.mainStudyChatView.hidden, @"appearance settings do not automatically restore the sidebar");
                ResizeThroughLayout(app, 720);
                Require(app.mainStudyChatView.hidden, @"appearance settings can shrink across the sidebar threshold to the minimum");
            }
            ResizeThroughLayout(app, 980);
        }
        ResizeThroughLayout(app, 1180); [app toggleMainStudyChat:nil]; Layout(app);
        for (NSInteger page=0; page<(NSInteger)app.pages.count; page++) {
            [app selectPageAtIndex:page]; Layout(app);
            Require(!app.mainStudyChatView.hidden && fabs(NSWidth(app.mainWindow.frame)-1180)<2,
                @"all six pages preserve the open sidebar and chosen window width");
        }
        [app toggleMainStudyChat:nil]; Layout(app);
        [app selectPageAtIndex:0]; Layout(app);
        for (NSNumber *width in @[@720, @1320]) {
            NSRect frame=app.mainWindow.frame; frame.size.width=width.doubleValue;
            frame.size.height=width.doubleValue==720 ? 760 : 920;
            [app.mainWindow setFrame:frame display:NO]; Layout(app);
            Require(fabs(NSWidth(app.mainWindow.frame)-width.doubleValue)<2,
                @"programmatic frame changes remain available after a live-resize gesture");
        }
        [app.mainWindow orderOut:nil];
        __block BOOL closed=NO;
        [store closeWithCompletion:^(NSError *error) { Require(!error,@"close failed"); closed=YES; }];
        Pump(^BOOL { return closed; });
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        NSLog(@"PASS: window layout shrink/grow, release and six-page width preservation; isolated data and no capture/API.");
    }
    return 0;
}
