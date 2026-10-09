#import "LearningAppTestSupport.h"

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    AppDelegate *app=[AppDelegate new];
    app.captionFontSizeSlider=[app sliderWithMin:18 max:56 value:30 action:NULL];
    app.captionWidthSlider=[app sliderWithMin:360 max:1200 value:700 action:NULL];
    app.captionHeightSlider=[app sliderWithMin:120 max:340 value:180 action:NULL];
    app.captionOpacitySlider=[app sliderWithMin:0 max:.95 value:.58 action:NULL];
    app.captionThemeControl=[NSSegmentedControl segmentedControlWithLabels:@[@"black",@"white",@"pink",@"flower"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:NULL];
    app.captionThemeControl.selectedSegment=0;
    [app createCaptionWindow];
    [app updateCaptionWindowWithText:@"合成旧译文" status:@"测试"];
    NSColor *background=((FYAdventurePanel *)app.captionContainer).fillColor;
    [app.captionPanel makeKeyWindow];
    // Seed AppKit's existing field editor, then perform only automatic updates.
    // No mouse click or selection operation occurs on the subsequent captions.
    [app.captionTextLabel selectText:nil];
    Require(app.captionTextLabel.currentEditor.selectedRange.length==5,@"native caption selection is available");
    [app updateCaptionWindowWithText:@"合成旧译文" status:@"相同帧"];
    Require(app.captionTextLabel.currentEditor.selectedRange.length==5,@"unchanged OCR preserves the reader's selection");
    [app updateCaptionWindowWithText:@"翻译失败：合成超时" status:@"测试失败"];
    Require(app.captionTextLabel.currentEditor==nil,@"error caption must not automatically inherit full-text highlight");
    Require([background isEqual:((FYAdventurePanel *)app.captionContainer).fillColor],@"request errors cannot change the caption theme");
    [app.captionTextLabel selectText:nil];
    Require(app.captionTextLabel.currentEditor!=nil,@"native selection remains usable after an error");
    [app setCaptionPanelVisibleForUIMode:YES];
    Require(app.captionTextLabel.currentEditor==nil,@"hiding for UI mode must finish the caption field editor");
    [app setCaptionPanelVisibleForUIMode:NO];
    [app updateCaptionWindowWithText:@"合成新的译文\n第二行" status:@"恢复"];
    Require(app.captionTextLabel.currentEditor==nil && !app.captionTextLabel.drawsBackground,@"new dialogue has no inactive selection or opaque label background");
    Require([background isEqual:((FYAdventurePanel *)app.captionContainer).fillColor],@"dialogue/UI/dialogue preserves configured background opacity and color");
    [app.captionTextLabel selectText:nil];
    Require(app.captionTextLabel.currentEditor.selectedRange.length==10,@"new translation can still be selected normally");
    [app.captionPanel endEditingFor:app.captionTextLabel];
    [app.captionPanel orderOut:nil];
    puts("PASS CaptionSelectionTests: error recovery, mode changes, unchanged text and native selection");
} return 0; }
