#import "FYRealtimeRecognitionFrame.h"
@implementation FYRealtimeRecognitionFrame
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID inputEpoch:(NSUInteger)epoch
    captureCard:(BOOL)captureCard language:(NSInteger)language cycleStart:(NSDate *)cycleStart {
    if ((self=[super init])) { _generation=generation; _windowID=windowID; _inputEpoch=epoch;
        _captureCard=captureCard; _language=language; _cycleStart=cycleStart; }
    return self;
}
@end
