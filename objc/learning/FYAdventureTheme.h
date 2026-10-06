#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN

// Yiya cream-and-brown theme. Keep text native and artwork decorative.
FOUNDATION_EXPORT NSFont *FYUIFont(CGFloat size, NSFontWeight weight);
FOUNDATION_EXPORT NSFont *FYJapaneseFont(CGFloat size);
FOUNDATION_EXPORT NSFont *FYFontForText(NSString *text, CGFloat size, NSFontWeight weight);
FOUNDATION_EXPORT NSColor *FYAdventureColor(NSString *token);
FOUNDATION_EXPORT NSBezierPath *FYAdventureOutline(NSRect rect, CGFloat corner);
FOUNDATION_EXPORT void FYDrawAdventureArt(NSInteger artwork, NSRect destination);

@interface FYAdventurePanel : NSView
@property(nonatomic, strong) NSColor *fillColor;
@property(nonatomic, strong) NSColor *edgeColor;
@property(nonatomic) BOOL speechBubble;
@end

@interface FYAdventureArtView : NSView
@property(nonatomic) NSInteger artwork;
@end

@interface FYAdventureBanner : NSView
@end

@interface FYAdventureStack : NSStackView
@property(nonatomic, strong) NSColor *fillColor;
@end

NS_ASSUME_NONNULL_END
