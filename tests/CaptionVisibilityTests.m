#import "LearningAppTestSupport.h"
@interface FocusTestApp : AppDelegate
@property(nonatomic) BOOL targetActive;
@end
@implementation FocusTestApp
- (BOOL)translationTargetIsForeground { return self.targetActive; }
@end
// 目标就是本进程时，验证浮窗层级会不会跟上目标应用自己的高层级窗口（OBS 场景）。
@interface LevelTestApp : AppDelegate
@end
@implementation LevelTestApp
- (BOOL)translationTargetIsForeground { return YES; }
- (pid_t)selectedWindowOwnerPID { return getpid(); }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    FocusTestApp *app = [FocusTestApp new];
    [app createCaptionWindow];
    app.captionPanelShownByUser = YES;
    app.inlineTranslationPanels = [NSMutableArray arrayWithObject:[[NSPanel alloc] initWithContentRect:NSMakeRect(30,30,80,30) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]];
    [app refreshOverlayVisibility:nil];
    Require(!app.captionPanel.isVisible && app.captionPanel.level == NSNormalWindowLevel, @"startup outside target must not float");
    app.targetActive = YES; [app refreshOverlayVisibility:nil];
    Require(app.captionPanel.isVisible && app.inlineTranslationPanels.firstObject.isVisible, @"target foreground restores overlays");
    [app.captionHideButton performClick:nil];
    Require(!app.captionPanel.isVisible, @"hide control must hide caption");
    NSRect savedDock=app.captionDockPanel.frame;
    [app setCaptionPanelVisibleForUIMode:NO];
    Require(!app.captionPanel.isVisible, @"OCR mode updates cannot undo explicit hide");
    app.targetActive=NO; [app refreshOverlayVisibility:nil]; app.targetActive=YES; [app refreshOverlayVisibility:nil];
    Require(!app.captionPanel.isVisible, @"switching back cannot undo explicit hide");
    Require(app.captionDockPanel.isVisible && NSEqualRects(savedDock,app.captionDockPanel.frame),@"switching away and back preserves collapsed dock position");
    [app showCaptionPanel:nil]; Require(app.captionPanel.isVisible, @"explicit show restores caption");
    [app setCaptionPanelVisibleForUIMode:YES]; Require(!app.captionPanel.isVisible, @"UI mode suppresses caption");
    [app setCaptionPanelVisibleForUIMode:NO]; Require(app.captionPanel.isVisible, @"dialogue mode restores caption");
    app.targetActive=NO; [app refreshOverlayVisibility:nil];
    Require(!app.captionPanel.isVisible && !app.inlineTranslationPanels.firstObject.isVisible && app.captionPanel.level==NSNormalWindowLevel, @"other app must hide and lower overlays");
    [app setCaptionPanelVisibleForUIMode:NO];
    Require(!app.captionPanel.isVisible, @"late translation reply cannot show above other app");
    [app showCaptionPanel:nil]; Require(!app.captionPanel.isVisible, @"show request outside target waits for foreground");
    app.targetActive=YES;app.selectingCaptureRegion=YES;[app refreshOverlayVisibility:nil];
    Require(!app.captionPanel.isVisible && !app.inlineTranslationPanels.firstObject.isVisible, @"region selection suppresses overlays");
    app.selectingCaptureRegion=NO;[app refreshOverlayVisibility:nil];
    Require(app.captionPanel.isVisible, @"region selection completion respects target policy");
    [app.captionPanel.contentView layoutSubtreeIfNeeded];
    Require(NSMaxY(app.captionTextLabel.frame)<=NSMinY(app.captionHideButton.frame), @"hide control must not overlap translated text");
    [app.captionPanel orderOut:nil];[app.inlineTranslationPanels.firstObject orderOut:nil];
    AppDelegate *realPolicy = [AppDelegate new];
    realPolicy.windowPopup = [[NSPopUpButton alloc] init];
    NSWindow *target = [[NSWindow alloc] initWithContentRect:NSMakeRect(60,60,320,180) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    target.title=@"Focus policy test";
    [target makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; Tick();
    [realPolicy.windowPopup addItemWithTitle:@"Test target"];
    realPolicy.windowPopup.selectedItem.representedObject=@(target.windowNumber);
    BOOL realForeground=[realPolicy translationTargetIsForeground];
    if (!realForeground) {
        NSArray *visible=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
        NSMutableArray *owned=[NSMutableArray array];
        for (NSDictionary *entry in visible) if ([entry[(id)kCGWindowOwnerPID] intValue]==getpid()) [owned addObject:entry];
        NSLog(@"FOREGROUND DIAGNOSTIC pid=%d frontPID=%d target=%ld selected=%u owner=%d appActive=%d visible=%d keyTarget=%d resolved=%d ambiguous=%d resolvedID=%u owned=%@",getpid(),NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier,(long)target.windowNumber,[realPolicy selectedWindowID],[realPolicy selectedWindowOwnerPID],NSApp.isActive,target.isVisible,NSApp.keyWindow==target,realPolicy.displayTargetResolved,realPolicy.displayTargetAmbiguous,realPolicy.resolvedDisplayTargetID,owned);
    }
    Require(realForeground, @"real foreground PID and on-screen window must match");
    [target miniaturize:nil]; Tick();
    Require(![realPolicy translationTargetIsForeground], @"minimized target must not qualify even when its app remains frontmost");
    [target orderOut:nil];
    // —— 浮窗显示策略：OBS 全屏预览/投影会接管画面（主窗口离开屏幕窗口列表）——
    AppDelegate *policy = [AppDelegate new];
    Require([policy targetQualifiesForOverlayWithFrontmostPID:100 targetPID:100 targetOnScreen:NO ownerHasOnScreenWindow:YES interactingWithOverlay:NO],
            @"target app in front with another on-screen window keeps the caption (fullscreen projector case)");
    Require([policy targetQualifiesForOverlayWithFrontmostPID:100 targetPID:100 targetOnScreen:YES ownerHasOnScreenWindow:YES interactingWithOverlay:NO],
            @"target window on screen in front still shows the caption");
    Require(![policy targetQualifiesForOverlayWithFrontmostPID:200 targetPID:100 targetOnScreen:YES ownerHasOnScreenWindow:YES interactingWithOverlay:NO],
            @"another app in front still hides the caption");
    Require(![policy targetQualifiesForOverlayWithFrontmostPID:100 targetPID:100 targetOnScreen:NO ownerHasOnScreenWindow:NO interactingWithOverlay:NO],
            @"minimized target whose app has no on-screen window stays hidden");
    Require([policy targetQualifiesForOverlayWithFrontmostPID:0 targetPID:100 targetOnScreen:NO ownerHasOnScreenWindow:NO interactingWithOverlay:YES],
            @"interacting with our own auxiliary panel keeps the caption visible");
    NSString *pidKey = (__bridge NSString *)kCGWindowOwnerPID;
    NSString *layerKey = (__bridge NSString *)kCGWindowLayer;
    NSArray *obsWindows = @[@{pidKey: @100, layerKey: @0}, @{pidKey: @200, layerKey: @101}, @{pidKey: @100, layerKey: @101}];
    Require([policy overlayLevelForTargetPID:100 inWindowList:obsWindows] == NSPopUpMenuWindowLevel + 1,
            @"overlay level rises above a target app that uses pop-up level preview windows");
    Require([policy overlayLevelForTargetPID:200 inWindowList:obsWindows] == NSPopUpMenuWindowLevel + 1,
            @"the level follows whichever app owns the selected window");
    Require([policy overlayLevelForTargetPID:100 inWindowList:@[@{pidKey: @100, layerKey: @0}]] == NSFloatingWindowLevel,
            @"normal target windows keep the floating level");
    Require([policy overlayLevelForTargetPID:0 inWindowList:obsWindows] == NSFloatingWindowLevel,
            @"unknown target keeps the floating level");
    // 真实窗口验证：目标应用有一个 101 层级的窗口时，字幕窗必须抬到 102。
    NSWindow *popupLevel = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 320, 200)
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    popupLevel.level = NSPopUpMenuWindowLevel;
    popupLevel.opaque = NO;
    popupLevel.backgroundColor = NSColor.clearColor;
    [popupLevel makeKeyAndOrderFront:nil];
    Tick();
    LevelTestApp *levelApp = [LevelTestApp new];
    // The target must actually be selected: an empty picker now intentionally
    // skips window-list polling rather than inferring a target from a test PID.
    levelApp.windowPopup = [[NSPopUpButton alloc] init];
    [levelApp.windowPopup addItemWithTitle:@"Pop-up level target"];
    levelApp.windowPopup.selectedItem.representedObject = @(popupLevel.windowNumber);
    [levelApp createCaptionWindow];
    levelApp.captionPanelShownByUser = YES;
    [levelApp refreshOverlayVisibility:nil];
    Require(levelApp.captionPanel.isVisible && levelApp.captionPanel.level == NSPopUpMenuWindowLevel + 1,
            @"caption panel really rises above a pop-up-level target window");
    [levelApp.captionPanel orderOut:nil];
    [popupLevel orderOut:nil];
    NSLog(@"PASS: foreground, hide/show, explicit hide persistence, mode transitions, late reply, region selection and button layout");
} return 0; }
