#import <Cocoa/Cocoa.h>
#import "FYReferenceDictionary.h"
// A self-contained lookup context: never changes the live sentence or its reference UI.
@interface FYSavedWordReferenceView : NSStackView
- (void)loadWord:(NSString *)word reading:(NSString *)reading dictionary:(FYReferenceDictionary *)dictionary;
@end
