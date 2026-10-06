#import <Cocoa/Cocoa.h>
#import "FYAdventureTheme.h"
NS_ASSUME_NONNULL_BEGIN

// Page/card contents stretch within their padded parent and wrap long text.
@interface FYLearningStackView : NSStackView
@end

@interface FYLearningRowView : NSStackView
@end

// Two columns at normal width, one column at compact window sizes.
@interface FYLearningColumnsView : NSStackView
@property(nonatomic) CGFloat leftFraction;
@property(nonatomic) CGFloat compactWidth;
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

FOUNDATION_EXPORT NSAttributedStringKey const FYSourceHoverAttributeName;

@interface FYSelectableSourceTextView : NSTextView
@property(nonatomic, readonly) BOOL trackingSelection;
- (void)dismissSourceHover;
@property(nonatomic, copy, nullable) void (^didFinishSelection)(void);
@property(nonatomic, copy, nullable) void (^willBeginSelection)(void);
@property(nonatomic, copy, nullable) void (^didClickAtCharacterIndex)(NSUInteger characterIndex);
@end

// NSTextView document sizing follows its clip view, including after window resize.
FOUNDATION_EXPORT void FYConfigureSourceTextView(NSTextView *textView, NSScrollView *scrollView, CGFloat fontSize);
NS_ASSUME_NONNULL_END
