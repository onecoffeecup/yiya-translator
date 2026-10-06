#import <Cocoa/Cocoa.h>
@interface FYStudyOverlayPanel : NSPanel
@property(nonatomic,copy) void (^onEscape)(void);
@end

// The header drags the window; controls keep their own mouse handling.
@interface FYOverlayDragHeader : NSStackView
@end
