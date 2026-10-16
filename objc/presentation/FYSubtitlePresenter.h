#pragma once
#import "../app/FYAppSupport.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context and peer actions. Capture, OCR and translation stay with the host.
@protocol FYSubtitlePresenterHost <NSObject>
@property(nonatomic, strong) NSSlider *captionFontSizeSlider;
@property(nonatomic, strong) NSSlider *captionHeightSlider;
@property(nonatomic, strong) NSSlider *captionOpacitySlider;
@property(nonatomic) BOOL captionTextColorCustomized;
@property(nonatomic, strong) NSColorWell *captionTextColorWell;
@property(nonatomic, strong) NSSegmentedControl *captionThemeControl;
@property(nonatomic, strong) NSSlider *captionWidthSlider;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic) BOOL running;
- (void)configureStudyOverlay:(NSPanel *)panel;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSView *)card;
- (void)refreshOverlayVisibility:(id)sender;
- (void)refreshInlinePanelAppearance;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (void)updateCaptionAppearance;
@end

// Sole owner of subtitle panels and their presentation lifecycle.
@interface FYSubtitlePresenter : NSObject
@property(nonatomic, weak) id<FYSubtitlePresenterHost> host;
- (instancetype)initWithHost:(id<FYSubtitlePresenterHost>)host;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewBrand;
@property(nonatomic, strong) FYAdventurePanel *captionAppearancePreviewContainer;
@property(nonatomic, strong) NSPanel *captionAppearancePreviewPanel;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewText;
@property(nonatomic, strong) NSTextField *captionBrandLabel;
@property(nonatomic, strong) NSView *captionContainer;
@property(nonatomic) BOOL captionDockHasAnchor;
@property(nonatomic, strong) NSPanel *captionDockPanel;
@property(nonatomic, strong) NSButton *captionHideButton;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic) BOOL captionPanelShownByUser;
@property(nonatomic) BOOL captionSuppressedForUIMode;
@property(nonatomic, strong) NSTextField *captionTextLabel;
- (void)createCaptionWindow;
- (void)showCaptionAppearancePreview:(id)sender;
- (void)updateCaptionAppearancePreview;
- (void)anchorCaptionDockToCaption;
- (void)hideCaptionPanel:(id)sender;
- (void)showCaptionPanel:(id)sender;
- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode;
- (BOOL)captionPanelShouldBeHidden;
- (NSInteger)captionThemeIndex;
- (NSColor *)captionBackgroundColorWithAlpha:(CGFloat)alpha;
- (NSColor *)captionThemeTextColor;
- (NSColor *)captionTextColor;
- (NSColor *)captionSecondaryTextColor;
- (NSColor *)captionBorderColor;
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status;
- (void)setCaptionDisplayText:(NSString *)text;
- (void)updateCaptionAppearance;
- (void)resizeCaptionWindowForText:(NSString *)text;
- (void)toggleCaptionCollapsed:(id)sender;
- (void)createCaptionDock;
@end
#pragma clang diagnostic pop
