#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface FYAppUpdater : NSObject <NSMenuItemValidation>
- (void)addItemsToApplicationMenu:(NSMenu *)menu;
- (void)start;
@end
NS_ASSUME_NONNULL_END
