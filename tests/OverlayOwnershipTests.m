#import "LearningAppTestSupport.h"
#import <objc/runtime.h>

@interface OverlayOwnershipApp : AppDelegate
@property(nonatomic) NSUInteger captionHideActions;
@property(nonatomic) NSUInteger rowActions;
@end
@implementation OverlayOwnershipApp
- (void)refreshOverlayVisibility:(id)sender {}
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason {
    if (rect) { *rect = NSMakeRect(60, 60, 900, 600); }
    return YES;
}
- (void)hideCaptionPanel:(id)sender { self.captionHideActions++; [super hideCaptionPanel:sender]; }
- (void)openInlineOverflowRow:(NSButton *)sender { self.rowActions++; [super openInlineOverflowRow:sender]; }
@end

static NSUInteger checks;
static void Check(BOOL value, NSString *message) { checks++; Require(value, message); }
static NSButton *FindButton(NSView *view, SEL action) {
    if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).action == action) { return (NSButton *)view; }
    for (NSView *child in view.subviews) { NSButton *button = FindButton(child, action); if (button) { return button; } }
    return nil;
}

int main(void) { @autoreleasepool {
    __weak AppDelegate *released;
    FYSubtitlePresenter *subtitle;
    FYInlineOverlayController *inlineOwner;
    @autoreleasepool {
        AppDelegate *cold = [AppDelegate new]; released = cold;
        subtitle = cold.subtitlePresenter; inlineOwner = cold.inlineOverlayController;
        Check(!cold.captionPanel && !cold.captionDockPanel && !cold.inlineOverflowPanel && !cold.inlineExpandedReadingPanel,
              @"owner access must not create any floating window");
        Check(cold.inlineTranslationPanels && cold.inlineLongCardPanels && cold.inlineManualOffsets &&
              cold.inlineStableBlockIDs && !cold.inlineModifierTimer, @"cold state keeps initialized collections without starting monitoring");
        Check([cold conformsToProtocol:@protocol(FYSubtitlePresenterHost)] &&
              [cold conformsToProtocol:@protocol(FYInlineOverlayControllerHost)], @"host exposes both explicit overlay contracts");
    }
    Check(!released && !subtitle.host && !inlineOwner.host, @"overlay owners do not retain the host");
    for (NSString *ivar in @[@"_captionPanel", @"_captionDockPanel", @"_captionPanelShownByUser", @"_captionTextLabel",
        @"_inlinePanelsByBlockID", @"_inlineManualOffsets", @"_inlineOverflowEntries", @"_inlineExpandedReadingPanel",
        @"_inlineExpandedReadingBlockID", @"_lastInlineLayoutResult", @"_inlineLayoutEngine"]) {
        Check(class_getInstanceVariable(AppDelegate.class, ivar.UTF8String) == NULL, @"facade does not duplicate owned overlay state");
    }
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    OverlayOwnershipApp *app = [OverlayOwnershipApp new];
    [app createCaptionWindow]; app.captionPanelShownByUser = YES;
    Check(app.captionPanel == app.subtitlePresenter.captionPanel && app.captionHideButton.target == app,
          @"caption window has one owner and preserves its native host action");
    [app.captionHideButton performClick:nil];
    Check(app.captionHideActions == 1 && !app.captionPanelShownByUser && !app.subtitlePresenter.captionPanelShownByUser,
          @"native hide action passes through the subclass hook into the owner");
    app.inlineOverlayController.inlineManualOffsets[@"synthetic"] = [NSValue valueWithSize:NSMakeSize(12, 8)];
    Check(app.inlineManualOffsets == app.inlineOverlayController.inlineManualOffsets && app.inlineManualOffsets.count == 1,
          @"drag offsets have one state source");
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new]; snapshot.blockID = @"study-context";
    app.inlineBlockSnapshot = snapshot;
    Check(app.inlineOverlayController.host.inlineBlockSnapshot == app.studyPresentationController.inlineBlockSnapshot,
          @"overlay and study use the same learning return context");
    OCRTextItem *item = [OCRTextItem new]; item.text = @"猫は窓のそばにいる。";
    item.blockKind = InlineBlockKindLong; item.boundingBox = CGRectMake(0.1, 0.1, 0.6, 0.2); item.lineBoxes = @[];
    app.inlineOverflowEntries = @[@{@"item":item, @"source":item.text, @"translation":@"猫在窗户旁边。", @"blockID":@"first", @"title":@"第一条"},
        @{@"item":item, @"source":item.text, @"translation":@"另一条完整译文。", @"blockID":@"second", @"title":@"第二条"}];
    [app showInlineOverflowChooser];
    NSButton *row = FindButton(app.inlineOverflowChoicePanel.contentView, @selector(openInlineOverflowRow:));
    Check(row && row.target == app && app.inlineOverflowChoiceKeyMonitor,
          @"chooser rows preserve host actions and the owned close monitor");
    [row performClick:nil];
    Check(app.rowActions == 1 && !app.inlineOverflowChoicePanel && !app.inlineOverflowChoiceKeyMonitor &&
          app.inlineExpandedReadingPanel && [app.inlineExpandedReadingBlockID isEqual:@"first"],
          @"native chooser action closes the frozen list and expands the selected stable identity");
    Check(app.inlineExpandedReadingPanel == app.inlineOverlayController.inlineExpandedReadingPanel &&
          app.inlineExpandedReadingKeyMonitor, @"expanded reading window and monitor belong to the same owner");
    [app clearInlineTranslationPanels];
    Check(!app.inlineExpandedReadingPanel && !app.inlineExpandedReadingKeyMonitor && !app.inlineOverflowChoiceKeyMonitor &&
          !app.inlineModifierTimer && !app.lastInlineLayoutResult && app.inlineManualOffsets.count == 0,
          @"scene cleanup releases monitors, panels, layout cache and manual offsets");
    [app.captionPanel orderOut:nil]; [app.captionDockPanel orderOut:nil];
    printf("PASS OverlayOwnershipTests: %lu checks; cold/weak ownership, unique state, native actions, stable reading identity, cleanup\n", (unsigned long)checks);
} return 0; }
