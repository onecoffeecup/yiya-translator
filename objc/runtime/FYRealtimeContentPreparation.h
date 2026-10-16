#pragma once
#import "FYRealtimeContentPreparationHost.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Stateless stage. Existing owners retain every mutable state field.
@interface FYRealtimeContentPreparation : NSObject
- (FYPreparedRealtimeContent *)prepareText:(NSString *)ocrText items:(NSArray<OCRTextItem *> *)ocrBlocks modalItems:(NSArray<OCRTextItem *> *)modalScopedBlocks duration:(NSTimeInterval)ocrDuration language:(NSInteger)languageSegment trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id<FYRealtimeContentPreparationHost>)runtimeHost;
@end
#pragma clang diagnostic pop
