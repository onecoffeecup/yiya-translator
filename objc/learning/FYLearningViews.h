#import <Cocoa/Cocoa.h>
#import "FYAdventureTheme.h"
NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void FYMountLearningPage(NSArray<NSView *> *pages, NSView *host, NSInteger index);
FOUNDATION_EXPORT void FYUpdateLearningPageSelection(NSArray<NSView *> *pages, NSArray<NSButton *> *buttons, NSInteger index);
// Small vector action/status icons; remain crisp at Retina scale.
FOUNDATION_EXPORT NSImage *FYAdventureSymbolImage(NSString *symbol, NSColor *color);

// Page/card contents stretch within their padded parent and wrap long text.
@interface FYLearningStackView : NSStackView
@end

@interface FYLearningRowView : NSStackView
@end

// Two columns at normal width, one column at compact window sizes.
@interface FYLearningColumnsView : NSStackView
@property(nonatomic) CGFloat leftFraction;
@property(nonatomic) CGFloat compactWidth;
// Opt in for settings whose reviewed column ratio must outrank native control hugging.
@property(nonatomic) NSLayoutPriority columnWidthPriority;
@end

// Fit the captured frame to the available width, without image pixels sizing the window.
@interface FYCapturePreviewView : NSImageView
@end

// Deterministic desktop buttons rather than platform-dependent bezel styling.
@interface FYWorkspaceButton : NSButton
@property(nonatomic) BOOL primary;
@property(nonatomic) BOOL darkSurface;
@property(nonatomic) BOOL accent;
@property(nonatomic) BOOL navigation;
@property(nonatomic) NSInteger artworkIndex;
@end

// Native selectable palette cards and a sample-only subtitle preview.
FOUNDATION_EXPORT NSColor *FYSubtitleThemeBackground(NSInteger index, CGFloat alpha);
FOUNDATION_EXPORT NSColor *FYSubtitleThemeText(NSInteger index);
FOUNDATION_EXPORT NSColor *FYSubtitleThemeBorder(NSInteger index);
@interface FYSubtitleStyleButton : NSButton
@property(nonatomic) NSInteger themeIndex;
@end
@interface FYSubtitleModeButton : NSButton
@end
@interface FYSubtitleDisclosureButton : NSButton
@end
@interface FYSubtitleSliderCell : NSSliderCell
@end
@interface FYSubtitleColorWell : NSColorWell
@end
@interface FYSubtitleFollowButton : FYWorkspaceButton
@end
@interface FYSubtitleAppearancePreview : FYAdventurePanel
@property(nonatomic) BOOL inlineMode;
@property(nonatomic) BOOL showsHeightLimitExample;
@property(nonatomic, strong) NSColor *subtitleFill;
@property(nonatomic, strong) NSColor *subtitleInk;
@property(nonatomic, strong) NSColor *subtitleBorder;
@property(nonatomic) CGFloat subtitleSize;
@property(nonatomic) CGFloat subtitleWidth;
@property(nonatomic) CGFloat subtitleHeight;
@property(nonatomic, strong, readonly) NSTextField *translationLabel;
@property(nonatomic, copy, readonly) NSArray<FYAdventurePanel *> *translationSurfaces;
@property(nonatomic, copy, readonly) NSArray<FYAdventurePanel *> *sourcePanels;
- (void)refreshSample;
@end

FOUNDATION_EXPORT NSAttributedStringKey const FYSourceHoverAttributeName;

@interface FYSelectableSourceTextView : NSTextView
@property(nonatomic, readonly) BOOL trackingSelection;
- (void)dismissSourceHover;
@property(nonatomic, copy, nullable) void (^didFinishSelection)(void);
@property(nonatomic, copy, nullable) void (^willBeginSelection)(void);
@property(nonatomic, copy, nullable) void (^didClickAtCharacterIndex)(NSUInteger characterIndex);
@end

// A native, selectable source block that wraps to its actual width and lets the
// surrounding reading document scroll. No fixed empty viewport for short text.
@interface FYSourceReadingView : NSView
@property(nonatomic, strong, readonly) FYSelectableSourceTextView *textView;
@end

// NSTextView document sizing follows its clip view, including after window resize.
FOUNDATION_EXPORT void FYConfigureSourceTextView(NSTextView *textView, NSScrollView *scrollView, CGFloat fontSize);
NS_ASSUME_NONNULL_END
