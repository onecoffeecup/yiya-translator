#pragma once
#import <Foundation/Foundation.h>
// Original local cycle values only; no mutable runtime state or callback source.
@interface FYRealtimeRecognitionFrame : NSObject
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID inputEpoch:(NSUInteger)epoch
    captureCard:(BOOL)captureCard language:(NSInteger)language cycleStart:(NSDate *)cycleStart;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) uint32_t windowID;
@property(nonatomic, readonly) NSUInteger inputEpoch;
@property(nonatomic, readonly) BOOL captureCard;
@property(nonatomic, readonly) NSInteger language;
@property(nonatomic, strong, readonly) NSDate *cycleStart;
@end
