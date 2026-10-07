#import "LearningAppTestSupport.h"

@interface DiagnosticTestMailService : NSSharingService
@property(nonatomic) BOOL available;
@property(nonatomic) NSUInteger composeCount;
@property(nonatomic, copy) NSArray *composedItems;
@end
@implementation DiagnosticTestMailService
- (BOOL)canPerformWithItems:(NSArray *)items { return self.available; }
- (void)performWithItems:(NSArray *)items { self.composeCount++; self.composedItems = items; }
@end

@interface DiagnosticTestApp : AppDelegate
@property(nonatomic, strong) NSArray *fixtureInfos;
@property(nonatomic) BOOL fixturePermission;
@property(nonatomic) BOOL fixtureQuickTimeRunning;
@property(nonatomic) BOOL requestedPermission;
@property(nonatomic) NSUInteger captureAttempts;
@property(nonatomic, strong) DiagnosticTestMailService *fixtureMailService;
@property(nonatomic) NSUInteger saveRequests;
@property(nonatomic) BOOL saveForEmail;
@end
@implementation DiagnosticTestApp
- (NSArray *)diagnosticWindowInfos { return self.fixtureInfos ?: @[]; }
- (BOOL)diagnosticQuickTimeRunning { return self.fixtureQuickTimeRunning; }
- (BOOL)hasScreenAccess { return self.fixturePermission; }
- (uint32_t)displayTargetWindowID { return [self selectedWindowID]; }
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force { }
- (void)handleMissingScreenAccessForStart { self.requestedPermission = YES; }
- (NSArray *)availableWindowItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *info in self.fixtureInfos) { WindowItem *item = FYWindowItemFromInfo(info); if (item) { [items addObject:item]; } }
    return items;
}
- (pid_t)selectedWindowOwnerPID {
    for (NSDictionary *info in self.fixtureInfos) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] == [self selectedWindowID]) { return [info[(id)kCGWindowOwnerPID] intValue]; }
    }
    return 0;
}
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID { self.captureAttempts++; return NULL; }
- (NSSharingService *)newDiagnosticMailService { return self.fixtureMailService; }
- (void)saveRuntimeDiagnosticsForEmail:(BOOL)email { self.saveRequests++; self.saveForEmail = email; }
@end

