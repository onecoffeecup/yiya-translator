#import "FYPreparedRealtimeContent.h"
@implementation FYPreparedRealtimeContent
- (instancetype)initWithNormalized:(NSString *)normalized items:(NSArray<OCRTextItem *> *)items mode:(NSInteger)mode {
    if ((self=[super init])) { _normalized=normalized; _items=items; _mode=mode; }
    return self;
}
@end
