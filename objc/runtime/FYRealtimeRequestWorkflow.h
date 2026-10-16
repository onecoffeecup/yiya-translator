#pragma once
#import "FYRealtimeRequestHost.h"
#import "FYRealtimeResultDelivery.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
@class FYRealtimeResultDelivery;
@protocol FYRealtimeRequestRuntime <FYRealtimeResultRuntime>
- (FYRealtimeResultDelivery *)resultDelivery;
@end

// Stateless stage. Existing owners retain every mutable state field.
@interface FYRealtimeRequestWorkflow : NSObject
- (void)submitContent:(FYPreparedRealtimeContent *)prepared items:(NSArray<OCRTextItem *> *)ocrBlocks duration:(NSTimeInterval)ocrDuration frame:(FYRealtimeRecognitionFrame *)frame trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeRequestRuntime>)runtime host:(id<FYRealtimeRequestHost>)runtimeHost;
@end
#pragma clang diagnostic pop