static NSDictionary *WindowInfo(uint32_t window, pid_t pid, NSString *owner) {
    return @{(id)kCGWindowNumber: @(window), (id)kCGWindowOwnerPID: @(pid), (id)kCGWindowOwnerName: owner,
             (id)kCGWindowName: @"PRIVATE_DOCUMENT_TITLE", (id)kCGWindowLayer: @0,
             (id)kCGWindowBounds: @{ @"X": @20, @"Y": @30, @"Width": @800, @"Height": @500 }};
}
static NSButton *DiagnosticButton(NSView *view, SEL action) {
    if ([view isKindOfClass:NSButton.class] && [(NSButton *)view action] == action) { return (NSButton *)view; }
    for (NSView *child in view.subviews) { NSButton *found = DiagnosticButton(child, action); if (found) { return found; } }
    return nil;
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    DiagnosticTestApp *app = [DiagnosticTestApp new];
    app.fixtureInfos = @[WindowInfo(1, getpid(), @"译芽")];
    [app createMainWindow]; // Never order a window front, change focus, or use the clipboard.
    app.fixturePermission = NO;
    [app refreshWindows:nil];
    Require(app.windowPopup.selectedItem.representedObject == nil || [app selectedWindowID] == 0, @"self is not offered as a capture target");
    Require([app.diagnosticStatusLabel.stringValue containsString:@"屏幕录制权限"] && [app.diagnosticStatusLabel.stringValue containsString:@"自己的窗口"], @"self-only list gives concrete permission feedback");
    [app start];
    Require(app.requestedPermission && !app.running && app.captureAttempts == 0, @"empty unauthorized list routes to permission recovery before generic selection warning");
    [app.windowPopup removeAllItems]; [app.windowPopup addItemWithTitle:@"译芽"];
    app.windowPopup.lastItem.representedObject = @1;
    Require(![app canCaptureSelectedWindowOnce] && app.captureAttempts == 0, @"own window cannot fake usable screen permission");
    Require(!FYWindowOwnerIsYiya(nil), @"missing window metadata is not mistaken for the app itself");
    app.fixturePermission = YES;
    [app start];
    Require(!app.running && app.captureAttempts == 0 && [app.statusLabel.stringValue containsString:@"不能把译芽自身"], @"even with permission, own-window capture is refused");
    app.fixtureInfos = @[WindowInfo(1, getpid(), @"译芽"), WindowInfo(42, 98765, @"QuickTime Player")];
    app.fixturePermission = YES; app.fixtureQuickTimeRunning = YES;
    [app.windowPopup removeAllItems];
    [app refreshWindows:nil];
    [app selectWindowWithID:42 notifyChange:NO];
    NSButton *run = DiagnosticButton(app.pages[3], @selector(runRuntimeDiagnostics:));
    NSButton *export = DiagnosticButton(app.pages[3], @selector(exportRuntimeDiagnostics:));
    NSButton *mail = DiagnosticButton(app.pages[3], @selector(emailRuntimeDiagnostics:));
    Require(run && export && mail && [export.title containsString:@"导出"], @"all three user-facing actions are present in run settings");
    [NSApp sendAction:mail.action to:app from:mail];
    Require(app.saveRequests == 1 && app.saveForEmail, @"mail action saves a report before composing");
    [NSApp sendAction:export.action to:app from:export];
    Require(app.saveRequests == 2 && !app.saveForEmail, @"standalone export remains available");
    [NSApp sendAction:run.action to:app from:run];
    Require([app.diagnosticStatusLabel.stringValue containsString:@"未发现明显"], @"permission and target recovery clears prior warning");
    NSDictionary *report = [FYRuntimeDiagnostics.shared reportForSnapshot:[app runtimeDiagnosticSnapshot]];
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL] encoding:NSUTF8StringEncoding];
    Require(![json containsString:@"PRIVATE_DOCUMENT_TITLE"] && [report[@"snapshot"][@"selected_role"] isEqual:@"quicktime"], @"adapter identifies QuickTime without exporting window titles");
    Require(app.captureAttempts == 0 && FYTestCaptureCount() == 0, @"running diagnostics never captures screenshots or starts OCR");

    // Render only the diagnostic controls with synthetic state, offscreen.
    NSString *output = argc > 1 ? @(argv[1]) : NSTemporaryDirectory();
    NSURL *attachment = [NSURL fileURLWithPath:[output stringByAppendingPathComponent:@"diagnostic-email-fixture.json"]];
    Require([FYRuntimeDiagnostics writeReport:report toURL:attachment error:NULL], @"email attachment saved using real report writer");
    [app composeDiagnosticEmailForURL:attachment];
    Require([app.diagnosticStatusLabel.stringValue containsString:@"网页邮箱"] && [app.diagnosticStatusLabel.stringValue containsString:@"yiyatranslator@163.com"], @"missing mail service provides manual sending instructions");
    DiagnosticTestMailService *service = [[DiagnosticTestMailService alloc] initWithTitle:@"Test mail" image:[NSImage new] alternateImage:nil handler:^{}];
    app.fixtureMailService = service;
    [app composeDiagnosticEmailForURL:attachment];
    Require(service.composeCount == 0 && !app.diagnosticMailService, @"unconfigured service does not attempt composition");
    service.available = YES;
    [app composeDiagnosticEmailForURL:attachment];
    Require([service.recipients isEqual:@[@"yiyatranslator@163.com"]] && [service.subject containsString:@"译芽"], @"mail recipient and subject configured");
    Require(service.composeCount == 1 && service.composedItems.count == 2 && [service.composedItems[1] isEqual:attachment], @"mail receives a file URL attachment and body, never a mailto attachment parameter");
    Require([service.composedItems[0] containsString:@"复现步骤"] && ![app.statusLabel.stringValue containsString:@"已发送"], @"draft requests context without claiming delivery");
    [app emailRuntimeDiagnostics:nil];
    Require(app.saveRequests == 2, @"duplicate mail action is blocked while composing");
    [app sharingService:service didFailToShareItems:service.composedItems error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    Require(!app.diagnosticMailService && [NSFileManager.defaultManager fileExistsAtPath:attachment.path], @"cancel/failure releases service and preserves attachment for retry");
    [app composeDiagnosticEmailForURL:attachment];
    Require(service.composeCount == 2, @"retry works after cancellation");
    [app sharingService:service didShareItems:service.composedItems];
    Require(!app.diagnosticMailService && [app.statusLabel.stringValue containsString:@"确认发送状态"], @"service completion is not treated as recipient delivery");
    app.fixturePermission = NO; app.fixtureInfos = @[WindowInfo(1, getpid(), @"译芽")];
    for (NSNumber *width in @[@340, @620]) {
        NSView *controls = [app diagnosticControls];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-3000, -3000, width.doubleValue, 700)
                                                     styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.contentView = [[FYAdventurePanel alloc] initWithFrame:NSMakeRect(0, 0, width.doubleValue, 700)];
        controls.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:controls];
        [NSLayoutConstraint activateConstraints:@[[controls.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:16],
                                                 [controls.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-16],
                                                 [controls.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:16]]];
        [app updateRuntimeDiagnostics];
        [window.contentView layoutSubtreeIfNeeded]; Tick();
        [window.contentView layoutSubtreeIfNeeded];
        Require(NSWidth(controls.frame) <= width.doubleValue && NSHeight(controls.frame) > 100 && NSHeight(controls.frame) < 680, @"diagnostics wraps and fits compact and wide layouts");
        Require(NSWidth([app.diagnosticStatusLabel alignmentRectForFrame:app.diagnosticStatusLabel.frame]) <= NSWidth(controls.frame) + 1, [NSString stringWithFormat:@"finding text fits the available width (label=%@ controls=%@)", NSStringFromRect(app.diagnosticStatusLabel.frame), NSStringFromRect(controls.frame)]);
        NSBitmapImageRep *rep = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:rep];
        Require([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[output stringByAppendingPathComponent:[NSString stringWithFormat:@"diagnostics-%@.png", width]] atomically:YES], @"diagnostic preview written");
        [window orderOut:nil];
    }
    [app.mainWindow orderOut:nil];
    puts("PASS DiagnosticsInteractionTests: self-only recovery, native actions, private metadata, email attachment/recipient, unavailable/cancel/retry, zero real mail/capture, compact/wide layout");
} return 0; }
