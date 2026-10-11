// Headless: production preference migration/selection, no NSApplication or windows.
#import "LearningAppTestSupport.h"
@interface SubtitleTestControl : NSObject
@property(nonatomic) double doubleValue;
@property(nonatomic) NSInteger selectedSegment;
@property(nonatomic) NSInteger tag;
@property(nonatomic, strong) NSColor *color;
@end
@implementation SubtitleTestControl
@end
@interface SubtitleSettingsApp : AppDelegate
@property(nonatomic) NSUInteger saves;
@property(nonatomic) NSUInteger captionUpdates;
@property(nonatomic) NSUInteger ocrUpdates;
@end
@implementation SubtitleSettingsApp
- (void)scheduleSettingsSave { self.saves++; }
- (void)updateCaptionAppearance { self.captionUpdates++; }
- (void)updateOCRPreviewIfVisible { self.ocrUpdates++; }
@end
static SubtitleSettingsApp *SettingsApp(void) {
    SubtitleSettingsApp *app=[SubtitleSettingsApp new];
    for(NSString *key in @[@"captionOpacitySlider",@"captionFontSizeSlider",@"captionHeightSlider",@"captionWidthSlider",@"captionThemeControl",@"captionTextColorWell",@"batchFontSizeSlider",@"batchWidthSlider",@"batchHeightSlider",@"batchThemeControl",@"batchTextColorWell",@"appearanceModeControl"]){
        [app setValue:[SubtitleTestControl new] forKey:key];
    }
    return app;
}
static BOOL SameColor(NSColor *a,NSColor *b) { return [FYAppearanceColorHex(a) isEqualToString:FYAppearanceColorHex(b)]; }
int main(void) { @autoreleasepool {
    SubtitleSettingsApp *app=SettingsApp();[app loadSubtitleAppearanceSettings:@{}];
    Require([app inlineThemeIndex]==3 && [app captionThemeIndex]==3 && app.appearanceModeControl.selectedSegment==1,@"default independent cream themes and inline settings");
    [app loadSubtitleAppearanceSettings:@{@"captionTheme":@0,@"captionOpacity":@.2,@"batchTextColor":@"#123456",@"batchFontSize":@21,@"batchMaxWidth":@420}];
    Require([app inlineThemeIndex]==3 && SameColor([app inlinePanelFillColor],FYAdventureColor(@"cream")),@"legacy black caption must not migrate into the inline theme");
    Require(app.batchTextColorCustomized && [FYAppearanceColorHex([app inlinePanelTextColor]) isEqual:@"#123456"] && app.batchFontSizeSlider.doubleValue==21 && app.batchWidthSlider.doubleValue==420,@"legacy custom color and dimensions survive migration");
    Require(fabs([app inlinePanelFillColor].alphaComponent-.2)<.001 && [app inlinePanelTextColor].alphaComponent==1,@"only backgrounds share opacity, text remains opaque");
    SubtitleTestControl *choice=[SubtitleTestControl new];
    for(NSInteger i=0;i<4;i++){
        choice.tag=i;[app selectBatchSwatch:(NSButton *)choice];
        Require([app inlineThemeIndex]==i && !app.batchTextColorCustomized && SameColor([app inlinePanelTextColor],FYSubtitleThemeText(i)),@"palette selection restores its text color");
        Require([app captionThemeIndex]==0 && app.captionUpdates==0 && app.ocrUpdates==0 && !app.batchAppearanceTimer,@"inline palette avoids caption/OCR work and layout scheduling");
    }
    choice.tag=2;[app selectBatchSwatch:(NSButton *)choice];
    choice.tag=1;[app selectCaptionSwatch:(NSButton *)choice];
    Require([app inlineThemeIndex]==2 && [app captionThemeIndex]==1,@"caption palette selection leaves inline palette independent");
    app.batchTextColorWell.color=FYAppearanceColorFromHex(@"#987654",NSColor.blackColor);[app controlValueChanged:app.batchTextColorWell];
    Require(app.batchTextColorCustomized,@"color-well action records a customization");
    NSDictionary *saved=[app subtitleAppearanceSettings];SubtitleSettingsApp *reopened=SettingsApp();[reopened loadSubtitleAppearanceSettings:saved];
    Require([reopened inlineThemeIndex]==2 && [reopened captionThemeIndex]==1 && reopened.batchTextColorCustomized && SameColor([reopened inlinePanelTextColor],app.batchTextColorWell.color),@"independent themes and custom color survive restart serialization");
    [reopened resetBatchTextColor:nil];Require(!reopened.batchTextColorCustomized && SameColor([reopened inlinePanelTextColor],FYSubtitleThemeText(2)),@"follow-style removes custom color without changing selected palette");
    [reopened loadSubtitleAppearanceSettings:@{@"batchTextColor":@"#593E2B"}];Require(!reopened.batchTextColorCustomized,@"legacy default brown remains a followed style");
    [reopened loadSubtitleAppearanceSettings:@{@"batchTheme":@99,@"captionTheme":@-2,@"batchTextColor":@"invalid"}];Require([reopened inlineThemeIndex]==3 && [reopened captionThemeIndex]==3 && SameColor([reopened inlinePanelTextColor],FYAdventureColor(@"ink")),@"invalid saved themes/colors fall back safely");
    Require(NSApp==nil && !app.mainWindow && !app.captionPanel,@"headless suite never creates an application or window");
    NSLog(@"PASS: subtitle appearance defaults, legacy migration, independent palette actions, custom color/follow, restart serialization, opacity and invalid saved values (headless)");
} return 0; }
